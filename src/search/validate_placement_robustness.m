% VALIDATE_PLACEMENT_ROBUSTNESS  GRASP restart ensemble for naive vs ANSP-aware placement.
%
% Tests whether "naive beats ANSP-aware on inter-ANSP handover share" is a
% structural effect or an artefact of one deterministic greedy path. Each
% greedy step samples uniformly from a Restricted Candidate List of sites
% within RCL_ALPHA of the best marginal gain (GRASP, Feo & Resende 1995);
% RCL_ALPHA=0 recovers the deterministic greedy, which is checked against
% results/topology_study.mat. Restarts are seeded and evaluated with M4 at
% every N in N_LIST (one prefix-valid greedy path to N_MAX per restart).
% RCL_ALPHA=0.15 is a disclosed modelling choice, not a literature value.
% Hex is a fixed tessellation with nothing to randomize, so it is excluded.
% Output: results/m3_placement_robustness.mat (pct_inter per restart and N,
% naive win rate per N). Run standalone after main.m.

clear; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), '..', '..')); init_paths();
N_RESTARTS = 30;
RCL_ALPHA = 0.15;
N_MAX = 20;
N_LIST = [5 8 10 12 15 18 20];

config = setup_config();
S = load(fullfile(config.output_data, 'tagged_data.mat'), 'tagged_data', 'COL');
tagged_data = S.tagged_data; COL = S.COL;
ansp_polys = load_ansp_polygons(config);
S2 = load(fullfile(config.output_data, 'border_hotspots.mat'), 'border_hotspots');
border_hotspots = S2.border_hotspots;

grid_points = build_adaptive_grid(tagged_data, COL, config);
naive_candidates = filter_valid_candidates(grid_points, ansp_polys);
naive_candidates = exclude_water_sites(naive_candidates, config.terrain_data_path);
difficulty_naive = load_difficulty(naive_candidates, config.terrain_data_path, config.dme_beacons, config.dme_cost_weight);

n_hotspots = numel(border_hotspots);
aware_pool = grid_points;
for h = 1:n_hotspots
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

% RCL_ALPHA=0 must reproduce the deterministic greedy before restarts are trusted.
fprintf('[SANITY] Checking RCL_ALPHA=0 reproduces the deterministic greedy...\n');
sel0 = greedy_mclp_soft_grasp(naive_candidates, grid_points, difficulty_naive, ...
    config.terrain_cost_weight, R_inner_km, R_outer_km, N_MAX, 0, 1, D_min_km_hi, n_channels_avail);
S3 = load(fullfile(config.output_data, 'topology_study.mat'), 'results');
real_sel = S3.results.conservative.selected_order(1:N_MAX);
if isequal(sort(sel0), sort(real_sel))
    fprintf('[SANITY] PASSED — RCL_ALPHA=0 selects the identical station SET as the real deterministic run.\n');
else
    fprintf('[SANITY] WARNING — RCL_ALPHA=0 selection differs from results/topology_study.mat. Investigate before trusting restarts.\n');
end

% One greedy path to N_MAX per restart; its first N picks are the N-station solution.
n_N = numel(N_LIST);
pct_inter_naive = zeros(N_RESTARTS, n_N);
pct_inter_aware = zeros(N_RESTARTS, n_N);

fprintf('[GRASP] Running %d restarts each for naive and ANSP-aware (RCL_alpha=%.2f), evaluated at N = %s...\n', ...
    N_RESTARTS, RCL_ALPHA, mat2str(N_LIST));

for r = 1:N_RESTARTS
    sel_naive = greedy_mclp_soft_grasp(naive_candidates, grid_points, difficulty_naive, ...
        config.terrain_cost_weight, R_inner_km, R_outer_km, N_MAX, RCL_ALPHA, r, D_min_km_hi, n_channels_avail);
    sel_aware = greedy_mclp_dual_grasp(aware_candidates, grid_points, border_hotspots, anchors, ...
        hotspot_weight, difficulty_aware, config.terrain_cost_weight, R_inner_km, R_outer_km, N_MAX, RCL_ALPHA, 1000+r, D_min_km_hi, n_channels_avail);

    for ni = 1:n_N
        N = N_LIST(ni);
        topo_naive.candidates = naive_candidates;
        topo_naive.selected_order = sel_naive(1:N);
        res_naive = m4_handover_cost(tagged_data, COL, topo_naive, N, config);
        pct_inter_naive(r,ni) = res_naive.by_margin(2).pct_inter;   % F=5.5dB conservative

        topo_aware.candidates = aware_candidates;
        topo_aware.selected_order = sel_aware(1:N);
        res_aware = m4_handover_cost(tagged_data, COL, topo_aware, N, config);
        pct_inter_aware(r,ni) = res_aware.by_margin(2).pct_inter;
    end

    fprintf('  restart %2d/%d done: naive %s | aware %s\n', r, N_RESTARTS, ...
        mat2str(round(pct_inter_naive(r,:),1)), mat2str(round(pct_inter_aware(r,:),1)));
end

fprintf('\n=== GRASP ROBUSTNESS SUMMARY BY N (F=5.5dB, %d restarts) ===\n', N_RESTARTS);
fprintf('%4s %10s %10s %10s %10s %12s\n', 'N', 'NaiveMean', 'NaiveStd', 'AwareMean', 'AwareStd', 'NaiveWin%%');
win_rate_by_N = zeros(n_N,1);
for ni = 1:n_N
    win_rate_by_N(ni) = 100 * mean(pct_inter_naive(:,ni) < pct_inter_aware(:,ni));
    fprintf('%4d %9.1f%% %9.1f%% %9.1f%% %9.1f%% %11.0f%%\n', N_LIST(ni), ...
        mean(pct_inter_naive(:,ni)), std(pct_inter_naive(:,ni)), ...
        mean(pct_inter_aware(:,ni)), std(pct_inter_aware(:,ni)), win_rate_by_N(ni));
end

fprintf('\nDeterministic (RCL_alpha=0) reference, per N:\n');
fprintf('%4s %10s %10s %10s\n', 'N', 'Naive%', 'Aware%', 'NaiveBetter');
det_naive_by_N = zeros(n_N,1); det_aware_by_N = zeros(n_N,1);
for ni = 1:n_N
    N = N_LIST(ni);
    topo_naive.candidates = naive_candidates; topo_naive.selected_order = sel0(1:N);
    res = m4_handover_cost(tagged_data, COL, topo_naive, N, config);
    det_naive_by_N(ni) = res.by_margin(2).pct_inter;

    sel0_aware = greedy_mclp_dual_grasp(aware_candidates, grid_points, border_hotspots, anchors, ...
        hotspot_weight, difficulty_aware, config.terrain_cost_weight, R_inner_km, R_outer_km, N_MAX, 0, 1, D_min_km_hi, n_channels_avail);
    topo_aware.candidates = aware_candidates; topo_aware.selected_order = sel0_aware(1:N);
    res = m4_handover_cost(tagged_data, COL, topo_aware, N, config);
    det_aware_by_N(ni) = res.by_margin(2).pct_inter;

    fprintf('%4d %9.1f%% %9.1f%% %11d\n', N, det_naive_by_N(ni), det_aware_by_N(ni), det_naive_by_N(ni) < det_aware_by_N(ni));
end

results.pct_inter_naive = pct_inter_naive;
results.pct_inter_aware = pct_inter_aware;
results.win_rate_by_N = win_rate_by_N;
results.det_naive_by_N = det_naive_by_N;
results.det_aware_by_N = det_aware_by_N;
results.N_LIST = N_LIST;
results.rcl_alpha = RCL_ALPHA;
results.n_restarts = N_RESTARTS;
save(fullfile(config.output_data, 'm3_placement_robustness.mat'), 'results');
fprintf('[SAVE] results/m3_placement_robustness.mat\n');
