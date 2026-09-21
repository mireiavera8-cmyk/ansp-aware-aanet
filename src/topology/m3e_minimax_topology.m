% M3E_MINIMAX_TOPOLOGY  Worst-case (minimax) hotspot-protecting station placement.
%
% M3b maximises a SUM of hotspot coverage, which can leave one hotspot badly
% covered while the total stays high. This module instead minimises the
% worst-covered hotspot using the greedy 2-approximation for weighted k-center
% (Gonzalez, 1985; Hochbaum & Shmoys, 1985): at each step take the hotspot
% with the largest weighted residual risk weight*(1 - best_prob) and add the
% candidate that covers THAT hotspot best. Same dual-anchor probability model,
% soft-edge radii, candidate pool, siting constraints and conservative scenario
% as M3b/M3d. Reported metric max_risk_pct(N) = 100*max_h(1 - best_prob_h), an
% unweighted percentage. The 2-approximation guarantee holds for the hard-cutoff
% k-center problem and is not proven for the soft-edge model.
%
% INPUT  : tagged_data, COL (M1); ansp_polys; border_hotspots (M2b); results_m3b
%          (its conservative order is replayed on this metric as reference); config
% OUTPUT : results.selected_order / .max_risk_pct / .hotspot_coverage_pct /
%          .coverage_pct, results.mclp_reference.*; results/topology_study_minimax.mat

function results = m3e_minimax_topology(tagged_data, COL, ansp_polys, ...
    border_hotspots, results_m3b, config)

    fprintf('[M3e] Minimax (worst-case) topology starting...\n');

    grid_points = build_adaptive_grid(tagged_data, COL, config);
    anchors     = compute_hotspot_anchors(border_hotspots, ansp_polys);
    [R_inner_hi, R_outer_hi] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);

    n_hotspots = numel(border_hotspots);
    candidate_pool = grid_points;
    for h = 1:n_hotspots
        entry.lat = border_hotspots(h).centroid_lat;
        entry.lon = border_hotspots(h).centroid_lon;
        entry.weight = 0;
        candidate_pool(end+1) = entry; %#ok<AGROW>
    end
    candidates = filter_valid_candidates(candidate_pool, ansp_polys);
    fprintf('[M3e] Valid candidate sites (same pool convention as M3b/M3d): %d\n', numel(candidates));

    n_before_water = numel(candidates);
    candidates = exclude_water_sites(candidates, config.terrain_data_path);
    fprintf('[M3e] Water-site exclusion (hard feasibility): %d -> %d candidates (%d removed)\n', ...
        n_before_water, numel(candidates), n_before_water - numel(candidates));

    difficulty_norm = load_difficulty(candidates, config.terrain_data_path, config.dme_beacons, config.dme_cost_weight);
    fprintf('[M3e] Siting difficulty (0-1, terrain+DME): median=%.2f, %d/%d sites >0.5\n', ...
        median(difficulty_norm), sum(difficulty_norm>0.5), numel(difficulty_norm));

    n_channels_avail = floor(config.spectrum_mhz / config.channel_bw_mhz);
    D_min_km_hi = free_space_D_min(config.gs_radius_km, config.ci_required_db_max);

    [selected_order, max_risk_pct, hotspot_coverage_pct, unreachable] = greedy_minimax_hotspot(...
        candidates, border_hotspots, anchors, difficulty_norm, config.terrain_cost_weight, ...
        R_inner_hi, R_outer_hi, config.n_max_sweep, D_min_km_hi, n_channels_avail);
    fprintf('[M3e] Greedy minimax (k-center, terrain-cost-weighted, spectrum-enforced): swept N=1..%d in one pass\n', config.n_max_sweep);
    fprintf('[M3e] Avg terrain difficulty of selected sites: %.3f (pool median %.3f)\n', ...
        mean(difficulty_norm(selected_order)), median(difficulty_norm));

    coverage_pct = grid_coverage_curve(candidates, selected_order, grid_points, ...
        R_inner_hi, R_outer_hi, config.n_max_sweep);

    % "Before" reference: M3b's own placement replayed under the worst-case metric.
    weight = [border_hotspots.count]';
    mclp_scen = results_m3b.conservative;
    [mclp_max_risk_pct, mclp_hotspot_coverage_pct] = evaluate_max_risk_curve(...
        mclp_scen.candidates, mclp_scen.selected_order, anchors, weight, unreachable, ...
        R_inner_hi, R_outer_hi, config.n_max_sweep);

    fprintf('[M3e] ---- WORST-CASE COMPARISON (N=1..%d) ----\n', config.n_max_sweep);
    fprintf('[M3e] %3s %18s %18s\n', 'N', 'max_risk% (M3b)', 'max_risk% (minimax)');
    for n = 1:config.n_max_sweep
        fprintf('[M3e] %3d %18.1f %18.1f\n', n, mclp_max_risk_pct(n), max_risk_pct(n));
    end

    results.candidates             = candidates;
    results.selected_order         = selected_order;
    results.max_risk_pct           = max_risk_pct;
    results.hotspot_coverage_pct   = hotspot_coverage_pct;
    results.coverage_pct           = coverage_pct;
    results.mclp_reference.max_risk_pct         = mclp_max_risk_pct;
    results.mclp_reference.hotspot_coverage_pct = mclp_hotspot_coverage_pct;
    results.unreachable_hotspot_mask = unreachable;
    results.n_unreachable_hotspots   = sum(unreachable);
    results.fade_margin_db_hi      = config.fade_margin_db_hi;
    results.R_inner_km             = R_inner_hi;
    results.R_outer_km             = R_outer_hi;
    results.config_snapshot        = config;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'topology_study_minimax.mat'), 'results');
    fprintf('[M3e] Saved: %s\n', fullfile(config.output_data, 'topology_study_minimax.mat'));
    fprintf('[M3e] Minimax topology complete.\n');

end


% GREEDY_MINIMAX_HOTSPOT  k-center-style greedy: pick the bottleneck hotspot,
% then the site covering it best. Hotspots no single candidate can reach at all
% (anchors > 2*R_outer apart) are excluded from the worst-case search, otherwise
% the loop would fixate on them forever; they still count in hotspot_coverage_pct.
function [selected_order, max_risk_pct, hotspot_coverage_pct, unreachable] = greedy_minimax_hotspot(...
    candidates, border_hotspots, anchors, difficulty_norm, terrain_cost_weight, R_inner_km, R_outer_km, n_max, ...
    D_min_km, n_channels_avail)

    n_cand = numel(candidates);
    cand_lat = [candidates.lat]';
    cand_lon = [candidates.lon]';
    n_hs = numel(border_hotspots);
    weight = [border_hotspots.count]';
    total_weight = sum(weight);

    HP = zeros(n_cand, n_hs);
    for i = 1:n_cand
        dA = haversine_km(cand_lat(i), cand_lon(i), [anchors.lat_a]', [anchors.lon_a]');
        dB = haversine_km(cand_lat(i), cand_lon(i), [anchors.lat_b]', [anchors.lon_b]');
        pA = connection_probability(dA, R_inner_km, R_outer_km);
        pB = connection_probability(dB, R_inner_km, R_outer_km);
        HP(i,:) = min(pA, pB)';
    end

    max_possible = max(HP, [], 1)';           % n_hs x 1: best any single candidate could give
    unreachable  = max_possible <= 0;
    n_unreachable = sum(unreachable);

    if n_unreachable > 0
        fprintf(['[M3e] WARNING: %d/%d hotspots are structurally unreachable by ANY single station\n' ...
                 '[M3e]          under this coverage model (dual-anchor separation exceeds R_outer=%.0fkm).\n' ...
                 '[M3e]          Excluded from the worst-case search (see file header); still counted in\n' ...
                 '[M3e]          hotspot_coverage_pct, so that curve will never reach 100%%.\n'], ...
                 n_unreachable, n_hs, R_outer_km);
    end

    cost_divisor = 1 + terrain_cost_weight * difficulty_norm;   % see setup_config.m

    best_prob = zeros(n_hs, 1);
    picked = false(n_cand, 1);
    selected_order = zeros(n_max, 1);
    max_risk_pct = zeros(n_max, 1);
    hotspot_coverage_pct = zeros(n_max, 1);

    for step = 1:n_max
        % A hotspot already at its max_possible ceiling cannot be improved by
        % any remaining candidate; drop it from the target search (its gap
        % still counts fully in max_risk_pct).
        capped = best_prob >= (max_possible - 1e-9);
        gap = 1 - best_prob;
        gap(unreachable | capped) = -Inf;

        % Live spectrum-budget gate, same mechanism as M3/M3b.
        picked_lat = cand_lat(picked); picked_lon = cand_lon(picked);
        colors_needed = zeros(n_cand,1);
        spectrum_ok = true(n_cand,1);
        for i = 1:n_cand
            if picked(i), continue; end
            colors_needed(i) = spectrum_colors_if_added(picked_lat, picked_lon, cand_lat(i), cand_lon(i), D_min_km);
            spectrum_ok(i) = colors_needed(i) <= n_channels_avail;
        end

        if all(gap == -Inf)
            % No targetable hotspot left: fall back to a plain MCLP-style step
            % (largest summed probability gain) so leftover stations still help.
            fallback_gain = sum(weight' .* max(HP - best_prob', 0), 2) ./ cost_divisor;
            fallback_gain(picked | ~spectrum_ok) = -Inf;
            if all(fallback_gain(~picked) == -Inf)
                colors_fallback = colors_needed; colors_fallback(picked) = Inf;
                [~, best] = min(colors_fallback);   % all break the budget: least-bad site
            else
                [~, best] = max(fallback_gain);
            end
        else
            max_gap = max(gap);
            tied = find(gap == max_gap);
            if numel(tied) > 1
                [~, tie_idx] = max(weight(tied));
                worst_h = tied(tie_idx);
            else
                worst_h = tied(1);
            end
            scores = HP(:, worst_h) ./ cost_divisor;   % difficulty discounts SELECTION only
            scores(picked | ~spectrum_ok) = -Inf;
            if all(scores(~picked) == -Inf)
                colors_fallback = colors_needed; colors_fallback(picked) = Inf;
                [~, best] = min(colors_fallback);
            else
                [~, best] = max(scores);
            end
        end

        picked(best) = true;
        best_prob = max(best_prob, HP(best,:)');
        selected_order(step) = best;

        reachable_risk = 1 - best_prob;
        reachable_risk(unreachable) = NaN;
        max_risk_pct(step) = 100 * max(reachable_risk, [], 'omitnan');
        hotspot_coverage_pct(step) = 100 * sum(weight .* best_prob) / total_weight;
    end

end


% EVALUATE_MAX_RISK_CURVE  Scores a fixed station order (M3b's) on the worst-case
% metric. The unreachable mask from the minimax run is reused so both curves
% ignore the same hotspots, even though the two candidate pools differ.
function [max_risk_pct, hotspot_coverage_pct] = evaluate_max_risk_curve(...
    candidates, selected_order, anchors, weight, unreachable, R_inner_km, R_outer_km, n_max)

    cand_lat = [candidates.lat]';
    cand_lon = [candidates.lon]';
    n_hs = numel(anchors);
    total_weight = sum(weight);

    best_prob = zeros(n_hs, 1);
    max_risk_pct = zeros(n_max, 1);
    hotspot_coverage_pct = zeros(n_max, 1);

    for step = 1:n_max
        si = selected_order(step);
        dA = haversine_km(cand_lat(si), cand_lon(si), [anchors.lat_a]', [anchors.lon_a]');
        dB = haversine_km(cand_lat(si), cand_lon(si), [anchors.lat_b]', [anchors.lon_b]');
        pA = connection_probability(dA, R_inner_km, R_outer_km);
        pB = connection_probability(dB, R_inner_km, R_outer_km);
        hp = min(pA, pB);
        best_prob = max(best_prob, hp);
        reachable_risk = 1 - best_prob;
        reachable_risk(unreachable) = NaN;
        max_risk_pct(step) = 100 * max(reachable_risk, [], 'omitnan');
        hotspot_coverage_pct(step) = 100 * sum(weight .* best_prob) / total_weight;
    end

end
