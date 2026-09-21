% M5_STATION_FAILURE  Leave-one-out station failure blast radius.
%
% For every active station k and every fade margin, counts the ticks k serves
% at baseline (M4 soft-edge assignment with hysteresis) and where those ticks
% land if k fails at that instant: nearest surviving station in the same ANSP
% (absorbed intra), a different ANSP (forced inter-ANSP handover), or no
% station in range (new gap). The redirect is instantaneous nearest-survivor
% at that tick, with no hysteresis, modelling a sudden hard failure; no
% failure probabilities or capacity limits are implied. Computed in one pass
% per aircraft by masking column k of the baseline distance matrix.
%
% INPUT : tagged_data, COL (M1); topology (.candidates, .selected_order); N; config.
% OUTPUT: results.by_margin(m).per_station(k) plus an undirected ANSP-pair
%         breakdown; saved to results/m5_<label>_N<N>.mat if config.m5_save_label is set.

function results = m5_station_failure(tagged_data, COL, topology, N, config)

    fprintf('[M5] Station-failure blast-radius analysis starting (N=%d)...\n', N);

    active_idx = topology.selected_order(1:N);
    active = topology.candidates(active_idx);
    active_lat  = [active.lat]';
    active_lon  = [active.lon]';
    active_ansp = {active.ansp_name}';

    R = config.gs_radius_km;
    n_hyst = config.assignment_hysteresis_n;

    n_margins = numel(config.ci_fade_margin_db_list);
    ac_ids = unique(tagged_data(:, COL.ID));
    n_ac = numel(ac_ids);

    by_margin = struct('fade_margin_db', {}, 'R_inner_km', {}, 'R_outer_km', {}, 'per_station', {}, ...
        'total_forced_inter_ticks', {}, 'top1_forced_inter_share_pct', {}, 'ansp_pair_forced_inter', {});

    for m = 1:n_margins
        F_db = config.ci_fade_margin_db_list(m);
        ratio = 10^(F_db/20);
        R_inner = R / ratio;
        R_outer = R * ratio;

        fprintf('[M5]  Margin F=%.1fdB -> R_inner=%.0fkm, R_outer=%.0fkm\n', F_db, R_inner, R_outer);

        served_ticks   = zeros(N, 1);
        forced_inter   = zeros(N, 1);   % redirected to a different ANSP's station
        absorbed_intra = zeros(N, 1);   % redirected to the same ANSP's station
        new_gap        = zeros(N, 1);   % no surviving station in range

        % Undirected ANSP-pair totals (topology-wide, both failure directions):
        % an interconnection agreement is a pairwise decision, see m6b.
        pair_map = containers.Map('KeyType', 'char', 'ValueType', 'double');

        for a = 1:n_ac
            rows = tagged_data(tagged_data(:,COL.ID) == ac_ids(a), :);
            lat = rows(:, COL.LAT);
            lon = rows(:, COL.LON);
            ntk = numel(lat);
            if ntk < 2, continue; end

            d = zeros(ntk, N);
            for s = 1:N
                d(:,s) = haversine_km(lat, lon, active_lat(s), active_lon(s));
            end
            [dmin, idxmin] = min(d, [], 2);

            raw_station = idxmin;
            raw_station(dmin > R_outer) = 0; % 0 = out of range at baseline

            confirmed_station = hysteresis_confirm(raw_station, n_hyst);

            for t = 1:ntk
                k = confirmed_station(t);
                if k == 0, continue; end   % unserved at baseline: not a failure event

                served_ticks(k) = served_ticks(k) + 1;

                drow = d(t, :);
                drow(k) = Inf;              % exclude the failed station
                [d2, s2] = min(drow);

                if d2 > R_outer
                    new_gap(k) = new_gap(k) + 1;
                elseif strcmp(active_ansp{s2}, active_ansp{k})
                    absorbed_intra(k) = absorbed_intra(k) + 1;
                else
                    forced_inter(k) = forced_inter(k) + 1;
                    pair_names = sort({active_ansp{k}, active_ansp{s2}});
                    pair_key = [pair_names{1} '||' pair_names{2}];
                    if isKey(pair_map, pair_key)
                        pair_map(pair_key) = pair_map(pair_key) + 1;
                    else
                        pair_map(pair_key) = 1;
                    end
                end
            end
        end

        per_station = struct('station_idx', {}, 'ansp_name', {}, 'served_ticks', {}, ...
            'forced_inter_ticks', {}, 'pct_forced_inter', {}, 'pct_new_gap', {}, 'pct_absorbed_intra', {});
        for k = 1:N
            entry.station_idx = k;
            entry.ansp_name = active_ansp{k};
            entry.served_ticks = served_ticks(k);
            denom = max(1, served_ticks(k));
            entry.forced_inter_ticks = forced_inter(k);
            entry.pct_forced_inter   = 100 * forced_inter(k)   / denom;
            entry.pct_new_gap        = 100 * new_gap(k)        / denom;
            entry.pct_absorbed_intra = 100 * absorbed_intra(k) / denom;
            per_station(k) = entry;
        end

        pair_keys = keys(pair_map);
        pair_vals = cell2mat(values(pair_map));
        [pair_vals_sorted, pair_ord] = sort(pair_vals, 'descend');
        ansp_pair_forced_inter = struct('ansp_a', {}, 'ansp_b', {}, 'count', {});
        for i = 1:numel(pair_keys)
            parts = strsplit(pair_keys{pair_ord(i)}, '||');
            ansp_pair_forced_inter(i).ansp_a = parts{1};
            ansp_pair_forced_inter(i).ansp_b = parts{2};
            ansp_pair_forced_inter(i).count  = pair_vals_sorted(i);
        end

        total_forced = sum(forced_inter);
        [worst_count, worst_k] = max(forced_inter);
        top1_share = 100 * worst_count / max(1, total_forced);

        fprintf('[M5]  ---- BLAST RADIUS SUMMARY (F=%.1fdB) ----\n', F_db);
        fprintf('[M5]  Total forced-inter-ANSP ticks across all single-station failures: %d\n', total_forced);
        fprintf('[M5]  Riskiest station: #%d (%s) — %d forced-inter ticks alone (%.1f%% of total)\n', ...
            worst_k, active_ansp{worst_k}, worst_count, top1_share);
        [~, order] = sort(forced_inter, 'descend');
        top_n = min(3, N);
        for i = 1:top_n
            k = order(i);
            fprintf('[M5]    #%2d %-20s served=%5d  forced_inter=%4d (%.1f%%)  new_gap=%.1f%%\n', ...
                k, active_ansp{k}, per_station(k).served_ticks, per_station(k).forced_inter_ticks, ...
                per_station(k).pct_forced_inter, per_station(k).pct_new_gap);
        end

        be.fade_margin_db = F_db;
        be.R_inner_km = R_inner;
        be.R_outer_km = R_outer;
        be.per_station = per_station;
        be.total_forced_inter_ticks = total_forced;
        be.top1_forced_inter_share_pct = top1_share;
        be.ansp_pair_forced_inter = ansp_pair_forced_inter;
        by_margin(m) = be;
    end

    results.N = N;
    results.by_margin = by_margin;
    results.config_snapshot = config;

    if isfield(config, 'm5_save_label') && ~isempty(config.m5_save_label)
        if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
        fname = sprintf('m5_%s_N%d.mat', config.m5_save_label, N);
        save(fullfile(config.output_data, fname), 'results');
        fprintf('[M5] Saved: %s\n', fullfile(config.output_data, fname));
    end

    fprintf('[M5] Station-failure blast-radius analysis complete.\n');

end
