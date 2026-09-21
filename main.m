% MAIN  Full pipeline: data -> border exposure -> siting strategies ->
%   handover cost -> station failure -> physical link -> matched-N sweep.
%
%   Needs data/opensky_data_extended.csv (see data/README.md) and
%   results/m3_optimal_search.mat (from search_optimized_topology, run once).
%   Every module saves its output under results/; figures go to results/figures/.

clear; clc;
init_paths();
fprintf('========================================\n');
fprintf('  ANSP-AWARE AANET GROUND-STATION STUDY\n');
fprintf('========================================\n\n');

config = setup_config();
R = config.output_data;

%% M1 — data pipeline: load, filter to the core box, tag every point with its ANSP
[tagged_data, ansp_names, COL] = m1_data_pipeline(config);

fprintf('[VALIDATION M1] %d rows x %d cols, %d aircraft, %.1f min\n', ...
    size(tagged_data,1), size(tagged_data,2), numel(unique(tagged_data(:,COL.ID))), ...
    (max(tagged_data(:,COL.TIME))-min(tagged_data(:,COL.TIME)))/60);
n_unk = sum(strcmp(ansp_names(tagged_data(:,COL.ANSP)), 'UNKNOWN'));
fprintf('  NaN rows %d | below floor %d | outside box %d | UNKNOWN ANSP %d\n\n', ...
    sum(any(isnan(tagged_data),2)), sum(tagged_data(:,COL.ALT) <= config.alt_min_m), ...
    sum(tagged_data(:,COL.LAT) < config.lat_min | tagged_data(:,COL.LAT) > config.lat_max | ...
        tagged_data(:,COL.LON) < config.lon_min | tagged_data(:,COL.LON) > config.lon_max), n_unk);

%% M2 / M2b / M2c — provider-boundary crossings, MUAC control group, DME reach
border_stats = m2_ansp_border_crossings(tagged_data, ansp_names, COL, config);
[muac_stats, border_hotspots] = m2b_muac_control_analysis(tagged_data, ansp_names, COL, border_stats, config); %#ok<ASGLU>
results_m2c = m2c_dme_hotspot_correlation(border_hotspots, config); %#ok<NASGU>

%% M3 family — nine siting strategies, all under the same water / terrain / spectrum constraints
ansp_polys = load_ansp_polygons(config);

results_m3  = m3_topology_study(tagged_data, COL, ansp_polys, config);                       % traffic-only (baseline)
m3_visualize(results_m3, ansp_polys, config);
results_m3b = m3b_ansp_aware_topology(tagged_data, COL, ansp_polys, border_hotspots, results_m3, config);   % provider-aware
results_m3c = m3c_literature_grid(tagged_data, COL, ansp_polys, border_hotspots, config);    % geometric hex lattice
m3b_visualize(results_m3b, results_m3c, config);
results_m3g = m3g_colocation_topology(tagged_data, COL, ansp_polys, border_hotspots, config); % co-location on DME/VOR sites (caps at N=9)
results_m3h = m3h_weighted_hex_topology(tagged_data, COL, ansp_polys, border_hotspots, config); % traffic-weighted lattice
results_m3d = m3d_pareto_frontier(tagged_data, COL, ansp_polys, border_hotspots, results_m3.conservative, config); % border-weight sweep
m3d_visualize(results_m3d, config);
results_m3e = m3e_minimax_topology(tagged_data, COL, ansp_polys, border_hotspots, results_m3b, config);   % worst-case pinch-point
m3e_visualize(results_m3e, config);
results_m3f = m3f_resilient_topology(tagged_data, COL, ansp_polys, border_hotspots, results_m3b, config); % same-ANSP backup by design

% Optimized: winner of the seeded p-robust GRASP search (search_optimized_topology).
% Loaded, not recomputed: 80 M4+M5 evaluations, run once as its own deliverable.
S_opt = load(fullfile(R, 'm3_optimal_search.mat'), 'pool', 'results_by_p');
results_optimized = struct( ...
    'candidates',     S_opt.pool(S_opt.results_by_p(1).winner_idx).candidates, ...
    'selected_order', S_opt.pool(S_opt.results_by_p(1).winner_idx).selected_order);

%% M7 — physical link: clean / FEC-recovered / relayed / lost, at both fade margins
% Matched set at N=12 plus traffic-only at N=20 for continuity with earlier numbers.
T7 = { 'naive_N20',        results_m3.conservative,  20;
       'naive_N12',        results_m3.conservative,  12;
       'aware_N12',        results_m3b.conservative, 12;
       'minimax_N12',      results_m3e,              12;
       'optimized_N12',    results_optimized,        12;
       'hex_N12',          results_m3c.conservative, 12;
       'weighted_hex_N12', results_m3h.conservative, 12 };
m7_list    = cell(1, size(T7,1));
m7_list_lo = cell(1, size(T7,1));
for i = 1:size(T7,1)
    m7_list{i}    = m7_signal_quality(tagged_data, COL, T7{i,2}, T7{i,3}, config, T7{i,1});                            % F = 5.5 dB
    m7_list_lo{i} = m7_signal_quality(tagged_data, COL, T7{i,2}, T7{i,3}, config, T7{i,1}, config.fade_margin_db_lo);  % F = 2.6 dB
end
m7_visualize_signal_quality(m7_list, config);
m7b_throughput_tradeoff(m7_list, config, m7_list_lo);          % what the split is worth in kbit/s, as a band

% Sensitivity: EIRP, DME rejection and ACM margin have no published value
% for a deployed network. The ranking is the defensible claim, not the levels.
m7c_sensitivity(tagged_data, COL, { ...
    'naive',        results_m3.conservative,  12; ...
    'ANSP-aware',   results_m3b.conservative, 12; ...
    'optimized',    results_optimized,        12; ...
    'hex',          results_m3c.conservative, 12; ...
    'weighted hex', results_m3h.conservative, 12}, config);

% Radio horizon as a separate pass (margin above the line-of-sight cutoff).
for i = [1 3 4 5]
    r7h = m7_radio_horizon_effect(tagged_data, COL, T7{i,2}, T7{i,3}, config, T7{i,1});
    m7_visualize_horizon_effect(m7_list{i}, r7h, config);
end

% Link quality after a single station failure (M5's redirection rule, re-scored with M7's budget).
T7d = { 'naive_N12',        results_m3.conservative;
        'aware_N12',        results_m3b.conservative;
        'hex_N12',          results_m3c.conservative;
        'weighted_hex_N12', results_m3h.conservative;
        'minimax_N12',      results_m3e;
        'resilient_N12',    results_m3f;
        'optimized_N12',    results_optimized };
results_m7d = cell(1, size(T7d,1));
for i = 1:size(T7d,1)
    results_m7d{i} = m7d_failure_link_quality(tagged_data, COL, T7d{i,2}, 12, config, T7d{i,1});
end
save(fullfile(R, 'm7d_failure_link_summary.mat'), 'results_m7d');

%% M4 — handover cost: share of handovers that cross a provider boundary
% Same N=12 for every strategy isolates the siting logic (Comparison B in the thesis).
% Traffic-only and hex are also run at N=20 for the earlier coverage-matched view.
config.m4_save_label = 'naive';
m4_naive_N20 = m4_handover_cost(tagged_data, COL, results_m3.conservative, 20, config); %#ok<NASGU>
m4_naive_N12 = m4_handover_cost(tagged_data, COL, results_m3.conservative, 12, config);
config.m4_save_label = 'aware';
m4_aware_N12 = m4_handover_cost(tagged_data, COL, results_m3b.conservative, 12, config);
config.m4_save_label = 'hex';
m4_hex_N20 = m4_handover_cost(tagged_data, COL, results_m3c.conservative, 20, config); %#ok<NASGU>
m4_hex_N12 = m4_handover_cost(tagged_data, COL, results_m3c.conservative, 12, config);
config.m4_save_label = 'optimized';
m4_optimized_N12 = m4_handover_cost(tagged_data, COL, results_optimized, 12, config);
config.m4_save_label = 'colocation';
m4_colocation_N9 = m4_handover_cost(tagged_data, COL, results_m3g.conservative, results_m3g.n_stations_available, config);
config.m4_save_label = 'weighted_hex';
m4_weighted_hex_N12 = m4_handover_cost(tagged_data, COL, results_m3h.conservative, 12, config);

fprintf('=== M4, matched N=12 ===\n%-22s %6s %12s %14s\n', 'Topology', 'N', 'Margin(dB)', 'pct_inter(%)');
labels_B  = {'Traffic-only', 'Provider-aware', 'Geometric lattice', 'Optimized (p-robust)', 'Weighted lattice'};
results_B = {m4_naive_N12, m4_aware_N12, m4_hex_N12, m4_optimized_N12, m4_weighted_hex_N12};
for i = 1:numel(results_B)
    for m = 1:numel(config.ci_fade_margin_db_list)
        fprintf('%-22s %6d %12.1f %14.1f\n', labels_B{i}, 12, ...
            results_B{i}.by_margin(m).fade_margin_db, results_B{i}.by_margin(m).pct_inter);
    end
end
for m = 1:numel(config.ci_fade_margin_db_list)
    fprintf('%-22s %6d %12.1f %14.1f\n', 'Co-location (cap)', results_m3g.n_stations_available, ...
        m4_colocation_N9.by_margin(m).fade_margin_db, m4_colocation_N9.by_margin(m).pct_inter);
end
fprintf('\n');

%% M5 — station failure: where does a single outage force inter-ANSP handovers?
config.m5_save_label = 'naive';
m5_naive_N20 = m5_station_failure(tagged_data, COL, results_m3.conservative, 20, config);
config.m5_save_label = 'aware';
m5_aware_N12 = m5_station_failure(tagged_data, COL, results_m3b.conservative, 12, config);
config.m5_save_label = 'hex';
m5_hex_N20 = m5_station_failure(tagged_data, COL, results_m3c.conservative, 20, config);
config.m5_save_label = 'resilient';
m5_resilient_N12 = m5_station_failure(tagged_data, COL, results_m3f, 12, config);
config.m5_save_label = 'optimized';
m5_optimized_N12 = m5_station_failure(tagged_data, COL, results_optimized, 12, config);

fprintf('=== M5 concentration (F=5.5dB) ===\n%-22s %6s %10s %14s %14s\n', 'Topology', 'N', 'Total F.I.', 'Top-1 share%', 'Top-1 station');
labels_5  = {'Traffic-only', 'Provider-aware', 'Geometric lattice', 'Resilient', 'Optimized (p-robust)'};
results_5 = {m5_naive_N20, m5_aware_N12, m5_hex_N20, m5_resilient_N12, m5_optimized_N12};
Ns_5      = [20, 12, 20, 12, 12];
for i = 1:numel(results_5)
    be = results_5{i}.by_margin(2);
    [~, top_k] = max([be.per_station.forced_inter_ticks]);
    fprintf('%-22s %6d %10d %13.1f%% %14s\n', labels_5{i}, Ns_5(i), ...
        be.total_forced_inter_ticks, be.top1_forced_inter_share_pct, be.per_station(top_k).ansp_name);
end
fprintf('\n');

%% M6 / M6c / M6b — can the network fix its own worst failure mode?
%   M6  reactive patch: a same-ANSP backup next to the riskiest station
%   M6c minimax search: place the backup to minimise the resulting worst case (two passes)
%   M6b policy: relabel forced-inter events under top-K provider interconnection (RFC 9372)
m6_margin_entry = m5_aware_N12.by_margin(2);
[topo_aware_aug, N_aware_aug, m6_report] = m6_redundancy_placement(results_m3b.conservative, 12, m6_margin_entry, config);
if m6_report.found
    config.m5_save_label = 'aware_redundant';
    m5_aware_aug = m5_station_failure(tagged_data, COL, topo_aware_aug, N_aware_aug, config);
end

[topo_mm1, N_mm1, m6c_report1] = m6c_minimax_redundancy(tagged_data, COL, results_m3b.conservative, 12, config);
config.m5_save_label = 'aware_minimax_redundant';
m5_mm1 = m5_station_failure(tagged_data, COL, topo_mm1, N_mm1, config);
[topo_mm2, N_mm2, m6c_report2] = m6c_minimax_redundancy(tagged_data, COL, topo_mm1, N_mm1, config);
config.m5_save_label = 'aware_minimax_redundant2';
m5_mm2 = m5_station_failure(tagged_data, COL, topo_mm2, N_mm2, config);
save(fullfile(R, 'm6c_chain.mat'), 'm6c_report1', 'm6c_report2', 'N_mm1', 'N_mm2');

fprintf('=== M6 reactive patch vs M6c minimax search (F=5.5dB) ===\n%-34s %5s %12s %11s\n', 'Step', 'N', 'total FI', 'top-1 %');
b0 = m5_aware_N12.by_margin(2);
fprintf('%-34s %5d %12d %10.2f%%\n', 'Baseline, provider-aware', 12, b0.total_forced_inter_ticks, b0.top1_forced_inter_share_pct);
if m6_report.found
    ba = m5_aware_aug.by_margin(2);
    fprintf('%-34s %5d %12d %10.2f%%\n', 'M6 reactive patch', N_aware_aug, ba.total_forced_inter_ticks, ba.top1_forced_inter_share_pct);
end
b1 = m5_mm1.by_margin(2); b2 = m5_mm2.by_margin(2);
fprintf('%-34s %5d %12d %10.2f%%   (backup in %s)\n', 'M6c minimax, 1st pass', N_mm1, b1.total_forced_inter_ticks, b1.top1_forced_inter_share_pct, m6c_report1.winner_ansp);
fprintf('%-34s %5d %12d %10.2f%%   (backup in %s)\n\n', 'M6c minimax, 2nd pass', N_mm2, b2.total_forced_inter_ticks, b2.top1_forced_inter_share_pct, m6c_report2.winner_ansp);

m6b_report = m6b_interconnection_scenario(m6_margin_entry, border_stats, config);
if m6_report.found
    m6_visualize(m5_aware_N12, m5_aware_aug, m6_report, m6b_report, config);
end

%% M8 / M9 — every topology at every N = 4..20, then the single-provider-station mechanism
results_m8 = m8_topology_sweep(tagged_data, COL, config);
m8_visualize(results_m8, config);
results_m9 = m9_singleton_analysis(config);
m9_visualize(results_m9, config);

fprintf('========================================\n  PIPELINE COMPLETE\n========================================\n');
