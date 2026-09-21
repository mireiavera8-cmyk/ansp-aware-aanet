% M3C_LITERATURE_GRID  Uniform hexagonal lattice baseline (classical cellular planning).
%
% Sites are fixed by geometry, not traffic: a regular hex tessellation of
% circumradius R = gs_radius_km (Rappaport, Wireless Communications) inside
% ANSP territory, deployed outward from the corridor centroid with a terrain
% penalty on the distance key, then water exclusion and the live spectrum
% budget (apply_siting_constraints). Stands in for the textbook demand-blind
% default, since no public operational European LDACS siting plan exists.
% Coverage and dual-anchor hotspot coverage use the same grid/metric as M3/M3b.
%
% INPUT  : tagged_data, COL (M1), ansp_polys, border_hotspots (M2b), config
% OUTPUT : results.optimistic / .conservative (+ pre-constraint order);
%          results/topology_study_literature_grid.mat
function results = m3c_literature_grid(tagged_data, COL, ansp_polys, border_hotspots, config)

    fprintf('[M3c] Literature hex-grid baseline starting...\n');

    grid_points = build_hex_grid(config);
    fprintf('[M3c] Hex-grid points (R=%dkm circumradius): %d, before ANSP filtering\n', ...
        config.gs_radius_km, numel(grid_points));

    candidates = filter_valid_candidates(grid_points, ansp_polys);
    fprintf('[M3c] Valid hex-grid candidates (inside ANSP territory): %d\n', numel(candidates));

    center_lat = (config.lat_min + config.lat_max) / 2;
    center_lon = (config.lon_min + config.lon_max) / 2;
    cand_lat = [candidates.lat]';
    cand_lon = [candidates.lon]';
    d_center = haversine_km(center_lat, center_lon, cand_lat, cand_lon);

    % Distance key (lower is better): difficulty pushes a site outward by (1 + w*difficulty).
    [difficulty_norm, dparts] = load_difficulty_hex(candidates, ...
        config.terrain_data_hex_path, config.dme_beacons, config.dme_cost_weight, true);
    fprintf('[M3c] Siting difficulty (0-1, terrain+DME): median=%.2f, %d/%d sites >0.5\n', ...
        median(difficulty_norm), sum(difficulty_norm>0.5), numel(difficulty_norm));

    score = d_center(:) .* (1 + config.terrain_cost_weight * difficulty_norm(:));
    [~, order] = sort(score, 'ascend');

    % Pre-constraint order kept so the cost of the feasibility filter is reportable.
    n_unc = min(config.n_max_sweep, numel(order));
    selected_order_unconstrained = order(1:n_unc);

    [order, site_diag] = apply_siting_constraints(candidates, order, config);
    fprintf(['[M3c] Feasibility: %d water sites and %d spectrum-budget sites dropped ' ...
             'from the deployment order (%d -> %d available)\n'], ...
        site_diag.n_water_dropped, site_diag.n_spectrum_dropped, site_diag.n_in, site_diag.n_out);

    n_use = min(config.n_max_sweep, numel(order));
    if n_use < config.n_max_sweep
        fprintf('[M3c] WARNING: only %d feasible hex-grid candidates exist inside ANSP territory ', n_use);
        fprintf('(< n_max_sweep=%d) — sweep capped at %d.\n', config.n_max_sweep, n_use);
    end
    selected_order = order(1:n_use);
    fprintf('[M3c] Deployment order: outward from corridor centroid (%.2f, %.2f), N=1..%d\n', ...
        center_lat, center_lon, n_use);

    anchors = compute_hotspot_anchors(border_hotspots, ansp_polys);
    hotspot_weight = config.hotspot_weight_alpha * [border_hotspots.count]';

    [R_inner_lo, R_outer_lo] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_lo);
    [R_inner_hi, R_outer_hi] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);

    % Same adaptive demand grid as M3/M3h, so coverage curves are comparable.
    demand_grid = build_adaptive_grid(tagged_data, COL, config);

    optimistic   = run_scenario_grid(candidates, selected_order, demand_grid, anchors, hotspot_weight, R_inner_lo, R_outer_lo, n_use);
    conservative = run_scenario_grid(candidates, selected_order, demand_grid, anchors, hotspot_weight, R_inner_hi, R_outer_hi, n_use);

    fprintf('[M3c] At N=%d — coverage: %.1f%%, hotspot coverage: %.1f%% (conservative)\n', ...
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
    save(fullfile(config.output_data, 'topology_study_literature_grid.mat'), 'results');
    fprintf('[M3c] Saved: %s\n', fullfile(config.output_data, 'topology_study_literature_grid.mat'));
    fprintf('[M3c] Literature hex-grid baseline complete.\n');

end
