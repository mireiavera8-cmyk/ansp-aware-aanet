% M3B_ANSP_AWARE_TOPOLOGY  Border-hotspot-weighted soft-edge greedy MCLP sweep.
%
% Same greedy MCLP, soft-edge model, siting constraints and two fade-margin
% scenarios as m3_topology_study.m, with an alpha-weighted hotspot term added
% to the objective: grid_gain + alpha * hotspot_gain (greedy_mclp_dual).
% Hotspot credit is directional and dual-anchored: two anchors sit km_r90 from
% the hotspot centroid towards each ANSP's territory (compute_hotspot_anchors)
% and a station scores min(P(anchor_A), P(anchor_B)), so one site must be able
% to escort the crossing alone. Hotspot centroids join the candidate pool.
%
% INPUT  : tagged_data, COL, ansp_polys (M1); border_hotspots (M2b); naive_results
%          (M3 output, scored on the same hotspot metric, not modified); config
% OUTPUT : results.optimistic / .conservative, each with hotspot_coverage_pct(N)
%          for this and the naive topology; results/topology_study_ansp_aware.mat

function results = m3b_ansp_aware_topology(tagged_data, COL, ansp_polys, ...
    border_hotspots, naive_results, config)

    fprintf('[M3b] ANSP-aware topology study starting...\n');

    grid_points = build_adaptive_grid(tagged_data, COL, config);

    % Anchors depend only on hotspot geometry and polygon shapes, not on F.
    anchors = compute_hotspot_anchors(border_hotspots, ansp_polys);

    [R_inner_lo, R_outer_lo] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_lo);
    [R_inner_hi, R_outer_hi] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);

    % Spectrum budget enforced live at every greedy step (conservative C/I bound).
    n_channels_avail = floor(config.spectrum_mhz / config.channel_bw_mhz);
    D_min_km_hi = free_space_D_min(config.gs_radius_km, config.ci_required_db_max);

    fprintf('[M3b] ---- SCENARIO: OPTIMISTIC (F=%.1fdB) ----\n', config.fade_margin_db_lo);
    optimistic = run_scenario_aware(grid_points, ansp_polys, border_hotspots, anchors, ...
        R_inner_lo, R_outer_lo, naive_results.optimistic, config.hotspot_weight_alpha, ...
        D_min_km_hi, n_channels_avail, config);

    fprintf('[M3b] ---- SCENARIO: CONSERVATIVE (F=%.1fdB) ----\n', config.fade_margin_db_hi);
    conservative = run_scenario_aware(grid_points, ansp_polys, border_hotspots, anchors, ...
        R_inner_hi, R_outer_hi, naive_results.conservative, config.hotspot_weight_alpha, ...
        D_min_km_hi, n_channels_avail, config);

    results.optimistic           = optimistic;
    results.conservative         = conservative;
    results.fade_margin_db_lo    = config.fade_margin_db_lo;
    results.fade_margin_db_hi    = config.fade_margin_db_hi;
    results.hotspot_weight_alpha = config.hotspot_weight_alpha;
    results.border_hotspots      = border_hotspots;
    results.anchors              = anchors;
    results.config_snapshot      = config;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'topology_study_ansp_aware.mat'), 'results');
    fprintf('[M3b] Saved: %s\n', fullfile(config.output_data, 'topology_study_ansp_aware.mat'));
    fprintf('[M3b] ANSP-aware topology study complete.\n');

end


function scen = run_scenario_aware(grid_points, ansp_polys, border_hotspots, anchors, ...
    R_inner_km, R_outer_km, naive_scenario, alpha, D_min_km_hi, n_channels_avail, config)

    % Candidate pool: grid points plus hotspot centroids, ANSP-restricted.
    n_hotspots = numel(border_hotspots);
    candidate_pool = grid_points;
    for h = 1:n_hotspots
        entry.lat = border_hotspots(h).centroid_lat;
        entry.lon = border_hotspots(h).centroid_lon;
        entry.weight = 0;
        candidate_pool(end+1) = entry; %#ok<AGROW>
    end
    candidates = filter_valid_candidates(candidate_pool, ansp_polys);
    fprintf('[M3b] Valid candidate sites (grid + hotspot centroids, ANSP-restricted): %d\n', ...
        numel(candidates));

    n_before_water = numel(candidates);
    candidates = exclude_water_sites(candidates, config.terrain_data_path);
    fprintf('[M3b] Water-site exclusion (hard feasibility): %d -> %d candidates (%d removed)\n', ...
        n_before_water, numel(candidates), n_before_water - numel(candidates));

    difficulty_norm = load_difficulty(candidates, config.terrain_data_path, config.dme_beacons, config.dme_cost_weight);
    fprintf('[M3b] Siting difficulty (0-1, terrain+DME): median=%.2f, %d/%d sites >0.5\n', ...
        median(difficulty_norm), sum(difficulty_norm>0.5), numel(difficulty_norm));

    hotspot_weight = alpha * [border_hotspots.count]';
    fprintf('[M3b] Total hotspot demand weight: %.1f (vs. %.1f base grid weight), alpha=%.2f\n', ...
        sum(hotspot_weight), sum([grid_points.weight]), alpha);

    [selected_order, coverage_pct] = greedy_mclp_dual(candidates, grid_points, ...
        border_hotspots, anchors, hotspot_weight, difficulty_norm, config.terrain_cost_weight, ...
        R_inner_km, R_outer_km, config.n_max_sweep, D_min_km_hi, n_channels_avail);
    fprintf('[M3b] Greedy MCLP (grid + directional dual-anchor hotspot, soft-edge, terrain-cost-weighted, spectrum-enforced): swept N=1..%d\n', ...
        config.n_max_sweep);
    fprintf('[M3b] Avg terrain difficulty of selected sites: %.3f (pool median %.3f)\n', ...
        mean(difficulty_norm(selected_order)), median(difficulty_norm));

    % Dual-anchor hotspot coverage curves: this topology and the naive M3 one.
    hotspot_cov_aware = hotspot_coverage_curve_dual(candidates, selected_order, ...
        anchors, hotspot_weight, R_inner_km, R_outer_km, config.n_max_sweep);

    hotspot_cov_naive = hotspot_coverage_curve_dual(naive_scenario.candidates, ...
        naive_scenario.selected_order, anchors, hotspot_weight, R_inner_km, R_outer_km, ...
        config.n_max_sweep);

    fprintf('[M3b] ---- HOTSPOT DUAL-ANCHOR COVERAGE: ANSP-AWARE vs NAIVE ----\n');
    fprintf('[M3b] %3s %14s %14s %10s\n', 'N', 'Aware Cov%', 'Naive Cov%', 'Delta(pp)');
    for n = 1:config.n_max_sweep
        fprintf('[M3b] %3d %13.1f%% %13.1f%% %9.1f\n', ...
            n, hotspot_cov_aware(n), hotspot_cov_naive(n), ...
            hotspot_cov_aware(n) - hotspot_cov_naive(n));
    end

    scen.candidates             = candidates;
    scen.selected_order         = selected_order;
    scen.coverage_pct           = coverage_pct;
    scen.hotspot_coverage_pct   = hotspot_cov_aware;
    scen.hotspot_coverage_naive = hotspot_cov_naive;
    scen.alpha                  = alpha;
    scen.R_inner_km             = R_inner_km;
    scen.R_outer_km             = R_outer_km;

end
