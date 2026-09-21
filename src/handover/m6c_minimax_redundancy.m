% M6C_MINIMAX_REDUNDANCY  Minimax backup placement: minimise the resulting worst station.
%
% M6 backs up whichever station M5 ranks worst today. This module instead
% evaluates every eligible candidate as station N+1 and keeps the one that
% minimises the post-failure worst-station forced inter-ANSP tick count,
% i.e. the k-center minimax logic of Gonzalez (1985) / Hochbaum & Shmoys
% (1985) retargeted at repair. The objective is the absolute count, not the
% share of the topology total, because a large poorly-connected candidate
% can shrink a share without removing a single tick. Only candidates whose
% ANSP owns an active station are eligible, since M5's redirect rule can
% only reclassify a forced-inter tick when the failed station's ANSP gains
% a sibling. Distances to the base N stations are cached once per aircraft
% and the redirect loop is vectorised; the winner should be re-verified
% with m5_station_failure, which is the number that gets reported.
%
% INPUT : tagged_data, COL (M1); topology, N; config.
% OUTPUT: topology_aug, N_aug (winner appended); report (winner, rejected
%         share-only winner and per-candidate scores).

function [topology_aug, N_aug, report] = m6c_minimax_redundancy(tagged_data, COL, topology, N, config)

    fprintf('[M6c] Minimax redundancy search starting (base N=%d)...\n', N);

    active_idx  = topology.selected_order(1:N);
    active      = topology.candidates(active_idx);
    active_lat  = [active.lat]';
    active_lon  = [active.lon]';
    active_ansp = {active.ansp_name}';

    R = config.gs_radius_km;
    F_db = config.ci_fade_margin_db_list(end);   % conservative bound, same as M6
    ratio = 10^(F_db/20);
    R_outer = R * ratio;
    n_hyst = config.assignment_hysteresis_n;

    fprintf('[M6c]  Searching at conservative margin F=%.1fdB (R_outer=%.0fkm)\n', F_db, R_outer);

    % ── Eligible candidates: unused sites whose ANSP owns >=1 active station ──
    n_cand = numel(topology.candidates);
    used = false(1, n_cand);
    used(active_idx) = true;
    cand_ansp = {topology.candidates.ansp_name};
    active_ansp_set = unique(active_ansp);
    eligible_idx = find(~used & ismember(cand_ansp, active_ansp_set));
    fprintf('[M6c]  %d eligible same-ANSP-as-active candidates (of %d unused, %d total pool)\n', ...
        numel(eligible_idx), sum(~used), n_cand);

    % ── Cache per-aircraft base distances once ──
    ac_ids = unique(tagged_data(:, COL.ID));
    n_ac = numel(ac_ids);
    ac_cache = struct('lat', {}, 'lon', {}, 'd_base', {}, 'valid', {});
    n_valid_ac = 0;
    for a = 1:n_ac
        rows = tagged_data(tagged_data(:,COL.ID) == ac_ids(a), :);
        lat = rows(:, COL.LAT); lon = rows(:, COL.LON);
        ntk = numel(lat);
        if ntk < 2, continue; end
        n_valid_ac = n_valid_ac + 1;
        d_base = zeros(ntk, N);
        for s = 1:N
            d_base(:,s) = haversine_km(lat, lon, active_lat(s), active_lon(s));
        end
        ac_cache(n_valid_ac).lat = lat;
        ac_cache(n_valid_ac).lon = lon;
        ac_cache(n_valid_ac).d_base = d_base;
    end
    fprintf('[M6c]  Cached base distances for %d aircraft\n', n_valid_ac);

    % ── Search: evaluate every eligible candidate as station N+1 ──
    n_eligible = numel(eligible_idx);
    top1_share_by_cand = zeros(n_eligible, 1);
    total_forced_by_cand = zeros(n_eligible, 1);
    max_forced_by_cand = zeros(n_eligible, 1);

    t_search = tic;
    for c = 1:n_eligible
        cand = topology.candidates(eligible_idx(c));
        aug_ansp = [active_ansp; {cand.ansp_name}];
        served = zeros(N+1, 1);
        forced = zeros(N+1, 1);

        for a = 1:n_valid_ac
            lat = ac_cache(a).lat; lon = ac_cache(a).lon;
            d_base = ac_cache(a).d_base;
            d_new = haversine_km(lat, lon, cand.lat, cand.lon);
            d_aug = [d_base, d_new];

            [dmin, idxmin] = min(d_aug, [], 2);
            raw = idxmin;
            raw(dmin > R_outer) = 0;
            confirmed = hysteresis_confirm(raw, n_hyst);

            valid = confirmed > 0;
            if ~any(valid), continue; end
            k_valid = confirmed(valid);
            rows_valid = find(valid);

            % Vectorised M5 redirect: mask each tick's serving column, take the survivor min.
            d_masked = d_aug(valid, :);
            lin_idx = sub2ind(size(d_masked), (1:numel(rows_valid))', k_valid);
            d_masked(lin_idx) = Inf;
            [d2, s2] = min(d_masked, [], 2);

            is_gap = d2 > R_outer;
            same_ansp = strcmp(aug_ansp(k_valid), aug_ansp(s2));
            is_forced = ~is_gap & ~same_ansp;

            served = served + accumarray(k_valid, 1, [N+1, 1]);
            forced = forced + accumarray(k_valid, double(is_forced), [N+1, 1]);
        end

        total_forced_by_cand(c) = sum(forced);
        max_forced_by_cand(c) = max(forced);
        top1_share_by_cand(c) = 100 * max(forced) / max(1, sum(forced));

        if mod(c, 40) == 0 || c == n_eligible
            fprintf('[M6c]  ...evaluated %d/%d candidates (%.0fs elapsed)\n', c, n_eligible, toc(t_search));
        end
    end
    fprintf('[M6c]  Search complete in %.0fs\n', toc(t_search));

    % ── Minimax winner: minimise the absolute worst-station count, not its share ──
    [best_max, best_c] = min(max_forced_by_cand);
    best_idx = eligible_idx(best_c);
    best_cand = topology.candidates(best_idx);

    % For the record: what the rejected share-based objective would have picked.
    [share_winner_share, share_winner_c] = min(top1_share_by_cand);
    share_winner_idx = eligible_idx(share_winner_c);

    fprintf('[M6c] Minimax winner (min worst-station COUNT): candidate #%d (%s) -> worst count %d (share %.1f%%, total %d)\n', ...
        best_idx, best_cand.ansp_name, best_max, top1_share_by_cand(best_c), total_forced_by_cand(best_c));
    fprintf('[M6c] (For comparison: the share-only objective would have picked candidate #%d, share %.1f%% -- but worst count %d)\n', ...
        share_winner_idx, share_winner_share, max_forced_by_cand(share_winner_c));

    topology_aug = topology;
    topology_aug.selected_order = [active_idx(:); best_idx];
    N_aug = N + 1;

    report.eligible_count = n_eligible;
    report.winner_candidate_idx = best_idx;
    report.winner_ansp = best_cand.ansp_name;
    report.fast_search_max_forced = best_max;
    report.fast_search_top1_share_pct = top1_share_by_cand(best_c);
    report.fast_search_total_forced = total_forced_by_cand(best_c);
    report.rejected_share_only_winner_idx = share_winner_idx;
    report.rejected_share_only_winner_share_pct = share_winner_share;
    report.rejected_share_only_winner_max_forced = max_forced_by_cand(share_winner_c);
    report.all_candidate_idx = eligible_idx;
    report.all_top1_share_pct = top1_share_by_cand;
    report.all_total_forced = total_forced_by_cand;
    report.all_max_forced = max_forced_by_cand;

    fprintf('[M6c] Minimax redundancy search complete.\n');
end
