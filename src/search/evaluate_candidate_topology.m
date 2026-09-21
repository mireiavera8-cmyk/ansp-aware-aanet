function entry = evaluate_candidate_topology(label, candidates, selected_order, tagged_data, COL, config, N, grid_points, R_inner_km, R_outer_km)
% EVALUATE_CANDIDATE_TOPOLOGY  Score one constructed topology at N stations:
%   demand coverage (M3 metric), inter-ANSP handover share and absolute
%   counts (M4, conservative margin), and failure concentration (M5).
    topo.candidates = candidates;
    topo.selected_order = selected_order;

    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';
    grid_lat = [grid_points.lat]'; grid_lon = [grid_points.lon]';
    grid_weight = [grid_points.weight]';
    idx = selected_order(1:N);
    best = zeros(numel(grid_points),1);
    for k = 1:N
        d = haversine_km(cand_lat(idx(k)), cand_lon(idx(k)), grid_lat, grid_lon);
        best = max(best, connection_probability(d, R_inner_km, R_outer_km));
    end
    coverage_pct = 100 * sum(grid_weight .* best) / sum(grid_weight);

    evalc('res4 = m4_handover_cost(tagged_data, COL, topo, N, config);');
    evalc('res5 = m5_station_failure(tagged_data, COL, topo, N, config);');
    b2 = res4.by_margin(2);

    entry.label          = label;
    entry.candidates     = candidates;
    entry.selected_order = selected_order;
    entry.coverage_pct   = coverage_pct;
    entry.pct_inter      = b2.pct_inter;
    entry.top1_share     = res5.by_margin(2).top1_forced_inter_share_pct;
    entry.served         = 100 - b2.coverage_gap_pct;
    entry.n_inter        = b2.n_inter;
    entry.ho_total       = b2.total_handovers;
end
