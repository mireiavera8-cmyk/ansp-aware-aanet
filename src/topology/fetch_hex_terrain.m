% FETCH_HEX_TERRAIN  Fetch elevation and ruggedness for off-grid candidate sites.
%
% Script. The hex lattice (M3c/M3h) and DME/VOR beacon sites (M3g) do not lie
% on the M3 adaptive grid that data/terrain_elevation.csv is keyed to, and a
% continuous ruggedness score cannot be interpolated over tens of km, so their
% terrain is fetched directly. Source: Copernicus DEM 2021 GLO-90 via the
% Open-Meteo elevation API (same as the existing file). Ruggedness = std of
% elevation over the site and its four neighbours at +-0.05 deg (~5.5 km).
% Results are written back BY INDEX into preallocated slots and short replies
% are rejected, so a rate-limited batch can never misalign elevations against
% coordinates; failed batches are retried with backoff.
%
% OUTPUT : config.terrain_data_hex_path (data/terrain_elevation_hex.csv),
%          columns lat, lon, elevation_m, ruggedness_std_m, ruggedness_range_m.

clear; clc;
config = setup_config();
ansp_polys = load_ansp_polygons(config);

%% -- 1. Sites needing elevation: hex lattice (ANSP-filtered as in M3c/M3h) + beacons --
grid_points = build_hex_grid(config);
hex_cands   = filter_valid_candidates(grid_points, ansp_polys);
hex_lat = [hex_cands.lat]';  hex_lon = [hex_cands.lon]';
fprintf('[FETCH] Hex-lattice candidates inside ANSP territory: %d\n', numel(hex_lat));

in_bbox = config.dme_beacons(:,1) >= config.lat_min & config.dme_beacons(:,1) <= config.lat_max & ...
          config.dme_beacons(:,2) >= config.lon_min & config.dme_beacons(:,2) <= config.lon_max;
bcn_lat = config.dme_beacons(in_bbox, 1);
bcn_lon = config.dme_beacons(in_bbox, 2);
fprintf('[FETCH] DME/VOR beacon sites inside the corridor: %d\n', numel(bcn_lat));

site_lat = [hex_lat; bcn_lat];
site_lon = [hex_lon; bcn_lon];
n_sites  = numel(site_lat);

%% -- 2. Expand to the 5-point ruggedness stencil --
d = 0.05;                                  % ~5.5 km
off = [0 0; +d 0; -d 0; 0 +d; 0 -d];       % centre, N, S, E, W
n_pts = n_sites * 5;
q_lat = zeros(n_pts,1); q_lon = zeros(n_pts,1);
for s = 1:n_sites
    for k = 1:5
        i = (s-1)*5 + k;
        q_lat(i) = site_lat(s) + off(k,1);
        q_lon(i) = site_lon(s) + off(k,2);
    end
end
fprintf('[FETCH] %d sites x 5 stencil points = %d elevation queries\n', n_sites, n_pts);

%% -- 3. Fetch, index-addressed --
elev = nan(n_pts, 1);                      % NaN until a slot is really filled
BATCH = 90;                                % Open-Meteo accepts up to 100/request
MAX_TRIES = 6;
opts = weboptions('Timeout', 45, 'ContentType', 'json');

starts = 1:BATCH:n_pts;
for b = 1:numel(starts)
    i0 = starts(b);
    i1 = min(i0 + BATCH - 1, n_pts);
    idx = i0:i1;                           % the slots this batch owns

    lat_str = strjoin(compose('%.6f', q_lat(idx))', ',');
    lon_str = strjoin(compose('%.6f', q_lon(idx))', ',');
    url = sprintf('https://api.open-meteo.com/v1/elevation?latitude=%s&longitude=%s', lat_str, lon_str);

    ok = false;
    for attempt = 1:MAX_TRIES
        try
            resp = webread(url, opts);
            e = resp.elevation(:);
            % A short or long reply cannot be aligned to the slots: refuse it.
            if numel(e) ~= numel(idx)
                error('length mismatch: asked %d, got %d', numel(idx), numel(e));
            end
            elev(idx) = e;                 % write BY INDEX, never appended
            ok = true;
            break;
        catch ME
            wait_s = 2^attempt;
            fprintf('[FETCH]   batch %d/%d attempt %d failed (%s) — retrying in %ds\n', ...
                b, numel(starts), attempt, ME.message, wait_s);
            pause(wait_s);
        end
    end
    if ~ok
        error(['fetch_hex_terrain: batch %d (slots %d-%d) failed after %d attempts. ' ...
               'Nothing was written for it; re-run when the API is reachable.'], ...
               b, i0, i1, MAX_TRIES);
    end
    fprintf('[FETCH] batch %d/%d ok (slots %d-%d)\n', b, numel(starts), i0, i1);
    pause(0.4);                            % be polite to a free API
end

if any(isnan(elev))
    error('fetch_hex_terrain: %d slots still unfilled — refusing to write a partial file.', sum(isnan(elev)));
end

%% -- 4. Reduce the stencil to elevation + ruggedness --
elevation_m       = zeros(n_sites,1);
ruggedness_std_m  = zeros(n_sites,1);
ruggedness_range_m= zeros(n_sites,1);
for s = 1:n_sites
    v = elev((s-1)*5 + (1:5));
    elevation_m(s)        = v(1);          % the site itself, not the mean
    ruggedness_std_m(s)   = std(v);
    ruggedness_range_m(s) = max(v) - min(v);
end

lat = site_lat; lon = site_lon;
T = table(lat, lon, elevation_m, ruggedness_std_m, ruggedness_range_m);
writetable(T, config.terrain_data_hex_path);

fprintf('\n[FETCH] Wrote %d rows to %s\n', height(T), config.terrain_data_hex_path);
fprintf('[FETCH] elevation  : min %.0f  median %.0f  max %.0f m\n', ...
    min(elevation_m), median(elevation_m), max(elevation_m));
fprintf('[FETCH] ruggedness : min %.1f  median %.1f  max %.1f m\n', ...
    min(ruggedness_std_m), median(ruggedness_std_m), max(ruggedness_std_m));
fprintf('[FETCH] sea-level sites (elevation == 0, water fill): %d\n', sum(elevation_m == 0));
