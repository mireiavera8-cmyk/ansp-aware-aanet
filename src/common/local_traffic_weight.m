function w = local_traffic_weight(candidates, demand_grid, R_inner_km)
% LOCAL_TRAFFIC_WEIGHT  Demand weight within R_inner_km of each candidate.
%   Used to sequence fixed candidate sets (hex lattice, beacon sites).
    n = numel(candidates);
    dem_lat = [demand_grid.lat]'; dem_lon = [demand_grid.lon]';
    dem_weight = [demand_grid.weight]';
    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';
    w = zeros(n,1);
    for i = 1:n
        d = haversine_km(cand_lat(i), cand_lon(i), dem_lat, dem_lon);
        w(i) = sum(dem_weight(d <= R_inner_km));
    end
end
