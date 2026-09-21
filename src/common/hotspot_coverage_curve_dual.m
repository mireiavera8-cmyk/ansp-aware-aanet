function hotspot_cov = hotspot_coverage_curve_dual(candidates, selected_order, ...
    anchors, hotspot_weight, R_inner_km, R_outer_km, n_max)
% HOTSPOT_COVERAGE_CURVE_DUAL  Weighted pinch-point coverage (%) of a fixed
%   station order under the dual-anchor metric: a station's contribution to
%   a pinch-point is min(P_A, P_B); the achieved value is the max over the
%   stations selected so far.
    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';
    total_weight = sum(hotspot_weight);
    n_hs = numel(anchors);
    hotspot_cov = zeros(n_max, 1);
    best_hs = zeros(n_hs, 1);
    for step = 1:n_max
        si = selected_order(step);
        dA = haversine_km(cand_lat(si), cand_lon(si), [anchors.lat_a]', [anchors.lon_a]');
        dB = haversine_km(cand_lat(si), cand_lon(si), [anchors.lat_b]', [anchors.lon_b]');
        pA = connection_probability(dA, R_inner_km, R_outer_km);
        pB = connection_probability(dB, R_inner_km, R_outer_km);
        best_hs = max(best_hs, min(pA, pB));
        hotspot_cov(step) = 100 * sum(hotspot_weight .* best_hs) / total_weight;
    end
end
