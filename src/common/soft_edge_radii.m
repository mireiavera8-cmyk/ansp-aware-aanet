function [R_inner_km, R_outer_km] = soft_edge_radii(R_km, F_db)
% SOFT_EDGE_RADII  Inner/outer coverage radii for nominal cell radius R_km
%   and fade margin F_db, from the free-space 20 dB/decade slope.
    ratio = 10^(F_db/20);
    R_inner_km = R_km / ratio;
    R_outer_km = R_km * ratio;
end
