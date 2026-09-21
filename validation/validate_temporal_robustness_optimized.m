% VALIDATE_TEMPORAL_ROBUSTNESS_OPTIMIZED  Out-of-sample check of the Optimized topology.
%
% The Optimized topology (search_optimized_topology.m) was selected by a
% p-robust search evaluated only on the design hour, so it is the topology
% most at risk of being fitted to one hour's traffic. This script evaluates
% it with M4/M5 on the independent validation hour and tabulates it next to
% naive/ANSP-aware/hex on both hours. Reuses the validation-hour checkpoints
% written by validate_temporal_robustness.m (results/validation/) instead of
% reprocessing the CSV. Run standalone after validate_temporal_robustness.m.

clear; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), '..')); init_paths();
config = setup_config();
config.output_data = fullfile(config.root, 'results', 'validation');

S = load(fullfile(config.output_data, 'tagged_data.mat'), 'tagged_data', 'COL');
tagged_data_val = S.tagged_data; COL_val = S.COL;

S_opt = load(fullfile(config.root, 'results', 'm3_optimal_search.mat'), 'pool', 'results_by_p');
results_optimized = struct( ...
    'candidates', S_opt.pool(S_opt.results_by_p(1).winner_idx).candidates, ...
    'selected_order', S_opt.pool(S_opt.results_by_p(1).winner_idx).selected_order);

fprintf('----------------------------------------\n');
config.m4_save_label = 'optimized_val';
m4_optimized_val = m4_handover_cost(tagged_data_val, COL_val, results_optimized, 12, config);

config.m5_save_label = 'optimized_val';
m5_optimized_val = m5_station_failure(tagged_data_val, COL_val, results_optimized, 12, config);
fprintf('----------------------------------------\n\n');

% Original-hour reference (computed by main.m).
Sd_naive  = load(fullfile(config.root, 'results', 'm4_naive_N12.mat'), 'results');     naive_orig  = Sd_naive.results;
Sd_aware  = load(fullfile(config.root, 'results', 'm4_aware_N12.mat'), 'results');     aware_orig  = Sd_aware.results;
Sd_hex    = load(fullfile(config.root, 'results', 'm4_hex_N12.mat'), 'results');       hex_orig    = Sd_hex.results;
Sd_opt    = load(fullfile(config.root, 'results', 'm4_optimized_N12.mat'), 'results'); opt_orig    = Sd_opt.results;

% Validation-hour reference from validate_temporal_robustness.m; Optimized computed above.
Sv_naive = load(fullfile(config.output_data, 'm4_naive_val_refresh_N12.mat'), 'results'); naive_val = Sv_naive.results;
Sv_aware = load(fullfile(config.output_data, 'm4_aware_val_refresh_N12.mat'), 'results'); aware_val = Sv_aware.results;
Sv_hex   = load(fullfile(config.output_data, 'm4_hex_val_refresh_N12.mat'), 'results');   hex_val   = Sv_hex.results;

fprintf('=== TEMPORAL ROBUSTNESS: does Optimized still win on the validation hour? ===\n');
fprintf('%-14s %10s %10s %10s\n', 'Topology', 'N', 'orig%', 'val%');
rows = {
    'Naive',      naive_orig, naive_val;
    'ANSP-aware', aware_orig, aware_val;
    'Hex',        hex_orig,   hex_val;
    'Optimized',  opt_orig,   m4_optimized_val;
};
for r = 1:size(rows,1)
    o = rows{r,2}.by_margin(2); v = rows{r,3}.by_margin(2);
    fprintf('%-14s %10d %9.1f%% %9.1f%%   delta=%+.1fpp\n', rows{r,1}, 12, o.pct_inter, v.pct_inter, v.pct_inter - o.pct_inter);
end

fprintf('\n=== M5 top1_share, original vs validation hour ===\n');
Se_naive = load(fullfile(config.root, 'results', 'm5_naive_N20.mat'), 'results'); m5_naive_orig = Se_naive.results;
Se_aware = load(fullfile(config.root, 'results', 'm5_aware_N12.mat'), 'results'); m5_aware_orig = Se_aware.results;
Se_hex   = load(fullfile(config.root, 'results', 'm5_hex_N20.mat'), 'results');   m5_hex_orig   = Se_hex.results;
Se_opt   = load(fullfile(config.root, 'results', 'm5_optimized_N12.mat'), 'results'); m5_opt_orig = Se_opt.results;
Sf_naive = load(fullfile(config.output_data, 'm5_naive_val_refresh_N20.mat'), 'results'); m5_naive_val = Sf_naive.results;
Sf_aware = load(fullfile(config.output_data, 'm5_aware_val_refresh_N12.mat'), 'results'); m5_aware_val = Sf_aware.results;
Sf_hex   = load(fullfile(config.output_data, 'm5_hex_val_refresh_N20.mat'), 'results');   m5_hex_val   = Sf_hex.results;

rows5 = {
    'Naive',      m5_naive_orig, m5_naive_val;
    'ANSP-aware', m5_aware_orig, m5_aware_val;
    'Hex',        m5_hex_orig,   m5_hex_val;
    'Optimized',  m5_opt_orig,   m5_optimized_val;
};
fprintf('%-14s %10s %10s\n', 'Topology', 'orig top1%', 'val top1%');
for r = 1:size(rows5,1)
    o = rows5{r,2}.by_margin(2); v = rows5{r,3}.by_margin(2);
    fprintf('%-14s %9.1f%% %9.1f%%   delta=%+.1fpp\n', rows5{r,1}, o.top1_forced_inter_share_pct, v.top1_forced_inter_share_pct, ...
        v.top1_forced_inter_share_pct - o.top1_forced_inter_share_pct);
end

fprintf('\n[DONE] Optimized validation-hour results saved to results/validation/m4_optimized_val_N12.mat, m5_optimized_val_N12.mat\n');
