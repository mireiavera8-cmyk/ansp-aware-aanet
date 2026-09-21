% PREPARE_WEB_DATA  Build web_visualizer/data/viz_data.js for the Leaflet visualizer.
%
% Reads the M1/M2/M2b outputs in results/ (tagged_data, border_crossings,
% border_hotspots), the four headline N=12 topologies, the terrain CSV and
% the DME beacon list, and writes one script-loadable file
% (window.VIZ_DATA = {...}; window.ANSP_GEOJSON = {...};) so index.html
% opens by double-click with no local server or fetch/CORS step.
% Tracks are downsampled to one point per SAMPLE_SEC, keeping every point
% where the raw ANSP tag changes, so drawn paths show M1's tagging exactly
% while M2's hysteresis-confirmed crossings are exported as separate markers.
% Run from anywhere: run('web_visualizer/prepare_web_data.m') after main.m.

SAMPLE_SEC = 10;     % keep >=1 point per this many seconds during stable ANSP
COORD_DP   = 4;      % round lat/lon to this many decimals (~11 m)

this_dir  = fileparts(mfilename('fullpath'));
proj_root = fileparts(this_dir);
addpath(proj_root); init_paths();

fprintf('[VIZ] Project root: %s\n', proj_root);

config = setup_config();

tagged_path = fullfile(proj_root, 'results', 'tagged_data.mat');
border_path = fullfile(proj_root, 'results', 'border_crossings.mat');
if ~isfile(tagged_path)
    error('[VIZ] %s not found. Run main.m first.', tagged_path);
end
if ~isfile(border_path)
    error('[VIZ] %s not found. Run main.m first.', border_path);
end

fprintf('[VIZ] Loading %s ...\n', tagged_path);
S = load(tagged_path);              % tagged_data, ansp_names, COL
tagged_data = S.tagged_data;
ansp_names  = S.ansp_names;
COL         = S.COL;

fprintf('[VIZ] Loading %s ...\n', border_path);
B = load(border_path);              % border_stats
border_stats = B.border_stats;

hotspots_path = fullfile(proj_root, 'results', 'border_hotspots.mat');
if ~isfile(hotspots_path)
    error('[VIZ] %s not found. Run main.m first.', hotspots_path);
end
fprintf('[VIZ] Loading %s ...\n', hotspots_path);
H = load(hotspots_path);            % border_hotspots
border_hotspots = H.border_hotspots;

n_ansp = numel(ansp_names);
fprintf('[VIZ] %d state vectors, %d aircraft, %d ANSPs\n', ...
    size(tagged_data,1), numel(unique(tagged_data(:,COL.ID))), n_ansp);

% ANSP colours: 8 validated categorical slots assigned by traffic rank. ANSPs with
% no points in this dataset share one neutral tone so rare real ANSPs never collide with them.
PALETTE_8 = {'#2a78d6','#eb6834','#1baf7a','#eda100','#e87ba4','#008300','#4a3aa7','#e34948'};
PALETTE_EXTRA = {'#8c6d1f','#616161','#a15a2a'};
NEUTRAL_UNUSED = '#c3c2b7';   % neutral tone for ANSPs with no traffic

counts = accumarray(tagged_data(:,COL.ANSP), 1, [n_ansp, 1]);
[~, order] = sort(counts, 'descend');   % order(1) = most-prevalent ANSP index
n_active = sum(counts > 0);
fprintf('[VIZ] %d / %d ANSPs have traffic in this corridor/hour; the rest share a neutral tone\n', ...
    n_active, n_ansp);

ansp_colors = cell(n_ansp, 1);
for k = 1:n_ansp
    idx = order(k);
    if counts(idx) == 0
        ansp_colors{idx} = NEUTRAL_UNUSED;
    elseif k <= numel(PALETTE_8)
        ansp_colors{idx} = PALETTE_8{k};
    else
        e = k - numel(PALETTE_8);
        ansp_colors{idx} = PALETTE_EXTRA{mod(e-1, numel(PALETTE_EXTRA)) + 1};
    end
end

D.ansp = struct('name', {}, 'color', {}, 'points', {});
for k = 1:n_ansp
    D.ansp(k) = struct('name', ansp_names{k}, 'color', ansp_colors{k}, 'points', counts(k));
end

% Upper-layer polygons only (the lower layer never tagged a point here), passed through
% as raw GeoJSON text: a jsondecode/jsonencode round-trip can malform Polygon vs MultiPolygon rings.
upper_path = config.ansp_upper_path;
ansp_geojson_raw = fileread(upper_path);
n_geo_features = numel(jsondecode(ansp_geojson_raw).features);
fprintf('[VIZ] Loaded ANSP boundary GeoJSON: %d features (passed through raw)\n', n_geo_features);

id_col      = tagged_data(:, COL.ID);
block_start = [1; find(diff(id_col) ~= 0) + 1];
block_end   = [block_start(2:end) - 1; numel(id_col)];
ac_ids      = id_col(block_start);
n_ac        = numel(ac_ids);

crossings_by_id = zeros(max(ac_ids), 1);
crossings_by_id(border_stats.aircraft_ids) = border_stats.crossings_per_aircraft;

tracks = struct('id', {}, 'lat', {}, 'lon', {}, 'ansp', {}, 'n_crossings', {});
n_pts_kept = 0;
for a = 1:n_ac
    rows = block_start(a):block_end(a);
    t    = tagged_data(rows, COL.TIME);
    lat  = tagged_data(rows, COL.LAT);
    lon  = tagged_data(rows, COL.LON);
    ansp = tagged_data(rows, COL.ANSP);

    n = numel(t);
    keep = false(n,1);
    keep(1) = true;
    last_t = t(1); last_ansp = ansp(1);
    for r = 2:n
        if ansp(r) ~= last_ansp || (t(r) - last_t) >= SAMPLE_SEC
            keep(r) = true;
            last_t = t(r); last_ansp = ansp(r);
        end
    end
    keep(end) = true;

    if sum(keep) < 2, continue; end   % skip single-point tracks

    tracks(end+1) = struct( ...                                  %#ok<SAGROW>
        'id',          ac_ids(a), ...
        'lat',         round(lat(keep), COORD_DP)', ...
        'lon',         round(lon(keep), COORD_DP)', ...
        'ansp',        ansp(keep)', ...
        'n_crossings', crossings_by_id(ac_ids(a)));
    n_pts_kept = n_pts_kept + sum(keep);
end
fprintf('[VIZ] Built %d tracks, %d sampled points (>=%ds spacing, exact on ANSP change)\n', ...
    numel(tracks), n_pts_kept, SAMPLE_SEC);
D.tracks = tracks;

% M2 hysteresis-confirmed crossing events (distinct from the raw tag changes in tracks).
D.crossings = border_stats.crossing_events;
for k = 1:numel(D.crossings)
    D.crossings(k).lat = round(D.crossings(k).lat, COORD_DP);
    D.crossings(k).lon = round(D.crossings(k).lon, COORD_DP);
end

pair_counts = border_stats.pair_counts;
[sorted_vals, sorted_idx] = sort(pair_counts(:), 'descend');
top_pairs = struct('a', {}, 'b', {}, 'count', {});
for k = 1:numel(sorted_idx)
    if sorted_vals(k) == 0, break; end
    [i, j] = ind2sub(size(pair_counts), sorted_idx(k));
    if i >= j, continue; end
    top_pairs(end+1) = struct('a', i, 'b', j, 'count', pair_counts(i,j)); %#ok<SAGROW>
    if numel(top_pairs) >= 15, break; end
end
D.top_pairs = top_pairs;

D.summary = struct( ...
    'n_aircraft',            border_stats.n_aircraft, ...
    'n_aircraft_crossing',   border_stats.n_aircraft_crossing, ...
    'pct_aircraft_crossing', round(border_stats.pct_aircraft_crossing, 1), ...
    'total_crossings',       border_stats.total_crossings, ...
    'n_raw_transitions',     border_stats.n_raw_transitions, ...
    'hysteresis_n',          border_stats.hysteresis_n);

D.meta = struct( ...
    'n_vectors',  size(tagged_data,1), ...
    'n_aircraft', n_ac, ...
    'span_min',   (max(tagged_data(:,COL.TIME)) - min(tagged_data(:,COL.TIME))) / 60, ...
    'sample_sec', SAMPLE_SEC);

% Core box = station placement zone and analysis scope; field name kept for the frontend's fitBounds.
D.corridor_box = struct('lat_min', config.lat_min, 'lat_max', config.lat_max, ...
                        'lon_min', config.lon_min, 'lon_max', config.lon_max);

% Extended box = OpenSky query extent (core box plus an ext_margin_km ring); acquisition only.
D.data_box = struct('lat_min', config.data_lat_min, 'lat_max', config.data_lat_max, ...
                    'lon_min', config.data_lon_min, 'lon_max', config.data_lon_max);

% Headline four topologies at the same N=12 and F=5.5dB band (main.m Comparison B),
% so the layer compares strategies at matched station count, not each one's best N.
fprintf('[VIZ] Building ground-station topology layers...\n');
N_VIZ = 12;

topo_defs = struct( ...
    'key',        {'naive', 'aware', 'hex', 'optimized'}, ...
    'label',      {'Naive (coverage-greedy)', 'ANSP-aware', 'Hex (literature grid)', 'Optimized (p-robust)'}, ...
    'study_file', {'results/topology_study.mat', 'results/topology_study_ansp_aware.mat', ...
                   'results/topology_study_literature_grid.mat', ''}, ...
    'm4_file',    {'results/m4_naive_N12.mat', 'results/m4_aware_N12.mat', ...
                   'results/m4_hex_N12.mat', 'results/m4_optimized_N12.mat'});

% The soft-edge radii depend only on the fade-margin config, so naive's conservative
% values are reused for Optimized, whose saved search pool does not store them.
S_naive_study = load(fullfile(proj_root, topo_defs(1).study_file), 'results');
shared_R_inner_km = S_naive_study.results.conservative.R_inner_km;
shared_R_outer_km = S_naive_study.results.conservative.R_outer_km;

D.topologies = struct('key', {}, 'label', {}, 'n_stations', {}, 'pct_inter', {}, ...
    'R_inner_km', {}, 'R_outer_km', {}, 'stations', {});

for t = 1:numel(topo_defs)
    def = topo_defs(t);
    if strcmp(def.key, 'optimized')
        S_opt  = load(fullfile(proj_root, 'results', 'm3_optimal_search.mat'), 'pool', 'results_by_p');
        winner = S_opt.pool(S_opt.results_by_p(1).winner_idx);
        candidates     = winner.candidates;
        selected_order = winner.selected_order;
    else
        S_study        = load(fullfile(proj_root, def.study_file), 'results');
        candidates     = S_study.results.conservative.candidates;
        selected_order = S_study.results.conservative.selected_order;
    end

    n_sel   = min(N_VIZ, numel(selected_order));
    sel_idx = selected_order(1:n_sel);

    stations = struct('lat', {}, 'lon', {}, 'ansp_name', {});
    for s = 1:n_sel
        ci = sel_idx(s);
        stations(s) = struct('lat', candidates(ci).lat, 'lon', candidates(ci).lon, ...
            'ansp_name', candidates(ci).ansp_name);
    end

    S_m4  = load(fullfile(proj_root, def.m4_file));
    fn_m4 = fieldnames(S_m4);
    m4r   = S_m4.(fn_m4{1});

    D.topologies(t) = struct('key', def.key, 'label', def.label, ...
        'n_stations', n_sel, 'pct_inter', round(m4r.by_margin(2).pct_inter, 1), ...
        'R_inner_km', shared_R_inner_km, 'R_outer_km', shared_R_outer_km, ...
        'stations', stations);
end
fprintf('[VIZ] Built %d topology layers (N=%d each)\n', numel(D.topologies), N_VIZ);

% Dataset geometry: everything the frontend needs to explain the two boxes,
% computed from config so no study parameter is hardcoded in JS. The four
% edge stations are hypothetical worst cases (midpoint of each core edge);
% their reach is why the extended box is one coverage radius wider.
% Radio horizon uses the 4/3-earth expression of m7_radio_horizon_effect.m.
radio_horizon_km = @(h1_m, h2_m) 3.57 * (sqrt((4/3)*max(h1_m,0)) + sqrt((4/3)*max(h2_m,0)));

KM_PER_DEG_LAT = 111.32;
km_per_deg_lon = @(lat) KM_PER_DEG_LAT * cosd(lat);
mid_lat = (config.lat_min + config.lat_max) / 2;
mid_lon = (config.lon_min + config.lon_max) / 2;

% Waypoint names follow the row order of config.corridor_positions.
corridor_names = {'London', 'Frankfurt', 'Vienna'};
D.corridor_line = struct('name', {}, 'lat', {}, 'lon', {}, 'margin_km', {});
for i = 1:size(config.corridor_positions, 1)
    wlat = config.corridor_positions(i,1);
    wlon = config.corridor_positions(i,2);
    margin_km = min([ ...
        (wlat - config.lat_min) * KM_PER_DEG_LAT, ...
        (config.lat_max - wlat) * KM_PER_DEG_LAT, ...
        (wlon - config.lon_min) * km_per_deg_lon(wlat), ...
        (config.lon_max - wlon) * km_per_deg_lon(wlat)]);
    D.corridor_line(i) = struct('name', corridor_names{i}, ...
        'lat', wlat, 'lon', wlon, 'margin_km', round(margin_km, 1));
end

edge_defs = { 'North edge', config.lat_max, mid_lon; ...
              'South edge', config.lat_min, mid_lon; ...
              'East edge',  mid_lat,        config.lon_max; ...
              'West edge',  mid_lat,        config.lon_min };
D.edge_gs = struct('name', {}, 'lat', {}, 'lon', {});
for e = 1:size(edge_defs, 1)
    D.edge_gs(e) = struct('name', edge_defs{e,1}, ...
        'lat', edge_defs{e,2}, 'lon', edge_defs{e,3});
end

D.geometry = struct( ...
    'gs_radius_km',     config.gs_radius_km, ...
    'R_inner_km',       round(shared_R_inner_km, 1), ...
    'R_outer_km',       round(shared_R_outer_km, 1), ...
    'fade_margin_db',   config.fade_margin_db_hi, ...
    'gs_mast_height_m', config.gs_mast_height_m, ...
    'alt_min_m',        config.alt_min_m, ...
    'alt_max_m',        config.alt_max_m, ...
    'horizon_floor_km', round(radio_horizon_km(config.gs_mast_height_m, config.alt_min_m)), ...
    'horizon_ceil_km',  round(radio_horizon_km(config.gs_mast_height_m, config.alt_max_m)), ...
    'ext_margin_km',    config.ext_margin_km, ...
    'core_width_km',    round((config.lon_max - config.lon_min) * km_per_deg_lon(mid_lat)), ...
    'core_height_km',   round((config.lat_max - config.lat_min) * KM_PER_DEG_LAT), ...
    'data_width_km',    round((config.data_lon_max - config.data_lon_min) * km_per_deg_lon(mid_lat)), ...
    'data_height_km',   round((config.data_lat_max - config.data_lat_min) * KM_PER_DEG_LAT));

fprintf(['[VIZ] Geometry: core %d x %d km, extended %d x %d km (+%d km ring), ' ...
         'R_outer %.0f km, horizon %d-%d km\n'], ...
    D.geometry.core_width_km, D.geometry.core_height_km, ...
    D.geometry.data_width_km, D.geometry.data_height_km, D.geometry.ext_margin_km, ...
    D.geometry.R_outer_km, D.geometry.horizon_floor_km, D.geometry.horizon_ceil_km);

% Copernicus DEM terrain at every candidate site. elevation_m==0 is the DEM's water fill;
% those sites were excluded from placement and are flagged is_water for a separate layer.
terrain_tbl = readtable(config.terrain_data_path);
D.terrain = struct('lat', {}, 'lon', {}, 'elevation_m', {}, 'ruggedness_std_m', {}, 'is_water', {});
for i = 1:height(terrain_tbl)
    D.terrain(i) = struct( ...
        'lat', terrain_tbl.lat(i), 'lon', terrain_tbl.lon(i), ...
        'elevation_m', terrain_tbl.elevation_m(i), ...
        'ruggedness_std_m', terrain_tbl.ruggedness_std_m(i), ...
        'is_water', terrain_tbl.elevation_m(i) == 0);
end
fprintf('[VIZ] Loaded %d terrain sample points (%d flagged as water-excluded)\n', ...
    numel(D.terrain), sum([D.terrain.is_water]));

% DME/VOR beacons, the same list used for siting cost and the M2c correlation.
D.dme_beacons = struct('name', {}, 'lat', {}, 'lon', {});
for i = 1:size(config.dme_beacons, 1)
    D.dme_beacons(i) = struct('name', config.dme_beacon_names{i}, ...
        'lat', config.dme_beacons(i,1), 'lon', config.dme_beacons(i,2));
end

% M2b border hotspots: the crossing-pair centroids that drive ANSP-aware placement.
D.hotspots = struct('lat', {}, 'lon', {}, 'count', {}, 'ansp_a', {}, 'ansp_b', {}, 'km_r90', {});
for i = 1:numel(border_hotspots)
    h = border_hotspots(i);
    D.hotspots(i) = struct('lat', h.centroid_lat, 'lon', h.centroid_lon, ...
        'count', h.count, 'ansp_a', h.ansp_a, 'ansp_b', h.ansp_b, ...
        'km_r90', h.km_r90);
end
fprintf('[VIZ] Loaded %d DME beacons, %d border hotspots\n', numel(D.dme_beacons), numel(D.hotspots));

out_dir = fullfile(this_dir, 'data');
if ~isfolder(out_dir), mkdir(out_dir); end
out_js  = fullfile(out_dir, 'viz_data.js');

json = jsonencode(D);
fid  = fopen(out_js, 'w', 'n', 'UTF-8');
fprintf(fid, 'window.VIZ_DATA = %s;\n', json);
% Original GeoJSON text, not a re-encoded struct (see the polygon note above).
fprintf(fid, 'window.ANSP_GEOJSON = %s;\n', ansp_geojson_raw);
fclose(fid);

kb = dir(out_js);
fprintf('[VIZ] Wrote %s (%.2f MB)\n', out_js, kb.bytes/1e6);
fprintf('[VIZ] Open web_visualizer/index.html in a browser.\n');
