% M1_DATA_PIPELINE  ADS-B load, filter and ANSP tagging.
%   Stage 1 loads the OpenSky CSV and applies bounding box, altitude floor
%   and sanity ceiling, time window, NaN removal and per-aircraft
%   continuity filters, then sorts by [ID, TIME]. Stage 2 parses the AIRAC
%   490 ANSP GeoJSON layers (load_ansp_polygons.m). Stage 3 tags each point
%   with its ANSP by 2D point-in-polygon, upper layer first then lower as
%   fallback; unresolved points become 'UNKNOWN'.
%   Input  : config (setup_config.m).
%   Outputs: tagged_data (clean data + ANSP index column), ansp_names,
%            COL column map; saved to results/tagged_data.mat.

function [tagged_data, ansp_names, COL] = m1_data_pipeline(config)

    fprintf('[M1] Data pipeline starting...\n');

    % ── COLUMN INDEX MAP ──
    COL.TIME = 1;
    COL.ID   = 2;
    COL.LAT  = 3;
    COL.LON  = 4;
    COL.VEL  = 5;
    COL.HDG  = 6;
    COL.VERT = 7;
    COL.ALT  = 8;
    COL.ANSP = 9;   % added by Stage 3

    clean_data                = stage1_load_and_filter(config, COL);
    ansp_polys                 = load_ansp_polygons(config);
    [tagged_data, ansp_names]  = stage3_tag_ansp(clean_data, COL, ansp_polys);

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'tagged_data.mat'), 'tagged_data', 'ansp_names', 'COL');
    fprintf('[M1] Saved: %s\n', fullfile(config.output_data, 'tagged_data.mat'));
    fprintf('[M1] Data pipeline complete.\n');

end


% ── STAGE 1: LOAD & FILTER ──
function clean_data = stage1_load_and_filter(config, COL)

    fprintf('[M1] Loading: %s\n', config.csv_path);
    raw_data = load_csv(config.csv_path, COL);
    fprintf('[M1] Loaded %d rows, %d aircraft\n', ...
        size(raw_data,1), length(unique(raw_data(:,COL.ID))));

    % Bounding box
    n_before = size(raw_data,1);
    mask = raw_data(:,COL.LAT) >= config.lat_min & raw_data(:,COL.LAT) <= config.lat_max & ...
           raw_data(:,COL.LON) >= config.lon_min & raw_data(:,COL.LON) <= config.lon_max;
    data = raw_data(mask,:);
    fprintf('[M1] Bounding box filter: %d -> %d rows (removed %d)\n', ...
        n_before, size(data,1), n_before - size(data,1));

    % Altitude floor
    n_before = size(data,1);
    data = data(data(:,COL.ALT) > config.alt_min_m, :);
    fprintf('[M1] Altitude filter (>%dm): %d -> %d rows (removed %d)\n', ...
        config.alt_min_m, n_before, size(data,1), n_before - size(data,1));

    % Sanity ceiling: drops corrupted baroaltitude glitches in the raw OpenSky data
    n_before = size(data,1);
    susp_mask = data(:,COL.ALT) > config.alt_max_m;
    n_susp_ac = numel(unique(data(susp_mask, COL.ID)));
    data = data(~susp_mask, :);
    fprintf('[M1] Sanity ceiling (<=%dm / FL%.0f): %d -> %d rows (removed %d, %d aircraft affected)\n', ...
        config.alt_max_m, config.alt_max_m/0.3048/100, ...
        n_before, size(data,1), n_before - size(data,1), n_susp_ac);

    % Time window
    n_before = size(data,1);
    data = data(data(:,COL.TIME) >= config.t_start & data(:,COL.TIME) <= config.t_end, :);
    fprintf('[M1] Time window filter: %d -> %d rows (removed %d)\n', ...
        n_before, size(data,1), n_before - size(data,1));

    % NaN removal
    mask_valid = ~any(isnan(data(:,[COL.LAT,COL.LON,COL.VEL,COL.HDG,COL.ALT])),2);
    n_nan = sum(~mask_valid);
    data = data(mask_valid,:);
    fprintf('[M1] Removed %d NaN rows.\n', n_nan);

    % Per-aircraft continuity
    [ac_ids, ~, ic] = unique(data(:,COL.ID));
    counts = accumarray(ic, 1);
    keep_ids = ac_ids(counts >= config.min_points_per_aircraft);
    n_ac_before = numel(ac_ids);
    data = data(ismember(data(:,COL.ID), keep_ids), :);
    fprintf('[M1] Continuity filter (>=%d points/aircraft): %d -> %d aircraft\n', ...
        config.min_points_per_aircraft, n_ac_before, numel(keep_ids));

    % Sort and reindex
    data = sortrows(data, [COL.ID, COL.TIME]);
    [~,~,data(:,COL.ID)] = unique(data(:,COL.ID));

    clean_data = data;

    n_ac   = length(unique(clean_data(:,COL.ID)));
    t_span = (max(clean_data(:,COL.TIME)) - min(clean_data(:,COL.TIME))) / 60;
    fprintf('[M1] ---- STAGE 1 SUMMARY ----\n');
    fprintf('[M1] State vectors  : %d\n',   size(clean_data,1));
    fprintf('[M1] Aircraft       : %d\n',   n_ac);
    fprintf('[M1] Time span      : %.1f min\n', t_span);
    fprintf('[M1] Alt range      : %.0f - %.0f m\n', min(clean_data(:,COL.ALT)), max(clean_data(:,COL.ALT)));

end


function raw_data = load_csv(csv_path, COL)
    % Typed load of the OpenSky CSV (icao24, callsign, lat, lon, velocity,
    % heading, vertrate, baroaltitude, geoaltitude, onground, time, hour).
    % Drops onground rows; maps icao24 string -> integer ID via unique().

    opts = detectImportOptions(csv_path);
    opts = setvartype(opts, 'icao24', 'string');
    opts = setvartype(opts, 'onground', 'logical');   % CSV stores "true"/"false" as quoted text
    T = readtable(csv_path, opts);

    T = T(~T.onground, :);
    [~, ~, id] = unique(T.icao24);

    n = size(T,1);
    raw_data = nan(n, 8);
    raw_data(:, COL.TIME) = T.time;
    raw_data(:, COL.ID)   = id;
    raw_data(:, COL.LAT)  = T.lat;
    raw_data(:, COL.LON)  = T.lon;
    raw_data(:, COL.VEL)  = T.velocity;
    raw_data(:, COL.HDG)  = T.heading;
    raw_data(:, COL.VERT) = T.vertrate;
    raw_data(:, COL.ALT)  = T.baroaltitude;
end


% ── STAGE 3: ANSP TAGGING (2D footprint only) ──
% The GeoJSON min_fl/max_fl fields come from EUROCONTROL's ACE cost-reporting
% split, not real 3D jurisdiction ceilings, so flight level is not matched.
% config.alt_min_m already guarantees every point is upper airspace.
function [tagged_data, ansp_names] = stage3_tag_ansp(clean_data, COL, ansp_polys)

    n_pts = size(clean_data, 1);
    lat = clean_data(:, COL.LAT);
    lon = clean_data(:, COL.LON);

    ansp_idx = zeros(n_pts, 1);

    % Pass 1: upper layer
    upper_idx = find(strcmp({ansp_polys.layer}, 'upper'));
    n_conflicts_1 = 0;
    for k = upper_idx
        poly = ansp_polys(k);
        bbox_mask = lon >= min(poly.lon) & lon <= max(poly.lon) & ...
                    lat >= min(poly.lat) & lat <= max(poly.lat);
        if ~any(bbox_mask), continue; end
        in_poly = false(n_pts, 1);
        in_poly(bbox_mask) = inpolygon(lon(bbox_mask), lat(bbox_mask), poly.lon, poly.lat);
        n_conflicts_1 = n_conflicts_1 + sum(in_poly & ansp_idx > 0);
        ansp_idx(in_poly & ansp_idx == 0) = k;
    end
    n_pass1 = sum(ansp_idx > 0);
    fprintf('[M1] Pass 1 (upper-layer footprint): %d / %d points assigned (%.2f%%)\n', ...
        n_pass1, n_pts, 100*n_pass1/n_pts);
    if n_conflicts_1 > 0
        fprintf('[M1] WARNING: %d points matched >1 upper polygon (kept first match)\n', n_conflicts_1);
    end

    % Pass 2: lower layer fallback
    lower_idx = find(strcmp({ansp_polys.layer}, 'lower'));
    remaining = ansp_idx == 0;
    n_conflicts_2 = 0;
    if any(remaining)
        for k = lower_idx
            poly = ansp_polys(k);
            bbox_mask = remaining & lon >= min(poly.lon) & lon <= max(poly.lon) & ...
                        lat >= min(poly.lat) & lat <= max(poly.lat);
            if ~any(bbox_mask), continue; end
            in_poly = false(n_pts, 1);
            in_poly(bbox_mask) = inpolygon(lon(bbox_mask), lat(bbox_mask), poly.lon, poly.lat);
            n_conflicts_2 = n_conflicts_2 + sum(in_poly & ansp_idx > 0 & remaining);
            ansp_idx(in_poly & remaining) = k;
        end
    end
    n_pass2 = sum(ansp_idx > 0) - n_pass1;
    fprintf('[M1] Pass 2 (lower-layer fallback): %d additional points assigned (%.2f%%)\n', ...
        n_pass2, 100*n_pass2/n_pts);
    if n_conflicts_2 > 0
        fprintf('[M1] WARNING: %d points matched >1 lower polygon (kept first match)\n', n_conflicts_2);
    end

    unresolved = ansp_idx == 0;
    fprintf('[M1] Unresolved (outside every known ANSP footprint): %d / %d (%.2f%%)\n', ...
        sum(unresolved), n_pts, 100*sum(unresolved)/n_pts);

    % Build name lookup and output column
    all_names = [{ansp_polys.name}, {'UNKNOWN'}];
    [ansp_names, ~, name_map] = unique(all_names, 'stable');
    unknown_code = name_map(end);

    ansp_col = zeros(n_pts, 1);
    ansp_col(~unresolved) = name_map(ansp_idx(~unresolved));
    ansp_col(unresolved)  = unknown_code;

    tagged_data = [clean_data, ansp_col];

    fprintf('[M1] ---- ANSP DISTRIBUTION ----\n');
    for k = 1:numel(ansp_names)
        cnt = sum(ansp_col == k);
        if cnt > 0
            fprintf('[M1]   %-25s : %d points (%.2f%%)\n', ansp_names{k}, cnt, 100*cnt/n_pts);
        end
    end

end