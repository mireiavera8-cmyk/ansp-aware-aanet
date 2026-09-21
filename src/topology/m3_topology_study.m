% M3_TOPOLOGY_STUDY  Coverage-only greedy MCLP ground-station sweep (naive baseline).
%
% Places N = 1..n_max_sweep stations by greedy maximal covering location
% (Church & ReVelle, 1974) on an adaptive demand grid. Coverage is soft-edged:
% connection probability falls linearly from 1 at R_inner to 0 at R_outer,
% with R_inner = R/10^(F/20) and R_outer = R*10^(F/20) for fade margin F (free-
% space 20 dB/decade slope). Two full scenarios are run, F = fade_margin_db_lo
% (optimistic) and fade_margin_db_hi (conservative), since the radius changes
% which sites are picked. Candidates must lie inside an ANSP polygon and off
% open water; terrain/DME siting difficulty discounts the greedy gain; the
% co-channel spectrum budget (free-space C/I D_min, greedy graph colouring) is
% enforced at every step. Elbow N: max distance to chord (Satopaa et al. 2011).
% coverage_pct is expected aircraft-cell presence weight covered (MCLP demand
% mass), not a share of distinct aircraft.
%
% INPUT  : tagged_data, COL (M1), ansp_polys, config
% OUTPUT : results.optimistic / .conservative scenario structs, saved to
%          results/topology_study.mat

function results = m3_topology_study(tagged_data, COL, ansp_polys, config)

    fprintf('[M3] Topology study starting...\n');

    % -- STEP 1: adaptive demand/candidate grid (shared across scenarios) --
    grid_points = build_adaptive_grid(tagged_data, COL, config);
    fprintf('[M3] Adaptive grid: %d points (base %.1fdeg, fine %.1fdeg, threshold %d aircraft)\n', ...
        numel(grid_points), config.grid_base_deg, config.grid_fine_deg, config.grid_subdiv_threshold);

    % -- STEP 2: candidate sites restricted to ANSP territory; demand is not --
    candidates = filter_valid_candidates(grid_points, ansp_polys);
    fprintf('[M3] Valid candidate sites (inside ANSP territory): %d / %d grid points\n', ...
        numel(candidates), numel(grid_points));

    % -- STEP 2a: hard exclusion of open-water sites (FIRs extend over sea) --
    n_before_water = numel(candidates);
    candidates = exclude_water_sites(candidates, config.terrain_data_path);
    fprintf('[M3] Water-site exclusion (hard feasibility): %d -> %d candidates (%d removed)\n', ...
        n_before_water, numel(candidates), n_before_water - numel(candidates));

    % -- STEP 2b: siting difficulty (terrain + DME proximity), soft discount --
    difficulty_norm = load_difficulty(candidates, config.terrain_data_path, config.dme_beacons, config.dme_cost_weight);
    fprintf('[M3] Siting difficulty (0-1, terrain+DME): median=%.2f, %d/%d sites >0.5\n', ...
        median(difficulty_norm), sum(difficulty_norm>0.5), numel(difficulty_norm));

    % -- STEP 2c: spectrum budget, enforced live using the conservative C/I bound --
    n_channels_avail = floor(config.spectrum_mhz / config.channel_bw_mhz);
    D_min_km_hi = free_space_D_min(config.gs_radius_km, config.ci_required_db_max);
    fprintf('[M3] Spectrum budget enforced live: D_min=%.0fkm, %d channels available\n', ...
        D_min_km_hi, n_channels_avail);

    % -- STEP 3: run both soft-edge scenarios --
    [R_inner_lo, R_outer_lo] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_lo);
    [R_inner_hi, R_outer_hi] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);

    fprintf('[M3] Soft-edge band, optimistic (F=%.1fdB): R_inner=%.0fkm, R_outer=%.0fkm\n', ...
        config.fade_margin_db_lo, R_inner_lo, R_outer_lo);
    fprintf('[M3] Soft-edge band, conservative (F=%.1fdB): R_inner=%.0fkm, R_outer=%.0fkm\n', ...
        config.fade_margin_db_hi, R_inner_hi, R_outer_hi);

    fprintf('[M3] ---- SCENARIO: OPTIMISTIC (F=%.1fdB) ----\n', config.fade_margin_db_lo);
    optimistic = run_scenario(candidates, grid_points, difficulty_norm, R_inner_lo, R_outer_lo, ...
        D_min_km_hi, n_channels_avail, config);

    fprintf('[M3] ---- SCENARIO: CONSERVATIVE (F=%.1fdB) ----\n', config.fade_margin_db_hi);
    conservative = run_scenario(candidates, grid_points, difficulty_norm, R_inner_hi, R_outer_hi, ...
        D_min_km_hi, n_channels_avail, config);

    % -- PACKAGE RESULTS --
    results.optimistic        = optimistic;
    results.conservative      = conservative;
    results.fade_margin_db_lo = config.fade_margin_db_lo;
    results.fade_margin_db_hi = config.fade_margin_db_hi;
    results.config_snapshot   = config;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'topology_study.mat'), 'results');
    fprintf('[M3] Saved: %s\n', fullfile(config.output_data, 'topology_study.mat'));
    fprintf('[M3] Topology study complete.\n');

end


% RUN_SCENARIO  Greedy MCLP + interference band + elbow for one (R_inner, R_outer) pair.
function scen = run_scenario(candidates, grid_points, difficulty_norm, R_inner_km, R_outer_km, ...
    D_min_km_hi, n_channels_avail, config)

    [selected_order, coverage_pct] = greedy_mclp_soft(candidates, grid_points, ...
        difficulty_norm, config.terrain_cost_weight, R_inner_km, R_outer_km, config.n_max_sweep, ...
        D_min_km_hi, n_channels_avail);
    fprintf('[M3] Greedy MCLP (soft-edge, terrain-cost-weighted, spectrum-budget-enforced): swept N=1..%d in one pass\n', config.n_max_sweep);
    fprintf('[M3] Avg terrain difficulty of selected sites: %.3f (pool median %.3f)\n', ...
        mean(difficulty_norm(selected_order)), median(difficulty_norm));

    % Interference curve as a lo/hi C/I band scored on the fixed placement;
    % only the hi bound was enforced during selection, so this confirms it.
    D_min_km_lo = free_space_D_min(config.gs_radius_km, config.ci_required_db_min);
    fprintf('[M3] Co-channel D_min band: %.0f-%.0f km (free-space C/I %.1f-%.1fdB required, R=%dkm)\n', ...
        D_min_km_lo, D_min_km_hi, config.ci_required_db_min, config.ci_required_db_max, config.gs_radius_km);
    fprintf('[M3] Channels available in band: %d\n', n_channels_avail);

    channels_required_lo = compute_interference_curve(candidates, selected_order, D_min_km_lo);
    channels_required_hi = compute_interference_curve(candidates, selected_order, D_min_km_hi);
    meets_spectrum_budget_lo = channels_required_lo <= n_channels_avail;
    meets_spectrum_budget_hi = channels_required_hi <= n_channels_avail;

    % Cost is linear in N (documented simplification).
    cost_units = (1:config.n_max_sweep)';

    elbow_N = find_elbow(coverage_pct);
    fprintf('[M3] Automatic elbow (max-distance-to-chord): N = %d (coverage %.1f%%)\n', ...
        elbow_N, coverage_pct(elbow_N));

    % Channel map at the elbow uses the conservative D_min so it matches the
    % single channel count quoted elsewhere.
    channel_assignment_elbow = channel_assignment_at_N(candidates, selected_order, D_min_km_hi, elbow_N);

    marginal = [coverage_pct(1); diff(coverage_pct)];
    fprintf('[M3] ---- SWEEP SUMMARY ----\n');
    fprintf('[M3] %3s %10s %10s %16s %12s %8s\n', 'N', 'Cov%', 'MargGain', 'Channels(lo-hi)', 'Budget', 'Cost');
    for n = 1:config.n_max_sweep
        marker = '';
        if n == elbow_N, marker = '  <-- elbow'; end
        if meets_spectrum_budget_hi(n)
            budget_str = 'true';
        elseif ~meets_spectrum_budget_lo(n)
            budget_str = 'false';
        else
            budget_str = 'borderline';
        end
        fprintf('[M3] %3d %9.2f%% %9.2f%% %7d-%-8d %12s %8d%s\n', ...
            n, coverage_pct(n), marginal(n), channels_required_lo(n), channels_required_hi(n), ...
            budget_str, cost_units(n), marker);
    end

    scen.candidates               = candidates;
    scen.selected_order           = selected_order;   % indices into candidates, in greedy pick order
    scen.coverage_pct             = coverage_pct;      % 1 x n_max_sweep
    scen.marginal_gain            = marginal;
    scen.channels_required_lo     = channels_required_lo;
    scen.channels_required_hi     = channels_required_hi;
    scen.n_channels_available     = n_channels_avail;
    scen.meets_spectrum_budget_lo = meets_spectrum_budget_lo;
    scen.meets_spectrum_budget_hi = meets_spectrum_budget_hi;
    scen.cost_units               = cost_units;
    scen.elbow_N                  = elbow_N;
    scen.channel_assignment_elbow = channel_assignment_elbow;  % aligned to selected_order(1:elbow_N)
    scen.D_min_km_lo              = D_min_km_lo;
    scen.D_min_km_hi              = D_min_km_hi;
    scen.R_inner_km                = R_inner_km;
    scen.R_outer_km                = R_outer_km;

end


% GREEDY_MCLP_SOFT  One greedy pass to n_max; every smaller N is a prefix.
function [selected_order, coverage_pct] = greedy_mclp_soft(candidates, demand_points, ...
    difficulty_norm, terrain_cost_weight, R_inner_km, R_outer_km, n_max, D_min_km, n_channels_avail)

    n_cand = numel(candidates);
    n_dem  = numel(demand_points);

    cand_lat = [candidates.lat]';
    cand_lon = [candidates.lon]';
    dem_lat  = [demand_points.lat]';
    dem_lon  = [demand_points.lon]';
    dem_weight = [demand_points.weight]';
    total_weight = sum(dem_weight);

    % Connection-probability matrix: candidate x demand, in [0,1]
    conn_prob = zeros(n_cand, n_dem);
    for i = 1:n_cand
        d = haversine_km(cand_lat(i), cand_lon(i), dem_lat, dem_lon);
        conn_prob(i,:) = connection_probability(d, R_inner_km, R_outer_km);
    end

    cost_divisor = 1 + terrain_cost_weight * difficulty_norm;   % see setup_config.m

    best_prob = zeros(n_dem, 1);   % best connection probability so far, per demand point
    selected_order = zeros(n_max, 1);
    coverage_pct = zeros(n_max, 1);
    picked = false(n_cand, 1);

    for step = 1:n_max
        picked_lat = cand_lat(picked); picked_lon = cand_lon(picked);
        gains = zeros(n_cand,1);
        colors_needed = zeros(n_cand,1);
        for i = 1:n_cand
            if picked(i), continue; end
            colors_needed(i) = spectrum_colors_if_added(picked_lat, picked_lon, cand_lat(i), cand_lon(i), D_min_km);
            if colors_needed(i) > n_channels_avail
                gains(i) = -Inf;
                continue;
            end
            improvement = max(conn_prob(i,:)' - best_prob, 0);
            gains(i) = sum(dem_weight .* improvement) / cost_divisor(i);   % difficulty discounts SELECTION only
        end
        if all(gains(~picked) == -Inf)
            colors_needed(picked) = Inf;
            [~, best] = min(colors_needed);   % all break the budget: take the least-bad site
        else
            [~, best] = max(gains);
        end
        picked(best) = true;
        best_prob = max(best_prob, conn_prob(best,:)');   % raw (unpenalised) achieved coverage
        selected_order(step) = best;
        coverage_pct(step) = 100 * sum(dem_weight .* best_prob) / total_weight;
    end

end


% COMPUTE_INTERFERENCE_CURVE  Channels needed for each prefix N (greedy colouring
% of the conflict graph, edge if distance < D_min).
function channels_required = compute_interference_curve(candidates, selected_order, D_min_km)

    n_max = numel(selected_order);
    channels_required = zeros(n_max, 1);

    lat = [candidates.lat]';
    lon = [candidates.lon]';

    for n = 1:n_max
        idx = selected_order(1:n);
        if n == 1
            channels_required(n) = 1;
            continue;
        end
        sub_lat = lat(idx);
        sub_lon = lon(idx);
        adj = false(n,n);
        for i = 1:n
            d = haversine_km(sub_lat(i), sub_lon(i), sub_lat, sub_lon);
            adj(i,:) = d < D_min_km;
        end
        adj(1:n+1:end) = false; % no self-conflict
        channels_required(n) = greedy_graph_color(adj);
    end

end


function color = channel_assignment_at_N(candidates, selected_order, D_min_km, n)
    idx = selected_order(1:n);
    lat = [candidates.lat]';
    lon = [candidates.lon]';
    sub_lat = lat(idx);
    sub_lon = lon(idx);
    adj = false(n,n);
    for i = 1:n
        d = haversine_km(sub_lat(i), sub_lon(i), sub_lat, sub_lon);
        adj(i,:) = d < D_min_km;
    end
    adj(1:n+1:end) = false;
    [~, color] = greedy_graph_color(adj);
end


% FIND_ELBOW  Max perpendicular distance to the first-to-last chord of the
% curve, both axes normalised to [0,1] (simplified Kneedle, Satopaa et al. 2011).
function elbow_idx = find_elbow(y)
    n = numel(y);
    x = (1:n)';
    xn = (x - x(1)) / (x(end) - x(1));
    yn = (y - min(y)) / (max(y) - min(y) + eps);

    p1 = [xn(1), yn(1)];
    p2 = [xn(end), yn(end)];
    line_vec = p2 - p1;
    line_vec = line_vec / norm(line_vec);

    dists = zeros(n,1);
    for i = 1:n
        pt = [xn(i), yn(i)] - p1;
        proj = dot(pt, line_vec) * line_vec;
        perp = pt - proj;
        dists(i) = norm(perp);
    end
    [~, elbow_idx] = max(dists);
end
