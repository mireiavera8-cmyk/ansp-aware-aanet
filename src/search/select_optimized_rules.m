% SELECT_OPTIMIZED_RULES  Sensitivity of the Optimized topology to the winner-selection rule.
%
% search_optimized_topology.m picks its winner with a p-robust rule (Snyder &
% Daskin 2005): meet the coverage floor, keep constructions whose failure
% concentration is within (1+p) of the best found, then minimise pct_inter.
% This script re-selects from the saved pools with a lexicographic rule
% (coverage floor, then min pct_inter; concentration only reported). No new
% search is run, so no topology can change; only the named winner can.
% Input : results/m3_optimal_search.mat, results/m3_optimal_search_Nsweep.mat
% Output: results/m3_optimal_selection_rules.mat and a printed table.

clear; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), '..', '..')); init_paths();
config = setup_config();
out = struct('N', {}, 'rule', {}, 'pct_inter', {}, 'top1_share', {}, ...
    'coverage_pct', {}, 'served', {}, 'n_admissible', {});

% N=12 pool: served traffic was not recorded, hence NaN.
A = load(fullfile(config.output_data, 'm3_optimal_search.mat'), 'pool', 'coverage_floor');
cov = [A.pool.coverage_pct]; pct = [A.pool.pct_inter]; t1 = [A.pool.top1_share];
out = add_rows(out, 12, cov, pct, t1, nan(size(pct)), A.coverage_floor, config);

if exist(fullfile(config.output_data, 'm3_optimal_search_Nsweep.mat'), 'file')
    B = load(fullfile(config.output_data, 'm3_optimal_search_Nsweep.mat'), 'sweep');
    for si = 1:numel(B.sweep)
        s = B.sweep(si);
        out = add_rows(out, s.N, s.pool_coverage, s.pool_pct_inter, ...
            s.pool_top1, s.pool_served, s.coverage_floor, config);
    end
end

fprintf('\n=== SELECTION RULE COMPARISON (F=5.5 dB) ===\n');
fprintf('%-5s %-22s %11s %11s %11s %9s\n', 'N', 'rule', 'pct_inter', 'top1', 'served', 'admiss.');
for i = 1:numel(out)
    fprintf('%-5d %-22s %10.2f%% %10.2f%% %10.2f%% %9d\n', out(i).N, out(i).rule, ...
        out(i).pct_inter, out(i).top1_share, out(i).served, out(i).n_admissible);
end

selection_rules = out; %#ok<NASGU>
save(fullfile(config.output_data, 'm3_optimal_selection_rules.mat'), 'selection_rules');
fprintf('\n[SAVE] results/m3_optimal_selection_rules.mat\n');


function out = add_rows(out, N, cov, pct, t1, served, floor_pct, config)
    feasible = cov >= floor_pct;
    if ~any(feasible)
        fprintf('N=%d: no construction meets the coverage floor %.2f%%\n', N, floor_pct);
        return
    end
    best_t1 = min(t1(feasible));

    for pi = 1:numel(config.p_robust_tolerances)
        p = config.p_robust_tolerances(pi);
        admissible = feasible & (t1 <= (1+p) * best_t1);
        c = pct; c(~admissible) = Inf;
        [~, w] = min(c);
        out(end+1) = pack(N, sprintf('p-robust p=%.2f', p), pct(w), t1(w), cov(w), served(w), sum(admissible)); %#ok<AGROW>
    end

    c = pct; c(~feasible) = Inf;
    [~, w] = min(c);
    out(end+1) = pack(N, 'lexicographic', pct(w), t1(w), cov(w), served(w), sum(feasible)); %#ok<AGROW>
end

function r = pack(N, rule, pct_inter, top1, cov, served, n)
    r.N = N; r.rule = rule; r.pct_inter = pct_inter; r.top1_share = top1;
    r.coverage_pct = cov; r.served = served; r.n_admissible = n;
end
