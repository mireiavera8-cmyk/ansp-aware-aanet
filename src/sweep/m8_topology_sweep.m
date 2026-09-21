% M8_TOPOLOGY_SWEEP  Matched-N head-to-head across every topology and station count.
%   Evaluates every saved topology at the same N across config.m8_N_list:
%   inter-ANSP handover share and served traffic (m4_handover_cost) per
%   (topology, N, fade margin); failure concentration at one matched N
%   (m5_station_failure), raw and normalised against the even-spread floor
%   100/N; the same matched-N comparison on the validation hour; a
%   feasibility-parity disclosure for M3c/M3g/M3h (constrained vs the
%   pre-constraint order those modules also save); a candidate-pool parity
%   audit; and the per-N ANSP composition consumed by m9_singleton_analysis.
%   Served traffic is 100 - coverage_gap_pct from M4, measured identically
%   for every topology (M3c stores no demand-weighted coverage_pct).
%   m4_save_label/m5_save_label are stripped from a local config copy so
%   M4/M5 write no per-run .mat here.
%   Inputs : tagged_data, COL (design hour, M1), config.
%   Output : results struct; saved to results/m8_topology_sweep.mat.

% tagged_data and COL are used inside the evalc() strings below (which
% silence M4/M5 console output); the Code Analyzer cannot see that.
function results = m8_topology_sweep(tagged_data, COL, config)

    fprintf('[M8] Matched-N topology sweep starting...\n');

    cfg = config;
    if isfield(cfg, 'm4_save_label'), cfg = rmfield(cfg, 'm4_save_label'); end
    if isfield(cfg, 'm5_save_label'), cfg = rmfield(cfg, 'm5_save_label'); end

    reg = build_topology_registry(cfg);
    N_LIST = cfg.m8_N_list;
    nT = numel(reg);
    nN = numel(N_LIST);

    fprintf('[M8] %d topology variants x %d station counts x 2 fade margins\n', nT, nN);

    % ── SWEEP 1: pct_inter and served traffic across N ──
    sweep_c = cell(1, nT);

    for i = 1:nT
        t   = reg(i).topo;
        cap = min(reg(i).cap, numel(t.selected_order));

        e = struct();
        e.name = reg(i).name;
        e.cap  = cap;
        e.N    = N_LIST;
        e.pct_inter_hi = nan(1, nN);  e.pct_inter_lo = nan(1, nN);
        e.served_hi    = nan(1, nN);  e.served_lo    = nan(1, nN);
        e.n_singleton  = nan(1, nN);  e.n_ansp       = nan(1, nN);
        % Absolute and distance metrics too: the ratio alone cannot rank
        % topologies with different coverage (see m4_handover_cost.m).
        e.n_inter_hi   = nan(1, nN);  e.ho_total_hi  = nan(1, nN);
        e.inter_per_ac_served_hi = nan(1, nN);
        e.mean_dist_hi = nan(1, nN);  e.p95_dist_hi  = nan(1, nN);
        e.ansp_order   = {t.candidates(t.selected_order(1:cap)).ansp_name};

        for j = 1:nN
            N = N_LIST(j);
            if N > cap, continue; end
            evalc('r4 = m4_handover_cost(tagged_data, COL, t, N, cfg);');
            e.pct_inter_lo(j) = r4.by_margin(1).pct_inter;
            e.pct_inter_hi(j) = r4.by_margin(2).pct_inter;
            e.served_lo(j)    = 100 - r4.by_margin(1).coverage_gap_pct;
            e.served_hi(j)    = 100 - r4.by_margin(2).coverage_gap_pct;
            b2 = r4.by_margin(2);
            e.n_inter_hi(j)  = b2.n_inter;
            e.ho_total_hi(j) = b2.total_handovers;
            if isfield(b2,'inter_per_aircraft_served')
                e.inter_per_ac_served_hi(j) = b2.inter_per_aircraft_served;
                e.mean_dist_hi(j) = b2.mean_served_distance_km;
                e.p95_dist_hi(j)  = b2.p95_served_distance_km;
            end

            [e.n_singleton(j), e.n_ansp(j)] = singleton_count(e.ansp_order(1:N));
        end

        % Collected in a cell and concatenated after the loop, so the field
        % set is defined once by the entries themselves.
        sweep_c{i} = e; %#ok<AGROW>
        fprintf('[M8]   swept: %-26s (cap N=%d)\n', reg(i).name, cap);
    end
    sweep = [sweep_c{:}];

    print_sweep('pct_inter %% (lower is better), F=5.5dB', sweep, N_LIST, 'pct_inter_hi');
    print_sweep('served traffic %% (higher is better), F=5.5dB', sweep, N_LIST, 'served_hi');
    print_sweep('pct_inter %% , F=2.6dB (sensitivity bound)', sweep, N_LIST, 'pct_inter_lo');
    print_sweep('served traffic %% , F=2.6dB', sweep, N_LIST, 'served_lo');
    % The ratio can tie while the absolute count differs, so both are shown.
    print_sweep('ABSOLUTE inter-provider handovers, F=5.5dB', sweep, N_LIST, 'n_inter_hi');
    print_sweep('inter-provider handovers per aircraft SERVED, F=5.5dB', sweep, N_LIST, 'inter_per_ac_served_hi');
    print_sweep('mean serving distance (km), F=5.5dB', sweep, N_LIST, 'mean_dist_hi');

    % ── SWEEP 2: failure concentration at a single matched N ──
    Nm = cfg.m8_m5_N;
    fprintf('\n[M8] ---- FAILURE CONCENTRATION AT MATCHED N=%d (F=5.5dB) ----\n', Nm);
    fprintf('[M8] %-26s %5s %12s %11s %11s %8s\n', ...
        'Topology', 'N', 'total FI', 'top1 %', 'even 100/N', 'ratio');

    conc = struct('name', {}, 'N', {}, 'total_forced_inter', {}, 'top1_share_pct', {}, ...
        'even_spread_pct', {}, 'concentration_ratio', {});
    for i = 1:nT
        t = reg(i).topo;
        N = min([Nm, reg(i).cap, numel(t.selected_order)]);
        evalc('r5 = m5_station_failure(tagged_data, COL, t, N, cfg);');
        b = r5.by_margin(2);
        even = 100 / N;
        conc(i).name = reg(i).name;
        conc(i).N = N;
        conc(i).total_forced_inter  = b.total_forced_inter_ticks;
        conc(i).top1_share_pct      = b.top1_forced_inter_share_pct;
        conc(i).even_spread_pct     = even;
        conc(i).concentration_ratio = b.top1_forced_inter_share_pct / even;
        fprintf('[M8] %-26s %5d %12d %10.2f%% %10.2f%% %8.2f\n', reg(i).name, N, ...
            conc(i).total_forced_inter, conc(i).top1_share_pct, even, conc(i).concentration_ratio);
    end

    % ── SWEEP 3: the same matched N, out of sample ──
    oos = struct('name', {}, 'N', {}, 'design_pct_inter', {}, 'validation_pct_inter', {}, 'delta', {});
    if exist(cfg.m8_validation_data, 'file')
        V = load(cfg.m8_validation_data);
        fprintf('\n[M8] ---- OUT-OF-SAMPLE AT MATCHED N=%d (F=5.5dB) ----\n', Nm);
        fprintf('[M8] Validation hour: %d ticks, %d aircraft\n', ...
            size(V.tagged_data,1), numel(unique(V.tagged_data(:,V.COL.ID))));
        fprintf('[M8] %-26s %5s %11s %13s %9s\n', 'Topology', 'N', 'design', 'validation', 'delta');
        for i = 1:nT
            t = reg(i).topo;
            N = min([Nm, reg(i).cap, numel(t.selected_order)]);
            evalc('rv = m4_handover_cost(V.tagged_data, V.COL, t, N, cfg);');
            j = find(N_LIST == N, 1);
            d = NaN; if ~isempty(j), d = sweep(i).pct_inter_hi(j); end
            oos(i).name = reg(i).name;
            oos(i).N = N;
            oos(i).design_pct_inter     = d;
            oos(i).validation_pct_inter = rv.by_margin(2).pct_inter;
            oos(i).delta = oos(i).validation_pct_inter - d;
            fprintf('[M8] %-26s %5d %10.2f%% %12.2f%% %+8.2f\n', reg(i).name, N, ...
                d, oos(i).validation_pct_inter, oos(i).delta);
        end
    else
        fprintf('\n[M8] Validation dataset not found (%s) — out-of-sample block skipped.\n', ...
            cfg.m8_validation_data);
    end

    % ── FEASIBILITY-PARITY BEFORE/AFTER ──
    % The constrained number is what M3c/M3g/M3h save and downstream modules
    % consume; the pre-constraint number only discloses the size of the correction.
    % Each pair is compared at the largest N <= Nm both variants reach
    % (Co-location caps below 12 stations).
    fprintf('\n[M8] ---- FEASIBILITY CONSTRAINTS: what they cost M3c/M3g/M3h ----\n');
    fprintf('[M8] %-26s %5s %16s %14s %10s\n', 'Topology', 'N', 'pre-constraint', 'constrained', 'change');
    parity = struct('name', {}, 'N', {}, 'pre_constraint', {}, 'constrained', {}, 'delta', {});
    pi_ = 0;
    for i = 1:nT
        k = find(strcmp({reg.name}, [reg(i).name ' (pre-constraint)']), 1);
        if isempty(k), continue; end
        both = find(~isnan(sweep(i).pct_inter_hi) & ~isnan(sweep(k).pct_inter_hi));
        if isempty(both), continue; end
        pj = both(find(N_LIST(both) <= Nm, 1, 'last'));
        if isempty(pj), pj = both(1); end
        a = sweep(k).pct_inter_hi(pj);   % pre-constraint twin
        b = sweep(i).pct_inter_hi(pj);   % constrained (primary)
        pi_ = pi_ + 1;
        parity(pi_).name = reg(i).name;
        parity(pi_).N = N_LIST(pj);
        parity(pi_).pre_constraint = a;
        parity(pi_).constrained = b;
        parity(pi_).delta = b - a;
        fprintf('[M8] %-26s %5d %15.2f%% %13.2f%% %+9.2f\n', reg(i).name, N_LIST(pj), a, b, b - a);
    end

    % ── CANDIDATE-PARITY AUDIT ──
    parity_audit = audit_candidate_parity(reg, cfg.m8_m5_N);

    results.sweep        = sweep;
    results.parity_audit = parity_audit;
    results.concentration = conc;
    results.out_of_sample = oos;
    results.parity        = parity;
    results.N_LIST        = N_LIST;
    results.matched_N     = Nm;
    results.registry_names = {reg.name};
    results.config_snapshot = cfg;

    if ~exist(cfg.output_data, 'dir'), mkdir(cfg.output_data); end
    save(fullfile(cfg.output_data, 'm8_topology_sweep.mat'), 'results');
    fprintf('\n[M8] Saved: %s\n', fullfile(cfg.output_data, 'm8_topology_sweep.mat'));
    fprintf('[M8] Matched-N topology sweep complete.\n');

end


% ── AUDIT_CANDIDATE_PARITY: how many deployed stations stand on candidates the
% traffic-only baseline pool never contained? The ANSP-aware pool is the
% traffic-only pool plus border pinch-point sites, so a zero count means a
% comparison against the baseline isolates the objective, not the site pool.
% Pools disjoint from the demand grid (lattice, beacon) are marked not comparable. ──
function audit = audit_candidate_parity(reg, N)

    base = find(strcmp({reg.name}, 'Naive'), 1);
    % Field list must match every assignment below exactly.
    audit = struct('name', {}, 'N', {}, 'n_exclusive', {}, 'pct_exclusive', {}, ...
                   'pool_relation', {}, 'comparable', {});
    if isempty(base)
        fprintf('\n[M8] Candidate-parity audit skipped: no traffic-only baseline in the registry.\n');
        return;
    end

    keyof = @(c) arrayfun(@(x) sprintf('%.4f_%.4f', x.lat, x.lon), c, 'UniformOutput', false);
    base_pool = keyof(reg(base).topo.candidates);

    fprintf('\n[M8] ---- CANDIDATE-PARITY AUDIT (at N=%d) ----\n', N);
    fprintf(['[M8] Stations standing on sites the traffic-only pool never contained.\n' ...
             '[M8] The count answers a confound only where the pools SHARE A LINEAGE, i.e.\n' ...
             '[M8] where one pool contains the other. A lattice or beacon pool is disjoint\n' ...
             '[M8] from the demand grid by construction, so 100%% there is definitional and\n' ...
             '[M8] carries no information: those families are not comparable site-for-site\n' ...
             '[M8] with the baseline and are marked accordingly.\n']);
    fprintf('[M8] %-26s %5s %12s %8s   %s\n', 'Topology', 'N', 'exclusive', 'share', 'pool vs baseline');

    for i = 1:numel(reg)
        t  = reg(i).topo;
        Ni = min([N, reg(i).cap, numel(t.selected_order)]);
        if Ni < 1, continue; end
        pool_i = keyof(t.candidates);
        sel    = keyof(t.candidates(t.selected_order(1:Ni)));
        n_ex   = numel(setdiff(sel, base_pool));

        n_shared = numel(intersect(pool_i, base_pool));
        if n_shared == 0
            rel = 'disjoint (not comparable)';       comparable = false;
        elseif isempty(setdiff(base_pool, pool_i))
            rel = 'superset of baseline';            comparable = true;
        elseif isempty(setdiff(pool_i, base_pool))
            rel = 'same as baseline';                comparable = true;
        else
            rel = 'partial overlap';                 comparable = true;
        end

        if comparable
            fprintf('[M8] %-26s %5d %12d %7.0f%%   %s\n', reg(i).name, Ni, n_ex, 100*n_ex/Ni, rel);
        else
            fprintf('[M8] %-26s %5d %12s %8s   %s\n', reg(i).name, Ni, '-', '-', rel);
        end

        audit(end+1) = struct('name', reg(i).name, 'N', Ni, ...
            'n_exclusive', n_ex, 'pct_exclusive', 100*n_ex/Ni, ...
            'pool_relation', rel, 'comparable', comparable); %#ok<AGROW>
    end

    cmp = audit([audit.comparable]);
    clean = cmp(strcmp({cmp.name},'Naive') | [cmp.n_exclusive] == 0);
    fprintf(['[M8] Within the shared-lineage family, %d of %d strategies deploy entirely on\n' ...
             '[M8] sites the baseline also had, so those comparisons isolate the objective.\n'], ...
             numel(clean), numel(cmp));

end


% ── BUILD_TOPOLOGY_REGISTRY: every saved topology plus the pre-constraint twins
% of M3c/M3g/M3h. M3/M3b/M3c/M3g/M3h wrap scenarios in .optimistic/.conservative;
% M3e/M3f store the placement flat. ──
function reg = build_topology_registry(cfg)

    reg = struct('name', {}, 'topo', {}, 'cap', {}, 'order_unconstrained', {});
    D   = cfg.output_data;
    Nmx = cfg.n_max_sweep;

    reg = add_topo(reg, 'Naive',        fullfile(D,'topology_study.mat'),                Nmx);
    reg = add_topo(reg, 'ANSP-aware',   fullfile(D,'topology_study_ansp_aware.mat'),     Nmx);
    reg = add_topo(reg, 'Geometric lattice',       fullfile(D,'topology_study_literature_grid.mat'),Nmx);
    reg = add_topo(reg, 'Traffic-weighted lattice', fullfile(D,'topology_study_weighted_hex.mat'),   Nmx);
    reg = add_topo(reg, 'Minimax',      fullfile(D,'topology_study_minimax.mat'),        Nmx);
    reg = add_topo(reg, 'Resilient',    fullfile(D,'topology_study_resilient.mat'),      Nmx);
    reg = add_topo(reg, 'Co-location',  fullfile(D,'topology_study_colocation.mat'),     Nmx);

    % Optimized (search_optimized_topology.m) is loaded, not recomputed; its
    % search ran at one N, so the cap stops evaluation past its station count.
    p = fullfile(D, 'm3_optimal_search.mat');
    if exist(p, 'file')
        S = load(p, 'pool', 'results_by_p');
        w = S.pool(S.results_by_p(1).winner_idx);
        reg(end+1) = struct('name', 'Optimized', ...
            'topo', struct('candidates', w.candidates, 'selected_order', w.selected_order), ...
            'cap', numel(w.selected_order), 'order_unconstrained', []);
    else
        fprintf('[M8] WARNING: %s not found — Optimized excluded from the sweep.\n', p);
    end

    % ── PRE-CONSTRAINT TWINS ──
    % M3c/M3g/M3h enforce siting constraints themselves (apply_siting_constraints.m)
    % and also save the unconstrained order; only that saved order is registered
    % here, nothing is reconstructed.
    for nm = {'Geometric lattice', 'Traffic-weighted lattice', 'Co-location'}
        k = find(strcmp({reg.name}, nm{1}), 1);
        if isempty(k) || isempty(reg(k).order_unconstrained), continue; end
        t = reg(k).topo;
        ord_u = reg(k).order_unconstrained;
        fprintf('[M8] %-14s pre-constraint twin registered: %d sites (constrained: %d)\n', ...
            nm{1}, numel(ord_u), numel(t.selected_order));
        reg(end+1) = struct('name', [nm{1} ' (pre-constraint)'], ...
            'topo', struct('candidates', t.candidates, 'selected_order', ord_u), ...
            'cap', min(Nmx, numel(ord_u)), 'order_unconstrained', []); %#ok<AGROW>
    end

end


function reg = add_topo(reg, name, path, cap)
    if ~exist(path, 'file')
        fprintf('[M8] WARNING: %s not found — %s excluded from the sweep.\n', path, name);
        return;
    end
    S = load(path);
    fn = fieldnames(S);
    r = S.(fn{1});
    ord_u = [];
    if isfield(r, 'selected_order_unconstrained'), ord_u = r.selected_order_unconstrained; end
    if isfield(r, 'conservative'), r = r.conservative; end
    if isfield(r, 'n_stations_available'), cap = min(cap, r.n_stations_available); end
    reg(end+1) = struct('name', name, ...
        'topo', struct('candidates', r.candidates, 'selected_order', r.selected_order), ...
        'cap', min(cap, numel(r.selected_order)), ...
        'order_unconstrained', ord_u); %#ok<AGROW>
end


% ── SINGLETON_COUNT: ANSPs holding exactly one station in this prefix. Such a
% station has no same-ANSP neighbour, so every handover through it crosses an
% administrative boundary (see m9_singleton_analysis.m). ──
function [n_singleton, n_ansp] = singleton_count(ansp_names)
    u = unique(ansp_names);
    c = cellfun(@(x) sum(strcmp(ansp_names, x)), u);
    n_singleton = sum(c == 1);
    n_ansp = numel(u);
end


function print_sweep(title_str, sweep, N_LIST, field)
    fprintf('\n[M8] ---- %s ----\n', title_str);
    fprintf('[M8] %-26s', 'Topology'); fprintf('%8d', N_LIST); fprintf('\n');
    for i = 1:numel(sweep)
        fprintf('[M8] %-26s', sweep(i).name);
        v = sweep(i).(field);
        for j = 1:numel(N_LIST)
            if isnan(v(j)), fprintf('%8s', '.'); else, fprintf('%8.2f', v(j)); end
        end
        fprintf('\n');
    end
end
