% M6_REDUNDANCY_PLACEMENT  Add a same-ANSP backup station next to the riskiest one.
%
% Takes the station with the most forced inter-ANSP ticks in one M5 margin
% entry and appends, as station N+1, the nearest unused candidate owned by the
% same ANSP from the topology's own pool. A nearest-site heuristic, not a
% placement re-run, so it isolates what fixing that one weak point buys. If no
% same-ANSP candidate is free, report.found = false and topology is unchanged.
%
% INPUT : topology; N; m5_margin_entry (one element of m5 results.by_margin); config.
% OUTPUT: topology_aug, N_aug (ready for m5_station_failure); report struct.

function [topology_aug, N_aug, report] = m6_redundancy_placement(topology, N, m5_margin_entry, config)

    fprintf('[M6] Redundancy placement starting (base N=%d)...\n', N);

    active_idx = topology.selected_order(1:N);
    per_station = m5_margin_entry.per_station;

    [worst_count, worst_k] = max([per_station.forced_inter_ticks]);
    risky_cand_idx = active_idx(worst_k);
    risky = topology.candidates(risky_cand_idx);
    risky_ansp = risky.ansp_name;

    fprintf('[M6] Riskiest station: #%d, owner=%s, forced_inter_ticks=%d\n', ...
        worst_k, risky_ansp, worst_count);

    n_cand = numel(topology.candidates);
    used = false(1, n_cand);
    used(active_idx) = true;

    cand_ansp = {topology.candidates.ansp_name};
    same_ansp_free = ~used & strcmp(cand_ansp, risky_ansp);
    free_idx = find(same_ansp_free);

    if isempty(free_idx)
        fprintf('[M6] No unused %s-owned candidate site found in this topology''s candidate pool.\n', risky_ansp);
        fprintf('[M6] Cannot add a same-ANSP backup here — %s may not have room for a second cell at this radius.\n', risky_ansp);
        topology_aug = topology;
        N_aug = N;
        report.found = false;
        report.risky_station_idx = worst_k;
        report.risky_ansp = risky_ansp;
        report.risky_forced_inter_ticks = worst_count;
        fprintf('[M6] Redundancy placement complete (no fix applied).\n');
        return;
    end

    cand_lat = [topology.candidates(free_idx).lat]';
    cand_lon = [topology.candidates(free_idx).lon]';
    d = haversine_km(risky.lat, risky.lon, cand_lat, cand_lon);
    [d_backup, i_min] = min(d);
    backup_idx = free_idx(i_min);

    fprintf('[M6] Backup site chosen: candidate #%d, %.0fkm from the risky station, same owner (%s)\n', ...
        backup_idx, d_backup, risky_ansp);

    topology_aug = topology;
    topology_aug.selected_order = [active_idx(:); backup_idx];
    N_aug = N + 1;

    report.found = true;
    report.risky_station_idx = worst_k;
    report.risky_ansp = risky_ansp;
    report.risky_forced_inter_ticks = worst_count;
    report.backup_candidate_idx = backup_idx;
    report.backup_distance_km = d_backup;

    fprintf('[M6] Redundancy placement complete — augmented topology has N=%d stations.\n', N_aug);

end
