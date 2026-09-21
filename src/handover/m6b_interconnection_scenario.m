% M6B_INTERCONNECTION_SCENARIO  Policy fix: mitigation if ANSP pairs interconnect.
%
% RFC 9372's break-before-make vs make-before-break split depends on whether
% the two ANSPs are interconnected; M5 models none as such. This relabels M5's
% forced inter-ANSP ticks under an incremental rollout: ANSP pairs are ranked
% by real border-crossing volume (M2, not M5's own counts, to avoid
% circularity) and the cumulative share of exposure neutralised is reported as
% the top-K pairs interconnect. No re-simulation or cost model is implied.
%
% INPUT : m5_margin_entry; border_stats from m2_ansp_border_crossings; config.
% OUTPUT: report (mitigation curve, ranked pairs, real-world rank of M5's top
%         pairs), saved to results/m6b_interconnection.mat.

function report = m6b_interconnection_scenario(m5_margin_entry, border_stats, config)

    fprintf('[M6b] Interconnection scenario starting...\n');

    ansp_names  = border_stats.ansp_names;
    pair_counts = border_stats.pair_counts;   % undirected, symmetric, diag=0
    n_ansp = numel(ansp_names);

    % ── Rank ANSP pairs by border-crossing volume (M2) ──
    [sorted_vals, sorted_idx] = sort(pair_counts(:), 'descend');
    ranked_a = {}; ranked_b = {}; ranked_count = [];
    for kk = 1:numel(sorted_idx)
        if sorted_vals(kk) == 0, break; end
        [i, j] = ind2sub([n_ansp, n_ansp], sorted_idx(kk));
        if i >= j, continue; end   % undirected pair appears twice; keep once
        ranked_a{end+1}     = ansp_names{i}; %#ok<AGROW>
        ranked_b{end+1}     = ansp_names{j}; %#ok<AGROW>
        ranked_count(end+1) = sorted_vals(kk); %#ok<AGROW>
    end
    n_pairs = numel(ranked_a);

    rank_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for K = 1:n_pairs
        names = sort({ranked_a{K}, ranked_b{K}});
        rank_map([names{1} '||' names{2}]) = K;
    end

    % ── M5 forced-inter count per pair ──
    m5_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
    m5_pairs = m5_margin_entry.ansp_pair_forced_inter;
    for i = 1:numel(m5_pairs)
        names = sort({m5_pairs(i).ansp_a, m5_pairs(i).ansp_b});
        m5_map([names{1} '||' names{2}]) = m5_pairs(i).count;
    end

    total_forced = m5_margin_entry.total_forced_inter_ticks;

    % ── Mitigation curve: cumulative % neutralised as K grows ──
    mitigation_curve = zeros(n_pairs, 1);
    cum_mitigated = 0;
    for K = 1:n_pairs
        names = sort({ranked_a{K}, ranked_b{K}});
        key = [names{1} '||' names{2}];
        if isKey(m5_map, key)
            cum_mitigated = cum_mitigated + m5_map(key);
        end
        mitigation_curve(K) = 100 * cum_mitigated / max(1, total_forced);
    end

    fprintf('[M6b] ---- MITIGATION CURVE (cumulative %% of forced-inter ticks neutralised) ----\n');
    checkpoints = unique(min(n_pairs, [1, 3, 5, 10, n_pairs]));
    for K = checkpoints
        fprintf('[M6b]   Top-%2d real-world pairs interconnected -> %5.1f%% of forced-inter exposure neutralised\n', ...
            K, mitigation_curve(K));
    end

    % ── Real-world rank of M5's worst contributing pairs ──
    fprintf('[M6b] ---- M5''s top contributing ANSP pairs vs. real-world interconnection priority ----\n');
    n_show = min(5, numel(m5_pairs));
    top_pairs_ranked = struct('ansp_a', {}, 'ansp_b', {}, 'forced_inter_count', {}, 'real_world_rank', {});
    for i = 1:n_show
        names = sort({m5_pairs(i).ansp_a, m5_pairs(i).ansp_b});
        key = [names{1} '||' names{2}];
        if isKey(rank_map, key)
            rk = rank_map(key);
            rk_str = sprintf('rank %d of %d', rk, n_pairs);
        else
            rk = NaN;
            rk_str = 'NOT in M2''s confirmed-crossing list (0 real crossings observed)';
        end
        fprintf('[M6b]   %-15s <-> %-20s : %5d forced-inter ticks -- %s\n', ...
            m5_pairs(i).ansp_a, m5_pairs(i).ansp_b, m5_pairs(i).count, rk_str);
        top_pairs_ranked(i).ansp_a = m5_pairs(i).ansp_a;
        top_pairs_ranked(i).ansp_b = m5_pairs(i).ansp_b;
        top_pairs_ranked(i).forced_inter_count = m5_pairs(i).count;
        top_pairs_ranked(i).real_world_rank = rk;
    end

    report.total_forced_inter_ticks = total_forced;
    report.n_ansp_pairs_real = n_pairs;
    report.mitigation_curve_pct = mitigation_curve;
    report.ranked_pairs = struct('ansp_a', ranked_a, 'ansp_b', ranked_b, 'crossing_count', num2cell(ranked_count));
    report.top_m5_pairs_ranked = top_pairs_ranked;

    % Persisted so the mitigation numbers can be tabulated without re-running the pipeline.
    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'm6b_interconnection.mat'), 'report');
    fprintf('[M6b] Saved: %s\n', fullfile(config.output_data, 'm6b_interconnection.mat'));

    fprintf('[M6b] Interconnection scenario complete.\n');

end
