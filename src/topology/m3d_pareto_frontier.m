% M3D_PARETO_FRONTIER  Alpha sweep tracing the traffic-vs-border-coverage trade-off.
%
% Re-runs the M3b objective (grid_gain + alpha * hotspot_gain, greedy_mclp_dual,
% same pool and siting constraints) for every alpha in config.pareto_alpha_values,
% conservative scenario only. Each alpha gives one (traffic coverage, dual-anchor
% hotspot coverage) point at N = pareto_eval_N; together they approximate a
% Pareto frontier (greedy weighted-sum scalarisation only reaches points that
% are optima of some linear weighting). Each topology is also scored through
% m4_handover_cost so the frontier can be drawn in outcome space.
%
% INPUT  : tagged_data, COL, ansp_polys (M1); border_hotspots (M2b);
%          naive_conservative (M3 results.conservative, reference only); config
% OUTPUT : results.alpha_sweep(k) (.alpha .coverage_pct .hotspot_coverage_pct
%          .selected_order .candidates .pct_inter_at_eval_N .served_at_eval_N),
%          results.naive_reference; results/topology_study_pareto.mat

function results = m3d_pareto_frontier(tagged_data, COL, ansp_polys, ...
    border_hotspots, naive_conservative, config)

    fprintf('[M3d] Pareto frontier alpha sweep starting...\n');

    grid_points = build_adaptive_grid(tagged_data, COL, config);
    anchors     = compute_hotspot_anchors(border_hotspots, ansp_polys);
    [R_inner_hi, R_outer_hi] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);

    % Live spectrum budget, identical to M3b, so every alpha is on the same footing.
    n_channels_avail = floor(config.spectrum_mhz / config.channel_bw_mhz);
    D_min_km_hi = free_space_D_min(config.gs_radius_km, config.ci_required_db_max);

    alphas  = config.pareto_alpha_values(:);
    n_alpha = numel(alphas);
    fprintf('[M3d] Sweeping %d alpha values: %s\n', n_alpha, mat2str(alphas', 3));

    sweep = repmat(struct('alpha', [], 'coverage_pct', [], ...
        'hotspot_coverage_pct', [], 'selected_order', [], 'candidates', [], ...
        'pct_inter_at_eval_N', [], 'served_at_eval_N', [], ...
        'n_inter_at_eval_N', []), n_alpha, 1);

    cfg_eval = config;
    if isfield(cfg_eval, 'm4_save_label'), cfg_eval = rmfield(cfg_eval, 'm4_save_label'); end
    N_eval = config.pareto_eval_N;

    for k = 1:n_alpha
        fprintf('[M3d] ---- alpha = %.3g (%d/%d) ----\n', alphas(k), k, n_alpha);
        scen = run_scenario_pareto(grid_points, ansp_polys, border_hotspots, anchors, ...
            R_inner_hi, R_outer_hi, alphas(k), D_min_km_hi, n_channels_avail, config);
        sweep(k).alpha                = alphas(k);
        sweep(k).coverage_pct         = scen.coverage_pct;
        sweep(k).hotspot_coverage_pct = scen.hotspot_coverage_pct;
        sweep(k).selected_order       = scen.selected_order;
        sweep(k).candidates           = scen.candidates;   % selected_order indexes into this pool

        % Outcome-space score: one M4 handover evaluation per alpha.
        topo_k = struct('candidates', scen.candidates, 'selected_order', scen.selected_order);
        evalc('r4k = m4_handover_cost(tagged_data, COL, topo_k, N_eval, cfg_eval);');
        b = r4k.by_margin(2);
        sweep(k).pct_inter_at_eval_N = b.pct_inter;
        sweep(k).served_at_eval_N    = 100 - b.coverage_gap_pct;
        sweep(k).n_inter_at_eval_N   = b.n_inter;
        fprintf('[M3d]   alpha=%.3g at N=%d: coverage %.2f%%, hotspot %.2f%%, inter-ANSP %.2f%%, served %.2f%%\n', ...
            alphas(k), N_eval, scen.coverage_pct(min(N_eval,end)), ...
            scen.hotspot_coverage_pct(min(N_eval,end)), b.pct_inter, 100 - b.coverage_gap_pct);
    end

    fprintf('\n[M3d] ---- FRONTIER IN OUTCOME SPACE (N=%d, F=%.1fdB) ----\n', ...
        N_eval, config.fade_margin_db_hi);
    fprintf('[M3d] %8s %12s %12s %14s %10s\n', 'alpha', 'coverage%', 'hotspot%', 'inter-ANSP%', 'served%');
    for k = 1:n_alpha
        fprintf('[M3d] %8.2f %11.2f%% %11.2f%% %13.2f%% %9.2f%%\n', sweep(k).alpha, ...
            sweep(k).coverage_pct(min(N_eval,end)), sweep(k).hotspot_coverage_pct(min(N_eval,end)), ...
            sweep(k).pct_inter_at_eval_N, sweep(k).served_at_eval_N);
    end

    % Naive reference on the same metric; the percentage is alpha-invariant for a fixed order.
    naive_hotspot_cov = hotspot_coverage_curve_dual(naive_conservative.candidates, ...
        naive_conservative.selected_order, anchors, [border_hotspots.count]', ...
        R_inner_hi, R_outer_hi, config.n_max_sweep);

    results.alpha_sweep        = sweep;
    results.fade_margin_db_hi  = config.fade_margin_db_hi;
    results.pareto_eval_N      = config.pareto_eval_N;
    results.naive_reference.coverage_pct         = naive_conservative.coverage_pct;
    results.naive_reference.hotspot_coverage_pct = naive_hotspot_cov;
    results.border_hotspots    = border_hotspots;
    results.anchors            = anchors;
    results.config_snapshot    = config;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'topology_study_pareto.mat'), 'results');
    fprintf('[M3d] Saved: %s\n', fullfile(config.output_data, 'topology_study_pareto.mat'));
    fprintf('[M3d] Pareto frontier sweep complete.\n');

end


% RUN_SCENARIO_PARETO  Single-alpha run of the M3b grid+hotspot greedy. The pool
% includes hotspot centroids, so alpha=0 is close to, not identical to, M3's naive run.
function scen = run_scenario_pareto(grid_points, ansp_polys, border_hotspots, anchors, ...
    R_inner_km, R_outer_km, alpha, D_min_km, n_channels_avail, config)

    n_hotspots = numel(border_hotspots);
    candidate_pool = grid_points;
    for h = 1:n_hotspots
        entry.lat = border_hotspots(h).centroid_lat;
        entry.lon = border_hotspots(h).centroid_lon;
        entry.weight = 0;
        candidate_pool(end+1) = entry; %#ok<AGROW>
    end
    candidates = filter_valid_candidates(candidate_pool, ansp_polys);

    candidates = exclude_water_sites(candidates, config.terrain_data_path);
    difficulty_norm = load_difficulty(candidates, config.terrain_data_path, ...
        config.dme_beacons, config.dme_cost_weight);

    hotspot_weight = alpha * [border_hotspots.count]';

    [selected_order, ~] = greedy_mclp_dual(candidates, grid_points, ...
        border_hotspots, anchors, hotspot_weight, difficulty_norm, ...
        config.terrain_cost_weight, R_inner_km, R_outer_km, config.n_max_sweep, ...
        D_min_km, n_channels_avail);

    % x-axis: grid-only coverage; y-axis: dual-anchor hotspot coverage (alpha-independent).
    coverage_pct = grid_coverage_curve(candidates, selected_order, grid_points, ...
        R_inner_km, R_outer_km, config.n_max_sweep);

    hotspot_coverage_pct = hotspot_coverage_curve_dual(candidates, selected_order, ...
        anchors, [border_hotspots.count]', R_inner_km, R_outer_km, config.n_max_sweep);

    scen.selected_order        = selected_order;
    scen.coverage_pct          = coverage_pct;
    scen.hotspot_coverage_pct  = hotspot_coverage_pct;
    scen.candidates            = candidates;

end
