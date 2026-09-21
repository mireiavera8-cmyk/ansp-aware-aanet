function sweep = search_optimized_topology(N_list, n_restarts)
% SEARCH_OPTIMIZED_TOPOLOGY  p-robust GRASP search for the "Optimized" topology.
%
%   Runs n_restarts randomised constructions from each of the two greedy
%   logics (traffic-only and provider-aware), under the same water, terrain,
%   DME and spectrum constraints as M3/M3b, and selects per station count N:
%       minimise  pct_inter (M4)
%       s.t.      coverage  >= max(traffic-only, provider-aware) at N
%                 top1_share <= (1+p) * best top1_share found      (Snyder & Daskin 2005)
%   for each p in config.p_robust_tolerances.
%
%   search_optimized_topology()                  N = 12, 40 + 40 restarts
%   search_optimized_topology([12 14 16 18 20])  full station-count sweep
%
%   Outputs (results/):
%     m3_optimal_search.mat        pool, results_by_p, coverage_floor   (when 12 is in N_list)
%     m3_optimal_search_Nsweep.mat sweep, N_SWEEP, N_RESTARTS, RCL_ALPHA (when N_list has >1 entry)
%
%   Stochastic but seeded (restart r uses rng(r) / rng(1000+r)), so every
%   construction can be regenerated exactly. Not called from main.m: run
%   once, main.m loads the winner.

    if nargin < 1 || isempty(N_list),     N_list = 12;    end
    if nargin < 2 || isempty(n_restarts), n_restarts = 40; end
    RCL_ALPHA = 0.15;

    config = setup_config();
    R = config.output_data;
    S  = load(fullfile(R, 'tagged_data.mat'), 'tagged_data', 'COL');
    tagged_data = S.tagged_data; COL = S.COL;
    ansp_polys = load_ansp_polygons(config);
    S2 = load(fullfile(R, 'border_hotspots.mat'), 'border_hotspots');
    border_hotspots = S2.border_hotspots;

    % candidate pools, with every feasibility constraint applied
    grid_points = build_adaptive_grid(tagged_data, COL, config);

    naive_candidates = filter_valid_candidates(grid_points, ansp_polys);
    naive_candidates = exclude_water_sites(naive_candidates, config.terrain_data_path);
    difficulty_naive = load_difficulty(naive_candidates, config.terrain_data_path, config.dme_beacons, config.dme_cost_weight);

    aware_pool = grid_points;
    for h = 1:numel(border_hotspots)
        entry.lat = border_hotspots(h).centroid_lat;
        entry.lon = border_hotspots(h).centroid_lon;
        entry.weight = 0;
        aware_pool(end+1) = entry; %#ok<AGROW>
    end
    aware_candidates = filter_valid_candidates(aware_pool, ansp_polys);
    aware_candidates = exclude_water_sites(aware_candidates, config.terrain_data_path);
    difficulty_aware = load_difficulty(aware_candidates, config.terrain_data_path, config.dme_beacons, config.dme_cost_weight);

    anchors = compute_hotspot_anchors(border_hotspots, ansp_polys);
    hotspot_weight = config.hotspot_weight_alpha * [border_hotspots.count]';

    [R_inner_km, R_outer_km] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);
    n_channels_avail = floor(config.spectrum_mhz / config.channel_bw_mhz);
    D_min_km_hi = free_space_D_min(config.gs_radius_km, config.ci_required_db_max);

    fprintf('[SEARCH] Traffic-only pool: %d candidates. Provider-aware pool: %d candidates.\n', ...
        numel(naive_candidates), numel(aware_candidates));

    S3 = load(fullfile(R, 'topology_study.mat'), 'results');            naive_det = S3.results.conservative;
    S4 = load(fullfile(R, 'topology_study_ansp_aware.mat'), 'results'); aware_det = S4.results.conservative;

    sweep = struct('N', {}, 'coverage_floor', {}, 'n_feasible', {}, ...
        'pool_pct_inter', {}, 'pool_served', {}, 'pool_coverage', {}, 'pool_top1', {}, 'by_p', {});
    t_all = tic;

    for si = 1:numel(N_list)
        N_EVAL = N_list(si);
        coverage_floor = max(naive_det.coverage_pct(N_EVAL), aware_det.coverage_pct(N_EVAL));
        fprintf('\n===== N = %d  (coverage floor %.2f%%, %d + %d restarts) =====\n', ...
            N_EVAL, coverage_floor, n_restarts, n_restarts);

        n_total = 2 * n_restarts;
        pool = struct('label', cell(1,n_total), 'candidates', cell(1,n_total), ...
            'selected_order', cell(1,n_total), 'coverage_pct', cell(1,n_total), ...
            'pct_inter', cell(1,n_total), 'top1_share', cell(1,n_total), ...
            'served', cell(1,n_total), 'n_inter', cell(1,n_total), 'ho_total', cell(1,n_total));

        idx = 0; t0 = tic;
        for r = 1:n_restarts
            idx = idx + 1;
            sel = greedy_mclp_soft_grasp(naive_candidates, grid_points, difficulty_naive, ...
                config.terrain_cost_weight, R_inner_km, R_outer_km, N_EVAL, RCL_ALPHA, r, D_min_km_hi, n_channels_avail);
            pool(idx) = evaluate_candidate_topology('naive', naive_candidates, sel, tagged_data, COL, config, N_EVAL, grid_points, R_inner_km, R_outer_km);
        end
        for r = 1:n_restarts
            idx = idx + 1;
            sel = greedy_mclp_dual_grasp(aware_candidates, grid_points, border_hotspots, anchors, hotspot_weight, ...
                difficulty_aware, config.terrain_cost_weight, R_inner_km, R_outer_km, N_EVAL, RCL_ALPHA, 1000+r, D_min_km_hi, n_channels_avail);
            pool(idx) = evaluate_candidate_topology('aware', aware_candidates, sel, tagged_data, COL, config, N_EVAL, grid_points, R_inner_km, R_outer_km);
        end
        fprintf('  %d constructions evaluated in %.1f s\n', n_total, toc(t0));

        all_coverage = [pool.coverage_pct];
        all_pct      = [pool.pct_inter];
        all_top1     = [pool.top1_share];
        all_served   = [pool.served];

        feasible = all_coverage >= coverage_floor;
        fprintf('  %d / %d meet the coverage floor\n', sum(feasible), n_total);
        fprintf('  pool: pct_inter %.2f-%.2f%%, served %.2f-%.2f%%, top1 %.2f-%.2f%%\n', ...
            min(all_pct), max(all_pct), min(all_served), max(all_served), min(all_top1), max(all_top1));

        by_p = struct('p', {}, 'winner_idx', {}, 'label', {}, 'pct_inter', {}, 'served', {}, ...
            'coverage_pct', {}, 'top1_share', {}, 'n_inter', {}, 'ho_total', {}, 'selected_order', {});
        if any(feasible)
            best_top1 = min(all_top1(feasible));
            for pi = 1:numel(config.p_robust_tolerances)
                p = config.p_robust_tolerances(pi);
                robust = feasible & (all_top1 <= (1+p) * best_top1);
                cand = all_pct; cand(~robust) = Inf;
                [~, w] = min(cand);
                by_p(pi).p              = p;
                by_p(pi).winner_idx     = w;
                by_p(pi).label          = pool(w).label;
                by_p(pi).pct_inter      = pool(w).pct_inter;
                by_p(pi).served         = pool(w).served;
                by_p(pi).coverage_pct   = pool(w).coverage_pct;
                by_p(pi).top1_share     = pool(w).top1_share;
                by_p(pi).n_inter        = pool(w).n_inter;
                by_p(pi).ho_total       = pool(w).ho_total;
                by_p(pi).selected_order = pool(w).selected_order;
                fprintf('  p=%.2f winner (%s-derived, %d admissible): pct_inter %.2f%%, served %.2f%%, top1 %.2f%%, inter %d of %d\n', ...
                    p, pool(w).label, sum(robust), pool(w).pct_inter, pool(w).served, pool(w).top1_share, ...
                    pool(w).n_inter, pool(w).ho_total);
            end
        else
            fprintf('  NO restart meets the coverage floor at N=%d\n', N_EVAL);
        end

        sweep(si).N              = N_EVAL;
        sweep(si).coverage_floor = coverage_floor;
        sweep(si).n_feasible     = sum(feasible);
        sweep(si).pool_pct_inter = all_pct;
        sweep(si).pool_served    = all_served;
        sweep(si).pool_coverage  = all_coverage;
        sweep(si).pool_top1      = all_top1;
        sweep(si).by_p           = by_p;

        if N_EVAL == 12 && ~isempty(by_p)
            results_by_p = rmfield(by_p, {'served', 'n_inter', 'ho_total', 'selected_order'});
            save(fullfile(R, 'm3_optimal_search.mat'), 'pool', 'results_by_p', 'coverage_floor');
            fprintf('  [SAVE] m3_optimal_search.mat (thesis N=12 deliverable)\n');
            print_reference_comparison(R, results_by_p);
        end
    end

    if numel(N_list) > 1
        N_SWEEP = N_list; N_RESTARTS = n_restarts; %#ok<NASGU>
        save(fullfile(R, 'm3_optimal_search_Nsweep.mat'), 'sweep', 'N_SWEEP', 'N_RESTARTS', 'RCL_ALPHA');
        fprintf('\n[SAVE] m3_optimal_search_Nsweep.mat\n');
    end
    fprintf('\n[SEARCH] total %.1f min\n', toc(t_all)/60);
end


function print_reference_comparison(R, results_by_p)
    refs = {'Traffic-only', 'm4_naive_N12.mat'; 'Provider-aware', 'm4_aware_N12.mat'; 'Geometric lattice', 'm4_hex_N12.mat'};
    fprintf('\n=== N=12, F=5.5 dB: searched vs deterministic ===\n');
    fprintf('%-28s %12s %12s\n', 'Topology', 'pct_inter', 'top1_share');
    for i = 1:size(refs,1)
        p = fullfile(R, refs{i,2});
        if ~exist(p, 'file'), continue; end
        r = getfield(load(p, 'results'), 'results');
        fprintf('%-28s %11.2f%%\n', refs{i,1}, r.by_margin(2).pct_inter);
    end
    for pi = 1:numel(results_by_p)
        fprintf('%-28s %11.2f%% %11.2f%%   (p=%.2f, %s-derived)\n', 'Optimized', ...
            results_by_p(pi).pct_inter, results_by_p(pi).top1_share, results_by_p(pi).p, results_by_p(pi).label);
    end
end
