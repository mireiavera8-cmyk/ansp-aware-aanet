% VALIDATE_TEMPORAL_ROBUSTNESS  Out-of-sample check of the topology comparison on a second traffic hour.
%
% The topologies were designed on one hour (2023-05-15 08:00-09:00 UTC). A
% deployment is fixed, so the robustness question is whether the SAME
% topologies still rank the same way on an independent hour
% (2023-05-18 17:00-18:00 UTC). M1/M2/M2b are re-run on the validation set
% (descriptive, no topology involved); M4/M5 re-evaluate the ORIGINAL
% naive/ANSP-aware/hex topologies against the validation traffic, mirroring
% main.m's Comparison A/B and headline trio. The optimizer is deliberately
% NOT re-fitted to the new hour: that would answer a different question.
% Self-contained: loads original results from results/, writes only to
% results/validation/. Run standalone after main.m.

clear; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), '..')); init_paths();
fprintf('=========================================================\n');
fprintf('  TEMPORAL ROBUSTNESS CHECK — original vs validation hour\n');
fprintf('=========================================================\n\n');

%% Validation dataset config
config2 = setup_config();
config2.csv_path       = fullfile(config2.root, 'data', 'opensky_data_validation.csv');
config2.t_start        = 1684429200;                  % 2023-05-18 17:00 UTC
config2.t_end          = config2.t_start + 3600;       % same 1h duration as original
config2.output_data    = fullfile(config2.root, 'results', 'validation');   % never touches results/
config2.output_figures = fullfile(config2.root, 'results', 'validation', 'figures');

fprintf('[INFO] Original window : 2023-05-15 08:00-09:00 UTC (data/opensky_data_extended.csv)\n');
fprintf('[INFO] Validation window: 2023-05-18 17:00-18:00 UTC (data/opensky_data_validation.csv)\n\n');

%% Original-hour baseline (from main.m)
fprintf('[LOAD] Reading original results from results/ ...\n');
S = load(fullfile(config2.root, 'results', 'border_crossings.mat'), 'border_stats');       border_stats_1 = S.border_stats;
S = load(fullfile(config2.root, 'results', 'muac_control_analysis.mat'), 'muac_stats');    muac_stats_1   = S.muac_stats;
S = load(fullfile(config2.root, 'results', 'topology_study.mat'), 'results');               results_m3     = S.results;
S = load(fullfile(config2.root, 'results', 'topology_study_ansp_aware.mat'), 'results');    results_m3b    = S.results;
S = load(fullfile(config2.root, 'results', 'topology_study_literature_grid.mat'), 'results'); results_m3c  = S.results;
S = load(fullfile(config2.root, 'results', 'tagged_data.mat'), 'tagged_data'); tagged_data_1 = S.tagged_data;

m4_naive_N20_1 = getfield(load(fullfile(config2.root, 'results', 'm4_naive_N20.mat'), 'results'), 'results');
m4_naive_N12_1 = getfield(load(fullfile(config2.root, 'results', 'm4_naive_N12.mat'), 'results'), 'results');
m4_aware_N12_1 = getfield(load(fullfile(config2.root, 'results', 'm4_aware_N12.mat'), 'results'), 'results');
m4_hex_N20_1   = getfield(load(fullfile(config2.root, 'results', 'm4_hex_N20.mat'), 'results'), 'results');
m4_hex_N12_1   = getfield(load(fullfile(config2.root, 'results', 'm4_hex_N12.mat'), 'results'), 'results');

m5_naive_N20_1 = getfield(load(fullfile(config2.root, 'results', 'm5_naive_N20.mat'), 'results'), 'results');
m5_aware_N12_1 = getfield(load(fullfile(config2.root, 'results', 'm5_aware_N12.mat'), 'results'), 'results');
m5_hex_N20_1   = getfield(load(fullfile(config2.root, 'results', 'm5_hex_N20.mat'), 'results'), 'results');
fprintf('[LOAD] Done.\n\n');

%% M1 on validation hour
fprintf('----------------------------------------\n');
[tagged_data_2, ansp_names_2, COL_2] = m1_data_pipeline(config2);
fprintf('----------------------------------------\n\n');

%% M2 / M2b on validation hour
fprintf('----------------------------------------\n');
border_stats_2 = m2_ansp_border_crossings(tagged_data_2, ansp_names_2, COL_2, config2);
fprintf('----------------------------------------\n\n');

fprintf('----------------------------------------\n');
[muac_stats_2, border_hotspots_2] = m2b_muac_control_analysis(tagged_data_2, ansp_names_2, COL_2, border_stats_2, config2); %#ok<ASGLU>
fprintf('----------------------------------------\n\n');

%% M4: original topologies, validation traffic
fprintf('----------------------------------------\n');
config2.m4_save_label = 'naive_val';
m4_naive_N20_2 = m4_handover_cost(tagged_data_2, COL_2, results_m3.conservative, 20, config2);
m4_naive_N12_2 = m4_handover_cost(tagged_data_2, COL_2, results_m3.conservative, 12, config2);

config2.m4_save_label = 'aware_val';
m4_aware_N12_2 = m4_handover_cost(tagged_data_2, COL_2, results_m3b.conservative, 12, config2);

config2.m4_save_label = 'hex_val';
m4_hex_N20_2 = m4_handover_cost(tagged_data_2, COL_2, results_m3c.conservative, 20, config2);
m4_hex_N12_2 = m4_handover_cost(tagged_data_2, COL_2, results_m3c.conservative, 12, config2);
fprintf('----------------------------------------\n\n');

%% M5: original topologies, validation traffic
fprintf('----------------------------------------\n');
config2.m5_save_label = 'naive_val';
m5_naive_N20_2 = m5_station_failure(tagged_data_2, COL_2, results_m3.conservative, 20, config2);

config2.m5_save_label = 'aware_val';
m5_aware_N12_2 = m5_station_failure(tagged_data_2, COL_2, results_m3b.conservative, 12, config2);

config2.m5_save_label = 'hex_val';
m5_hex_N20_2 = m5_station_failure(tagged_data_2, COL_2, results_m3c.conservative, 20, config2);
fprintf('----------------------------------------\n\n');

%% Consistency report
fprintf('\n=========================================================\n');
fprintf('  CONSISTENCY REPORT — original vs validation hour\n');
fprintf('=========================================================\n\n');

n_ac_2  = length(unique(tagged_data_2(:,COL_2.ID)));
fprintf('--- M1: pipeline yield ---\n');
fprintf('%-28s %14s %14s\n', '', 'original', 'validation');
fprintf('%-28s %14d %14d\n', 'state vectors', size(tagged_data_1,1), size(tagged_data_2,1));
fprintf('%-28s %14d %14d\n', 'aircraft', border_stats_1.n_aircraft, n_ac_2);
fprintf('\n');

fprintf('--- M2: border-crossing exposure ---\n');
fprintf('%-28s %14s %14s\n', '', 'original', 'validation');
fprintf('%-28s %14d %14d\n', 'aircraft analyzed', border_stats_1.n_aircraft, border_stats_2.n_aircraft);
fprintf('%-28s %13.1f%% %13.1f%%\n', 'pct crossing >=1 border', border_stats_1.pct_aircraft_crossing, border_stats_2.pct_aircraft_crossing);
fprintf('%-28s %14d %14d\n', 'total confirmed crossings', border_stats_1.total_crossings, border_stats_2.total_crossings);
fprintf('\n');

fprintf('--- M2b: MUAC vs non-MUAC bounded exposure ---\n');
fprintf('%-28s %14s %14s\n', '', 'original', 'validation');
fprintf('%-28s %13.1f%% %13.1f%%\n', 'MUAC pct_high (>=3 cross.)', muac_stats_1.exposure_muac.pct_high, muac_stats_2.exposure_muac.pct_high);
fprintf('%-28s %13.1f%% %13.1f%%\n', 'non-MUAC pct_high', muac_stats_1.exposure_non_muac.pct_high, muac_stats_2.exposure_non_muac.pct_high);
fprintf('%-28s %14.2f %14.2f\n', 'median rate/1000km ratio (non/MUAC)', muac_stats_1.rate_ratio_median_non_over_muac, muac_stats_2.rate_ratio_median_non_over_muac);
fprintf('  (ratio > 1 in both columns = non-MUAC crosses more per km than MUAC-touching, in BOTH samples)\n\n');

fprintf('--- M4 Comparison A: same coverage level (naive N=20, aware N=12, hex N=20) ---\n');
fprintf('%-14s %4s %8s %12s %12s %10s\n', 'topology', 'N', 'margin', 'orig pct_inter', 'val pct_inter', 'delta');
rows_A = {
    'Naive',       20, m4_naive_N20_1, m4_naive_N20_2;
    'ANSP-aware',  12, m4_aware_N12_1, m4_aware_N12_2;
    'Hex',         20, m4_hex_N20_1,   m4_hex_N20_2;
};
for r = 1:size(rows_A,1)
    for m = 1:numel(config2.ci_fade_margin_db_list)
        o = rows_A{r,3}.by_margin(m); v = rows_A{r,4}.by_margin(m);
        fprintf('%-14s %4d %8.1f %12.1f %12.1f %10.1f\n', rows_A{r,1}, rows_A{r,2}, ...
            o.fade_margin_db, o.pct_inter, v.pct_inter, v.pct_inter - o.pct_inter);
    end
end
fprintf('\n');

fprintf('--- M4 Comparison B: same N=12 (isolates topology effect) ---\n');
fprintf('%-14s %4s %8s %12s %12s %10s\n', 'topology', 'N', 'margin', 'orig pct_inter', 'val pct_inter', 'delta');
rows_B = {
    'Naive',      12, m4_naive_N12_1, m4_naive_N12_2;
    'ANSP-aware', 12, m4_aware_N12_1, m4_aware_N12_2;
    'Hex',        12, m4_hex_N12_1,   m4_hex_N12_2;
};
for r = 1:size(rows_B,1)
    for m = 1:numel(config2.ci_fade_margin_db_list)
        o = rows_B{r,3}.by_margin(m); v = rows_B{r,4}.by_margin(m);
        fprintf('%-14s %4d %8.1f %12.1f %12.1f %10.1f\n', rows_B{r,1}, rows_B{r,2}, ...
            o.fade_margin_db, o.pct_inter, v.pct_inter, v.pct_inter - o.pct_inter);
    end
end
fprintf('\n');

fprintf('--- M5: station-failure concentration (F=5.5dB) ---\n');
fprintf('%-14s %4s %14s %14s %14s %14s\n', 'topology', 'N', 'orig top1 %', 'val top1 %', 'orig total FI', 'val total FI');
rows_5 = {
    'Naive',      20, m5_naive_N20_1, m5_naive_N20_2;
    'ANSP-aware', 12, m5_aware_N12_1, m5_aware_N12_2;
    'Hex',        20, m5_hex_N20_1,   m5_hex_N20_2;
};
for r = 1:size(rows_5,1)
    o = rows_5{r,3}.by_margin(2); v = rows_5{r,4}.by_margin(2);   % margin(2) = F=5.5dB, matches main.m
    fprintf('%-14s %4d %13.1f%% %13.1f%% %14d %14d\n', rows_5{r,1}, rows_5{r,2}, ...
        o.top1_forced_inter_share_pct, v.top1_forced_inter_share_pct, ...
        o.total_forced_inter_ticks, v.total_forced_inter_ticks);
end
fprintf('\n');

fprintf('=========================================================\n');
fprintf('  END OF REPORT — validation outputs saved under results/validation/\n');
fprintf('=========================================================\n');

%% Save summary for validate_temporal_robustness_visualize.m (redraw without reprocessing the CSV)
consistency = struct();

consistency.m2.pct_crossing_orig = border_stats_1.pct_aircraft_crossing;
consistency.m2.pct_crossing_val  = border_stats_2.pct_aircraft_crossing;

consistency.m2b.muac_pct_high_orig     = muac_stats_1.exposure_muac.pct_high;
consistency.m2b.muac_pct_high_val      = muac_stats_2.exposure_muac.pct_high;
consistency.m2b.non_muac_pct_high_orig = muac_stats_1.exposure_non_muac.pct_high;
consistency.m2b.non_muac_pct_high_val  = muac_stats_2.exposure_non_muac.pct_high;

% Comparison B (same N=12) at the F=5.5dB headline margin.
consistency.m4.topology       = {'Naive', 'ANSP-aware', 'Hex'};
consistency.m4.N              = [12, 12, 12];
consistency.m4.pct_inter_orig = [m4_naive_N12_1.by_margin(2).pct_inter, ...
                                  m4_aware_N12_1.by_margin(2).pct_inter, ...
                                  m4_hex_N12_1.by_margin(2).pct_inter];
consistency.m4.pct_inter_val  = [m4_naive_N12_2.by_margin(2).pct_inter, ...
                                  m4_aware_N12_2.by_margin(2).pct_inter, ...
                                  m4_hex_N12_2.by_margin(2).pct_inter];

% Headline trio (naive N=20, aware N=12, hex N=20) at F=5.5dB.
consistency.m5.topology        = {'Naive', 'ANSP-aware', 'Hex'};
consistency.m5.N               = [20, 12, 20];
consistency.m5.top1_pct_orig   = [m5_naive_N20_1.by_margin(2).top1_forced_inter_share_pct, ...
                                   m5_aware_N12_1.by_margin(2).top1_forced_inter_share_pct, ...
                                   m5_hex_N20_1.by_margin(2).top1_forced_inter_share_pct];
consistency.m5.top1_pct_val    = [m5_naive_N20_2.by_margin(2).top1_forced_inter_share_pct, ...
                                   m5_aware_N12_2.by_margin(2).top1_forced_inter_share_pct, ...
                                   m5_hex_N20_2.by_margin(2).top1_forced_inter_share_pct];

consistency.meta.orig_window = '2023-05-15 08:00-09:00 UTC';
consistency.meta.val_window  = '2023-05-18 17:00-18:00 UTC';

if ~exist(config2.output_data, 'dir'), mkdir(config2.output_data); end
save(fullfile(config2.output_data, 'temporal_robustness_comparison.mat'), 'consistency');
fprintf('[SAVE] Comparison summary saved to %s\n', fullfile(config2.output_data, 'temporal_robustness_comparison.mat'));
