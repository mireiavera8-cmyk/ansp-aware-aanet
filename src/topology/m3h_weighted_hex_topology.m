% M3H_WEIGHTED_HEX_TOPOLOGY  Traffic-weighted hexagonal lattice baseline.
%
% Same hex geometry, filtering, siting constraints and hotspot metric as
% m3c_literature_grid.m; the ONLY change is deployment order: descending local
% traffic weight within R_inner (traffic-led rollout) instead of outward from
% the corridor centroid. The lattice stays rigid and ANSP-blind, isolating
% whether demand awareness alone reduces the handover vulnerability.
%
% INPUT  : tagged_data, COL (M1), ansp_polys, border_hotspots (M2b), config
% OUTPUT : results.optimistic / .conservative (+ pre-constraint order);
%          results/topology_study_weighted_hex.mat

function results = m3h_weighted_hex_topology(tagged_data, COL, ansp_polys, border_hotspots, config)

    fprintf('[M3h] Traffic-weighted hex-grid baseline starting...\n');

    grid_points = build_hex_grid(config);
    fprintf('[M3h] Hex-grid points (R=%dkm circumradius): %d, before ANSP filtering\n', ...
        config.gs_radius_km, numel(grid_points));

    candidates = filter_valid_candidates(grid_points, ansp_polys);
    fprintf('[M3h] Valid hex-grid candidates (inside ANSP territory): %d\n', numel(candidates));

    demand_grid = build_adaptive_grid(tagged_data, COL, config);
    [R_inner_hi, R_outer_hi] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);
    local_weight = local_traffic_weight(candidates, demand_grid, R_inner_hi);

    % Gain key (higher is better): same raw_gain/(1+w*difficulty) form as the greedy modules.
    [difficulty_norm, dparts] = load_difficulty_hex(candidates, ...
        config.terrain_data_hex_path, config.dme_beacons, config.dme_cost_weight, true);
    fprintf('[M3h] Siting difficulty (0-1, terrain+DME): median=%.2f, %d/%d sites >0.5\n', ...
        median(difficulty_norm), sum(difficulty_norm>0.5), numel(difficulty_norm));

    score = local_weight(:) ./ (1 + config.terrain_cost_weight * difficulty_norm(:));
    [~, order] = sort(score, 'descend');

    n_unc = min(config.n_max_sweep, numel(order));
    selected_order_unconstrained = order(1:n_unc);

    [order, site_diag] = apply_siting_constraints(candidates, order, config);
    fprintf(['[M3h] Feasibility: %d water sites and %d spectrum-budget sites dropped ' ...
             'from the deployment order (%d -> %d available)\n'], ...
        site_diag.n_water_dropped, site_diag.n_spectrum_dropped, site_diag.n_in, site_diag.n_out);

    n_use = min(config.n_max_sweep, numel(order));
    if n_use < config.n_max_sweep
        fprintf('[M3h] WARNING: only %d feasible hex-grid candidates exist inside ANSP territory ', n_use);
        fprintf('(< n_max_sweep=%d) — sweep capped at %d.\n', config.n_max_sweep, n_use);
    end
    selected_order = order(1:n_use);
    fprintf('[M3h] Deployment order: descending local traffic weight (busiest hex cell first), N=1..%d\n', n_use);

    anchors = compute_hotspot_anchors(border_hotspots, ansp_polys);
    hotspot_weight = config.hotspot_weight_alpha * [border_hotspots.count]';

    [R_inner_lo, R_outer_lo] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_lo);

    optimistic   = run_scenario_grid(candidates, selected_order, demand_grid, anchors, hotspot_weight, R_inner_lo, R_outer_lo, n_use);
    conservative = run_scenario_grid(candidates, selected_order, demand_grid, anchors, hotspot_weight, R_inner_hi, R_outer_hi, n_use);

    fprintf('[M3h] At N=%d — coverage: %.1f%%, hotspot coverage: %.1f%% (conservative)\n', ...
        n_use, conservative.coverage_pct(end), conservative.hotspot_coverage_pct(end));

    results.optimistic           = optimistic;
    results.conservative         = conservative;
    results.fade_margin_db_lo    = config.fade_margin_db_lo;
    results.fade_margin_db_hi    = config.fade_margin_db_hi;
    results.n_stations_available = n_use;
    results.selected_order_unconstrained = selected_order_unconstrained;
    results.siting_constraint_diag       = site_diag;
    results.config_snapshot      = config;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'topology_study_weighted_hex.mat'), 'results');
    fprintf('[M3h] Saved: %s\n', fullfile(config.output_data, 'topology_study_weighted_hex.mat'));
    fprintf('[M3h] Traffic-weighted hex-grid baseline complete.\n');

end
