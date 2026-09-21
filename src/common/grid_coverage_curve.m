function coverage_pct = grid_coverage_curve(candidates, selected_order, grid_points, R_inner_km, R_outer_km, n_max)
% GRID_COVERAGE_CURVE  Demand-weighted soft coverage (%) after each of the
%   first n_max stations in selected_order.
    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';
    grid_lat = [grid_points.lat]'; grid_lon = [grid_points.lon]';
    grid_weight = [grid_points.weight]';
    total_weight = sum(grid_weight);
    coverage_pct = zeros(n_max, 1);
    best_grid = zeros(numel(grid_points), 1);
    for step = 1:n_max
        si = selected_order(step);
        d = haversine_km(cand_lat(si), cand_lon(si), grid_lat, grid_lon);
        p = connection_probability(d, R_inner_km, R_outer_km);
        best_grid = max(best_grid, p);
        coverage_pct(step) = 100 * sum(grid_weight .* best_grid) / total_weight;
    end
end
