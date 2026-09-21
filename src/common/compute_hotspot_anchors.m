function anchors = compute_hotspot_anchors(border_hotspots, ansp_polys)
% COMPUTE_HOTSPOT_ANCHORS  Dual anchors for each border pinch-point: the
%   centroid displaced by its 90th-percentile radius towards each of the two
%   ANSP territories. A station "covers" the pinch-point only if it reaches
%   both anchors, i.e. both sides of the boundary.
    km_per_deg = 111.0;
    n_hs = numel(border_hotspots);
    anchors = struct('lat_a', cell(1,n_hs), 'lon_a', cell(1,n_hs), ...
                     'lat_b', cell(1,n_hs), 'lon_b', cell(1,n_hs));
    for h = 1:n_hs
        hs = border_hotspots(h);
        [cA_lat, cA_lon] = ansp_territory_centroid(hs.ansp_a, ansp_polys);
        [cB_lat, cB_lon] = ansp_territory_centroid(hs.ansp_b, ansp_polys);
        [anchors(h).lat_a, anchors(h).lon_a] = offset_point( ...
            hs.centroid_lat, hs.centroid_lon, cA_lat, cA_lon, hs.km_r90, km_per_deg);
        [anchors(h).lat_b, anchors(h).lon_b] = offset_point( ...
            hs.centroid_lat, hs.centroid_lon, cB_lat, cB_lon, hs.km_r90, km_per_deg);
    end
end


function [lat_c, lon_c] = ansp_territory_centroid(ansp_name, ansp_polys)
    mask = strcmp({ansp_polys.name}, ansp_name) & strcmp({ansp_polys.layer}, 'upper');
    polys = ansp_polys(mask);
    if isempty(polys)
        error('compute_hotspot_anchors: no upper-layer polygon found for ANSP "%s".', ansp_name);
    end
    lat_c = mean(vertcat(polys.lat));
    lon_c = mean(vertcat(polys.lon));
end


function [lat_out, lon_out] = offset_point(lat0, lon0, lat_target, lon_target, offset_km, km_per_deg)
    dlat_km = (lat_target - lat0) * km_per_deg;
    dlon_km = (lon_target - lon0) * km_per_deg * cosd(lat0);
    dist_km = sqrt(dlat_km^2 + dlon_km^2);
    if dist_km < 1e-6
        unit_lat = 1; unit_lon = 0;
    else
        unit_lat = dlat_km / dist_km;
        unit_lon = dlon_km / dist_km;
    end
    lat_out = lat0 + (unit_lat * offset_km) / km_per_deg;
    lon_out = lon0 + (unit_lon * offset_km) / (km_per_deg * cosd(lat0));
end
