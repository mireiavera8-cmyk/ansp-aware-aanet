% M3F_RESILIENT_TOPOLOGY  Same-ANSP-backup-aware soft-edge greedy MCLP sweep.
%
% Extends M3b's objective so that every border hotspot is rewarded for having
% a SECOND station from the SAME ANSP covering it well: a different-ANSP backup
% would still trigger the break-before-make inter-ANSP handover this thesis
% studies. This is a scoped instance of reliability/backup facility location
% (Snyder & Daskin, 2005, Transportation Science), applied to the hotspot term
% only. For hotspot h and ANSP o, TOP1/TOP2 are the best and second-best dual-
% anchor scores among selected stations of o; resilient_score(h) =
% max_o min(TOP1_h,o, TOP2_h,o). Running max/second-max are non-decreasing, so
% the resilience curve is monotonic in N and every marginal gain is >= 0.
% Conservative scenario only; same pool and siting constraints as M3b.
%
% INPUT  : tagged_data, COL, ansp_polys (M1); border_hotspots (M2b); results_m3b
%          (its conservative order is replayed on this metric as reference); config
% OUTPUT : results.selected_order / .coverage_pct / .resilient_hotspot_pct,
%          results.aware_reference.*; results/topology_study_resilient.mat

function results = m3f_resilient_topology(tagged_data, COL, ansp_polys, ...
    border_hotspots, results_m3b, config)

    fprintf('[M3f] Resilient (same-ANSP-backup) topology study starting...\n');

    grid_points = build_adaptive_grid(tagged_data, COL, config);
    anchors     = compute_hotspot_anchors(border_hotspots, ansp_polys);

    [R_inner_km, R_outer_km] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);
    fprintf('[M3f] Conservative scenario only (F=%.1fdB): R_inner=%.0fkm, R_outer=%.0fkm\n', ...
        config.fade_margin_db_hi, R_inner_km, R_outer_km);

    % Candidate pool: grid points plus hotspot centroids, ANSP-restricted (as M3b).
    n_hotspots = numel(border_hotspots);
    candidate_pool = grid_points;
    for h = 1:n_hotspots
        entry.lat = border_hotspots(h).centroid_lat;
        entry.lon = border_hotspots(h).centroid_lon;
        entry.weight = 0;
        candidate_pool(end+1) = entry; %#ok<AGROW>
    end
    candidates = filter_valid_candidates(candidate_pool, ansp_polys);
    fprintf('[M3f] Valid candidate sites (grid + hotspot centroids, ANSP-restricted): %d\n', numel(candidates));

    n_before_water = numel(candidates);
    candidates = exclude_water_sites(candidates, config.terrain_data_path);
    fprintf('[M3f] Water-site exclusion (hard feasibility): %d -> %d candidates (%d removed)\n', ...
        n_before_water, numel(candidates), n_before_water - numel(candidates));

    difficulty_norm = load_difficulty(candidates, config.terrain_data_path, config.dme_beacons, config.dme_cost_weight);
    fprintf('[M3f] Siting difficulty (0-1, terrain+DME): median=%.2f, %d/%d sites >0.5\n', ...
        median(difficulty_norm), sum(difficulty_norm>0.5), numel(difficulty_norm));

    n_channels_avail = floor(config.spectrum_mhz / config.channel_bw_mhz);
    D_min_km_hi = free_space_D_min(config.gs_radius_km, config.ci_required_db_max);

    hotspot_weight = config.hotspot_weight_alpha * [border_hotspots.count]';

    [selected_order, coverage_pct, resilient_pct] = greedy_mclp_resilient(candidates, ...
        grid_points, anchors, hotspot_weight, difficulty_norm, config.terrain_cost_weight, ...
        R_inner_km, R_outer_km, config.n_max_sweep, D_min_km_hi, n_channels_avail);
    fprintf('[M3f] Greedy MCLP (grid + same-ANSP-backup hotspot resilience, terrain-cost-weighted, spectrum-enforced): swept N=1..%d\n', config.n_max_sweep);
    fprintf('[M3f] Avg terrain difficulty of selected sites: %.3f (pool median %.3f)\n', ...
        mean(difficulty_norm(selected_order)), median(difficulty_norm));

    % "Before" reference: M3b's own placement scored on the resilience metric.
    resilient_pct_aware = resilient_hotspot_coverage_curve(results_m3b.conservative.candidates, ...
        results_m3b.conservative.selected_order, anchors, hotspot_weight, R_inner_km, R_outer_km, config.n_max_sweep);

    fprintf('[M3f] ---- SAME-ANSP-BACKUP RESILIENCE: THIS PLACEMENT vs M3b ANSP-AWARE ----\n');
    fprintf('[M3f] %3s %16s %16s %10s\n', 'N', 'Resilient Cov%', 'M3b Cov%', 'Delta(pp)');
    for n = 1:config.n_max_sweep
        fprintf('[M3f] %3d %15.1f%% %15.1f%% %9.1f\n', ...
            n, resilient_pct(n), resilient_pct_aware(n), resilient_pct(n) - resilient_pct_aware(n));
    end

    results.candidates             = candidates;
    results.selected_order         = selected_order;
    results.coverage_pct           = coverage_pct;
    results.resilient_hotspot_pct  = resilient_pct;
    results.aware_reference.resilient_hotspot_pct = resilient_pct_aware;
    results.alpha                  = config.hotspot_weight_alpha;
    results.R_inner_km             = R_inner_km;
    results.R_outer_km             = R_outer_km;
    results.fade_margin_db         = config.fade_margin_db_hi;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'topology_study_resilient.mat'), 'results');
    fprintf('[M3f] Saved: %s\n', fullfile(config.output_data, 'topology_study_resilient.mat'));
    fprintf('[M3f] Resilient topology study complete.\n');

end


% GREEDY_MCLP_RESILIENT  grid_gain + alpha-weighted same-ANSP-backup resilience
% gain, using the TOP1/TOP2-per-ANSP metric described in the file header.
function [selected_order, coverage_pct, resilient_pct] = greedy_mclp_resilient(candidates, ...
    grid_points, anchors, hotspot_weight, difficulty_norm, terrain_cost_weight, R_inner_km, R_outer_km, n_max, ...
    D_min_km, n_channels_avail)

    n_cand = numel(candidates);
    cand_lat = [candidates.lat]';
    cand_lon = [candidates.lon]';

    grid_lat = [grid_points.lat]';
    grid_lon = [grid_points.lon]';
    grid_weight = [grid_points.weight]';

    grid_prob = zeros(n_cand, numel(grid_points));
    for i = 1:n_cand
        d = haversine_km(cand_lat(i), cand_lon(i), grid_lat, grid_lon);
        grid_prob(i,:) = connection_probability(d, R_inner_km, R_outer_km);
    end

    n_hs = numel(anchors);
    HP = zeros(n_cand, n_hs);
    for i = 1:n_cand
        dA = haversine_km(cand_lat(i), cand_lon(i), [anchors.lat_a]', [anchors.lon_a]');
        dB = haversine_km(cand_lat(i), cand_lon(i), [anchors.lat_b]', [anchors.lon_b]');
        pA = connection_probability(dA, R_inner_km, R_outer_km);
        pB = connection_probability(dB, R_inner_km, R_outer_km);
        HP(i,:) = min(pA, pB)';
    end

    [ansp_names_u, ~, cand_ansp_idx] = unique({candidates.ansp_name});
    n_ansp = numel(ansp_names_u);

    total_weight = sum(grid_weight) + sum(hotspot_weight);
    cost_divisor = 1 + terrain_cost_weight * difficulty_norm;   % see setup_config.m
    best_grid = zeros(numel(grid_points), 1);
    top1_ansp = zeros(n_hs, n_ansp);
    top2_ansp = zeros(n_hs, n_ansp);
    resilient_now = zeros(n_hs, 1);   % = max_o min(top1,top2), all zero initially

    selected_order = zeros(n_max, 1);
    coverage_pct   = zeros(n_max, 1);
    resilient_pct  = zeros(n_max, 1);
    picked = false(n_cand, 1);

    for step = 1:n_max
        picked_lat = cand_lat(picked); picked_lon = cand_lon(picked);
        gains = zeros(n_cand, 1);
        colors_needed = zeros(n_cand, 1);
        for i = 1:n_cand
            if picked(i), continue; end
            colors_needed(i) = spectrum_colors_if_added(picked_lat, picked_lon, cand_lat(i), cand_lon(i), D_min_km);
            if colors_needed(i) > n_channels_avail
                gains(i) = -Inf;
                continue;
            end
            grid_gain = sum(grid_weight .* max(grid_prob(i,:)' - best_grid, 0));

            % Trial update of ANSP o_i's TOP1/TOP2 if candidate i were added.
            o_i = cand_ansp_idx(i);
            newval = HP(i,:)';
            t1 = top1_ansp(:,o_i); t2 = top2_ansp(:,o_i);
            mask1 = newval > t1;
            t2(mask1) = t1(mask1); t1(mask1) = newval(mask1);
            mask2 = ~mask1 & newval > t2;
            t2(mask2) = newval(mask2);
            resilient_new_oi = min(t1, t2);
            resilient_new_total = max(resilient_now, resilient_new_oi);   % valid: new min(t1,t2) dominates o_i's old one

            resilient_gain = sum(hotspot_weight .* max(resilient_new_total - resilient_now, 0));
            gains(i) = (grid_gain + resilient_gain) / cost_divisor(i);   % difficulty discounts SELECTION only
        end

        if all(gains(~picked) == -Inf)
            colors_needed(picked) = Inf;
            [~, best] = min(colors_needed);   % all break the budget: least-bad site
        else
            [~, best] = max(gains);
        end
        picked(best) = true;
        best_grid = max(best_grid, grid_prob(best,:)');

        o_b = cand_ansp_idx(best);
        newval = HP(best,:)';
        t1 = top1_ansp(:,o_b); t2 = top2_ansp(:,o_b);
        mask1 = newval > t1;
        t2(mask1) = t1(mask1); t1(mask1) = newval(mask1);
        mask2 = ~mask1 & newval > t2;
        t2(mask2) = newval(mask2);
        top1_ansp(:,o_b) = t1; top2_ansp(:,o_b) = t2;
        resilient_now = max(resilient_now, min(t1, t2));

        selected_order(step) = best;
        coverage_pct(step)  = 100 * (sum(grid_weight .* best_grid) + sum(hotspot_weight .* resilient_now)) / total_weight;
        resilient_pct(step) = 100 * sum(hotspot_weight .* resilient_now) / max(sum(hotspot_weight), eps);
    end

end


% RESILIENT_HOTSPOT_COVERAGE_CURVE  Scores a fixed station order (M3b's) on the
% same-ANSP-backup metric; needs that order's own candidate list for ansp_name.
function resilient_pct = resilient_hotspot_coverage_curve(fixed_candidates, selected_order, ...
    anchors, hotspot_weight, R_inner_km, R_outer_km, n_max)

    cand_lat = [fixed_candidates.lat]';
    cand_lon = [fixed_candidates.lon]';
    [ansp_names_u, ~, cand_ansp_idx] = unique({fixed_candidates.ansp_name}); %#ok<ASGLU>
    n_ansp = numel(ansp_names_u);
    n_hs = numel(anchors);

    top1_ansp = zeros(n_hs, n_ansp);
    top2_ansp = zeros(n_hs, n_ansp);
    resilient_now = zeros(n_hs, 1);
    resilient_pct = zeros(n_max, 1);

    for step = 1:n_max
        si = selected_order(step);
        dA = haversine_km(cand_lat(si), cand_lon(si), [anchors.lat_a]', [anchors.lon_a]');
        dB = haversine_km(cand_lat(si), cand_lon(si), [anchors.lat_b]', [anchors.lon_b]');
        pA = connection_probability(dA, R_inner_km, R_outer_km);
        pB = connection_probability(dB, R_inner_km, R_outer_km);
        hp = min(pA, pB);

        o = cand_ansp_idx(si);
        t1 = top1_ansp(:,o); t2 = top2_ansp(:,o);
        mask1 = hp > t1;
        t2(mask1) = t1(mask1); t1(mask1) = hp(mask1);
        mask2 = ~mask1 & hp > t2;
        t2(mask2) = hp(mask2);
        top1_ansp(:,o) = t1; top2_ansp(:,o) = t2;
        resilient_now = max(resilient_now, min(t1, t2));

        resilient_pct(step) = 100 * sum(hotspot_weight .* resilient_now) / max(sum(hotspot_weight), eps);
    end

end
