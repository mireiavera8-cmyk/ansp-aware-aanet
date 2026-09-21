function grid_points = build_hex_grid(config)
% BUILD_HEX_GRID  Regular hexagonal lattice of circumradius gs_radius_km
%   over the corridor box (dx = R*sqrt(3), dy = 1.5*R, alternating rows
%   offset by dx/2). One mid-corridor latitude sets the lon scaling so the
%   tessellation stays regular. Weights are 0 (geometry-only baseline).
    R_km = config.gs_radius_km;
    km_per_deg = 111.0;
    lat_mid = (config.lat_min + config.lat_max) / 2;

    dx_km = R_km * sqrt(3);
    dy_km = R_km * 1.5;
    dlat = dy_km / km_per_deg;
    dlon = dx_km / km_per_deg / cosd(lat_mid);
    margin_lat = R_km / km_per_deg;
    margin_lon = R_km / km_per_deg / cosd(lat_mid);

    lat_vals = (config.lat_min - margin_lat) : dlat : (config.lat_max + margin_lat);
    grid_points = struct('lat', {}, 'lon', {}, 'weight', {});
    for r = 1:numel(lat_vals)
        row_lat = lat_vals(r);
        offset = mod(r,2) * (dlon/2);
        lon_vals = (config.lon_min - margin_lon - offset) : dlon : (config.lon_max + margin_lon);
        for c = 1:numel(lon_vals)
            entry.lat = row_lat; entry.lon = lon_vals(c); entry.weight = 0;
            grid_points(end+1) = entry; %#ok<AGROW>
        end
    end
end
