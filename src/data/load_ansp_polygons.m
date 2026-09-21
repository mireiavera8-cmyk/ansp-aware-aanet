% LOAD_ANSP_POLYGONS  Load the AIRAC 490 ANSP polygons (upper and lower layers).
%   Parses the two GeoJSON files named in config (ansp_upper_path,
%   ansp_lower_path) into a flat struct array with one entry per exterior
%   ring; MultiPolygon features are expanded into several entries. Shared
%   by M1 (tagging) and the topology modules (boundary overlays).
%   Input  : config (setup_config.m).
%   Output : ansp_polys struct array (name, code, min_fl, max_fl, lon, lat, layer).
function ansp_polys = load_ansp_polygons(config)

    upper = load_geojson_layer(config.ansp_upper_path, 'upper');
    lower = load_geojson_layer(config.ansp_lower_path, 'lower');
    ansp_polys = [upper, lower];

    fprintf('[ANSP] Loaded %d ANSP polygons (%d upper, %d lower)\n', ...
        numel(ansp_polys), numel(upper), numel(lower));
end


function polys = load_geojson_layer(path, layer_name)
    fid = fopen(path, 'r');
    raw = fread(fid, inf, 'char=>char')';
    fclose(fid);
    data = jsondecode(raw);

    n_feat = numel(data.features);
    polys = struct('name',{}, 'code',{}, 'min_fl',{}, 'max_fl',{}, ...
                    'lon',{}, 'lat',{}, 'layer',{});
    n_multi = 0;

    for i = 1:n_feat
        feat = get_feature(data.features, i);
        p = feat.properties;
        rings = get_outer_rings(feat.geometry);

        if numel(rings) > 1, n_multi = n_multi + 1; end

        for r = 1:numel(rings)
            entry.name   = p.name;
            entry.code   = p.code;
            entry.min_fl = p.min_fl;
            entry.max_fl = p.max_fl;
            entry.layer  = layer_name;
            entry.lon    = rings{r}(:,1);
            entry.lat    = rings{r}(:,2);
            polys(end+1) = entry; %#ok<AGROW>
        end
    end

    fprintf('[ANSP] Parsed %s layer: %d features -> %d polygon entries (%d MultiPolygon expanded)\n', ...
        layer_name, n_feat, numel(polys), n_multi);
end


function feat = get_feature(features, i)
    % jsondecode gives a struct array when all geometries share a shape,
    % a cell array when Polygon and MultiPolygon are mixed. Handle both.
    if iscell(features)
        feat = features{i};
    else
        feat = features(i);
    end
end


function rings_out = get_outer_rings(geometry)
    % Exterior ring(s) as a cell array of [n_points x 2] (lon,lat) matrices,
    % one per (sub-)polygon. Interior holes ignored (none at ANSP scale).
    switch geometry.type
        case 'Polygon'
            rings_out = { extract_ring(geometry.coordinates, 1) };
        case 'MultiPolygon'
            sub = geometry.coordinates;
            if ~iscell(sub)
                n_sub = size(sub,1);
                rings_out = cell(1, n_sub);
                for s = 1:n_sub
                    rings_out{s} = squeeze(sub(s,1,:,:));
                end
            else
                n_sub = numel(sub);
                rings_out = cell(1, n_sub);
                for s = 1:n_sub
                    rings_out{s} = extract_ring(sub{s}, 1);
                end
            end
        otherwise
            error('load_ansp_polygons: unexpected geometry type "%s" (expected Polygon/MultiPolygon).', geometry.type);
    end
end


function pts = extract_ring(coords, k)
    % coords is a cell array of rings, or a numeric [n_rings x n_points x 2] array.
    if iscell(coords)
        pts = coords{k};
    else
        pts = squeeze(coords(k,:,:));
    end
end
