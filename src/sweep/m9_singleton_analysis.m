% M9_SINGLETON_ANALYSIS  Why adding a station can raise handover cost: the singleton-ANSP mechanism.
%   A station that is the only one of its ANSP has no same-provider
%   neighbour, so every handover into or out of it is forced across an
%   administrative boundary (break-before-make, RFC 9372, the mechanism M4
%   costs). Tested in first differences between consecutive N to remove the
%   shared downward trend of both quantities: does adding a station that
%   creates a new singleton ANSP change pct_inter differently from one that
%   does not? Every topology in M8's registry contributes every
%   consecutive-N step it has, pooled.
%   Input  : config; reads results/m8_topology_sweep.mat (nothing re-run).
%   Output : results struct; saved to results/m9_singleton_analysis.mat.

function results = m9_singleton_analysis(config)

    fprintf('[M9] Singleton-ANSP mechanism analysis starting...\n');

    p = fullfile(config.output_data, 'm8_topology_sweep.mat');
    if ~exist(p, 'file')
        error('m9: %s not found — run m8_topology_sweep.m first.', p);
    end
    S = load(p); sweep = S.results.sweep; N_LIST = S.results.N_LIST;

    % ── Per-topology detail ──
    for i = 1:numel(sweep)
        s = sweep(i);
        fprintf('\n[M9] ---- %s ----\n', s.name);
        fprintf('[M9] %4s %11s %12s %14s %8s\n', 'N', 'pct_inter', 'singletons', 'singleton stn%', 'n_ansp');
        for j = 1:numel(N_LIST)
            if isnan(s.pct_inter_hi(j)), continue; end
            fprintf('[M9] %4d %10.2f%% %12d %13.1f%% %8d\n', N_LIST(j), s.pct_inter_hi(j), ...
                s.n_singleton(j), 100*s.n_singleton(j)/N_LIST(j), s.n_ansp(j));
        end
    end

    % ── Pooled first-difference test ──
    ds = []; dp = []; owner = {};
    for i = 1:numel(sweep)
        s = sweep(i);
        ok = find(~isnan(s.pct_inter_hi));
        for k = 1:numel(ok)-1
            a = ok(k); b = ok(k+1);
            if N_LIST(b) - N_LIST(a) ~= 1, continue; end   % consecutive N only
            ds(end+1) = s.n_singleton(b) - s.n_singleton(a); %#ok<AGROW>
            dp(end+1) = s.pct_inter_hi(b) - s.pct_inter_hi(a); %#ok<AGROW>
            owner{end+1} = s.name; %#ok<AGROW>
        end
    end

    fprintf('\n[M9] ================================================================\n');
    fprintf('[M9]  FIRST-DIFFERENCE TEST — %d single-station additions, %d topologies\n', ...
        numel(ds), numel(sweep));
    fprintf('[M9] ================================================================\n');

    if numel(ds) < 3
        fprintf('[M9] Not enough consecutive-N steps to test. Widen config.m8_N_list to a step of 1.\n');
        results = struct('n_steps', numel(ds));
        return;
    end

    R = corrcoef(ds, dp);
    b = [ones(numel(ds),1) ds(:)] \ dp(:);
    fprintf('[M9] Pearson r (d singletons vs d pct_inter) = %+.3f\n', R(1,2));
    fprintf('[M9] Linear fit: d pct_inter = %+.2f %+.2f x (d singletons)\n\n', b(1), b(2));

    grp_lbl = {'created a new singleton ANSP', 'left singleton count unchanged', 'removed a singleton'};
    grp_sel = {ds > 0, ds == 0, ds < 0};
    fprintf('[M9] %-34s %5s %12s %10s %12s\n', 'Adding one station that...', 'n', 'mean d_pct', 'median', '%% that rose');
    groups = struct('label', {}, 'n', {}, 'mean_delta', {}, 'median_delta', {}, 'pct_worse', {});
    for g = 1:3
        v = dp(grp_sel{g});
        groups(g).label        = grp_lbl{g};
        groups(g).n            = numel(v);
        groups(g).mean_delta   = mean(v);
        groups(g).median_delta = median(v);
        groups(g).pct_worse    = 100 * mean(v > 0);
        fprintf('[M9] %-34s %5d %+11.2f %+10.2f %11.0f%%\n', grp_lbl{g}, numel(v), ...
            mean(v), median(v), 100*mean(v > 0));
    end

    fprintf('\n[M9] ---- every step that CREATED a singleton ----\n');
    for k = find(ds > 0)
        fprintf('[M9]   %-26s singletons %+d   pct_inter %+6.2f pp\n', owner{k}, ds(k), dp(k));
    end

    % ── Terminal state: does the topology end with singletons? ──
    fprintf('\n[M9] ---- terminal singleton count vs terminal pct_inter ----\n');
    fprintf('[M9] %-26s %5s %12s %12s\n', 'Topology', 'N', 'singletons', 'pct_inter');
    terminal = struct('name', {}, 'N', {}, 'n_singleton', {}, 'pct_inter', {});
    for i = 1:numel(sweep)
        s = sweep(i);
        ok = find(~isnan(s.pct_inter_hi), 1, 'last');
        if isempty(ok), continue; end
        terminal(end+1) = struct('name', s.name, 'N', N_LIST(ok), ...
            'n_singleton', s.n_singleton(ok), 'pct_inter', s.pct_inter_hi(ok)); %#ok<AGROW>
        fprintf('[M9] %-26s %5d %12d %11.2f%%\n', s.name, N_LIST(ok), s.n_singleton(ok), s.pct_inter_hi(ok));
    end

    results.delta_singleton   = ds;
    results.delta_pct_inter   = dp;
    results.step_topology     = owner;
    results.pearson_r         = R(1,2);
    results.linear_fit        = b;
    results.groups            = groups;
    results.terminal          = terminal;
    results.config_snapshot   = config;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'm9_singleton_analysis.mat'), 'results');
    fprintf('\n[M9] Saved: %s\n', fullfile(config.output_data, 'm9_singleton_analysis.mat'));
    fprintf('[M9] Singleton-ANSP mechanism analysis complete.\n');

end
