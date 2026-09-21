function p = connection_probability(d, R_inner_km, R_outer_km)
% CONNECTION_PROBABILITY  Soft-edge coverage: 1 inside R_inner, 0 beyond
%   R_outer, linear in between (see soft_edge_radii).
    p = zeros(size(d));
    p(d <= R_inner_km) = 1;
    mid = d > R_inner_km & d < R_outer_km;
    p(mid) = (R_outer_km - d(mid)) / (R_outer_km - R_inner_km);
end
