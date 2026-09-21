% M7C_SENSITIVITY  Link-budget parameter sweep: is the topology ranking stable?
%
% M7's classification rests on three parameters no published source fixes for
% a deployed LDACS network (config.gs_eirp_dbm, dme_oob_rejection_db,
% acm_64qam_margin_db) plus the documented decode-threshold range (3.2-6.0 dB).
% Each is swept, m7_signal_quality is re-run per topology and value, and the
% clean fraction and a mid-relay-bound throughput are tabulated. The claim
% tested is that the ranking, and specifically the throughput cost of ANSP-aware
% vs traffic-only siting (H4), is stable although absolute percentages are not.
%
% INPUT : tagged_data, COL, topologies (nT-by-3 cell {label, scen, N}), config.
% OUTPUT: results saved to results/m7c_sensitivity.mat; figure via m7c_visualize.

function results = m7c_sensitivity(tagged_data, COL, topologies, config)

    fprintf('\n[M7c] Link-budget sensitivity analysis starting...\n');

    cfg0 = config;
    cfg0.m7_model = 'linkbudget';

    sweeps = { ...
        'acm_64qam_margin_db',  [6 9 12 15 18 24], 'ACM 64QAM margin (dB)'; ...
        'dme_oob_rejection_db', [30 40 50 60],     'DME out-of-band rejection (dB)'; ...
        'gs_eirp_dbm',          [36 41 46 51],     'Ground-station EIRP (dBm)'; ...
        'ci_required_db_max',   [3.2 6.0],         'LDACS decode threshold (dB)'};

    nT = size(topologies, 1);   % rows, not numel: topologies is nT-by-3
    results = struct('param', {}, 'label', {}, 'values', {}, 'topologies', {}, ...
        'pct_clean', {}, 'throughput', {}, 'rank_stable', {});

    for s = 1:size(sweeps,1)
        pname = sweeps{s,1}; vals = sweeps{s,2};
        clean_m = nan(nT, numel(vals));
        thr_m   = nan(nT, numel(vals));

        for v = 1:numel(vals)
            cfg = cfg0; cfg.(pname) = vals(v);
            for i = 1:nT
                evalc('q = m7_signal_quality(tagged_data, COL, topologies{i,2}, topologies{i,3}, cfg, ''m7c_tmp'');');
                clean_m(i,v) = q.pct_clean;
                % Mid relay bound (0.75x robust): the relay band would be a
                % constant offset on every column of a cross-parameter comparison.
                thr_m(i,v) = (q.pct_clean*q.rate_fast_kbit_s + q.pct_fec*q.rate_robust_kbit_s + ...
                              q.pct_relay*0.75*q.rate_robust_kbit_s) / 100;
            end
        end

        % Same ordering in every column?
        [~, ord] = sort(thr_m, 1, 'descend');
        rank_stable = all(all(ord == ord(:,1)));

        fprintf('\n[M7c] ---- %s ----\n', sweeps{s,3});
        fprintf('[M7c] %-20s', 'Topology'); fprintf('%16g', vals); fprintf('\n');
        for i = 1:nT
            fprintf('[M7c] %-20s', topologies{i,1});
            for v = 1:numel(vals)
                fprintf('   %5.1f%% /%5.0f', clean_m(i,v), thr_m(i,v));
            end
            fprintf('\n');
        end
        fprintf('[M7c] clean fraction spans %.1f%% to %.1f%% across this sweep | ranking stable: %s\n', ...
            min(clean_m(:)), max(clean_m(:)), bool_str(rank_stable));

        results(s).param       = pname;
        results(s).label       = sweeps{s,3};
        results(s).values      = vals;
        results(s).topologies  = topologies(:,1)';
        results(s).pct_clean   = clean_m;
        results(s).throughput  = thr_m;
        results(s).rank_stable = rank_stable;
    end

    % ── Verdict ──
    % Two separate questions: (a) is the full ordering stable (generally no,
    % the best topology depends on EIRP); (b) does ANSP-aware siting cost
    % throughput vs traffic-only (H4), reported as the worst-case gap over all settings.
    all_stable = all([results.rank_stable]);
    fprintf('\n[M7c] ================= VERDICT =================\n');
    fprintf('[M7c] Absolute percentages are assumption-driven: the clean fraction of a\n');
    fprintf('[M7c] single topology spans %.0f%%-%.0f%% across these sweeps. They must not be\n', ...
        min(cellfun(@(x) min(x(:)), {results.pct_clean})), ...
        max(cellfun(@(x) max(x(:)), {results.pct_clean})));
    fprintf('[M7c] quoted as predictions of real network performance.\n');
    fprintf('[M7c] Full topology ranking stable across every sweep: %s\n', bool_str(all_stable));

    ia = find(strcmpi(topologies(:,1), 'ANSP-aware'), 1);
    in = find(strcmpi(topologies(:,1), 'naive'), 1);
    if ~isempty(ia) && ~isempty(in)
        worst_gap = -Inf; worst_where = '';
        for s = 1:numel(results)
            g = 100 * (results(s).throughput(in,:) - results(s).throughput(ia,:)) ./ ...
                       results(s).throughput(in,:);
            [mx, k] = max(g);
            if mx > worst_gap
                worst_gap = mx;
                worst_where = sprintf('%s = %g', results(s).label, results(s).values(k));
            end
        end
        fprintf('[M7c] H4 TEST — worst-case throughput cost of ANSP-aware vs naive, over\n');
        fprintf('[M7c] every parameter setting tested: %+.2f%% (at %s)\n', worst_gap, worst_where);
        fprintf('[M7c] H4 (no material sacrifice) is %s by this analysis.\n', ...
            ternary(worst_gap < 5, 'SUPPORTED', 'NOT supported'));
        results(1).h4_worst_gap_pct = worst_gap;
        results(1).h4_worst_where   = worst_where;
    end

    p = fullfile(config.output_data, 'signal_quality_m7c_tmp.mat');
    if exist(p,'file'), delete(p); end
    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'm7c_sensitivity.mat'), 'results');
    fprintf('[M7c] Saved: %s\n', fullfile(config.output_data, 'm7c_sensitivity.mat'));

    m7c_visualize(results, config);
    fprintf('[M7c] Link-budget sensitivity analysis complete.\n');

end


function s = bool_str(b)
    if b, s = 'yes'; else, s = 'NO'; end
end
