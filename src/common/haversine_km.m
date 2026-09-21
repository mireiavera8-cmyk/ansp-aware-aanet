function d = haversine_km(lat1, lon1, lat2, lon2)
% HAVERSINE_KM  Great-circle distance in km between (lat1,lon1) and (lat2,lon2).
%   Inputs in degrees; either side may be a vector.
    R = 6371;
    phi1 = deg2rad(lat1); phi2 = deg2rad(lat2);
    dphi = deg2rad(lat2 - lat1);
    dlambda = deg2rad(lon2 - lon1);
    a = sin(dphi/2).^2 + cos(phi1).*cos(phi2).*sin(dlambda/2).^2;
    d = 2 * R * asin(sqrt(a));
end
