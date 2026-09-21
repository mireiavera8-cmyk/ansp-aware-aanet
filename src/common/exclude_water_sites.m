function candidates = exclude_water_sites(candidates, terrain_path)
% EXCLUDE_WATER_SITES  Drop candidates whose exact-match terrain sample reads
%   0 m (Copernicus GLO-90 water fill). Errors if a candidate has no sample,
%   which means the elevation file must be re-fetched for the current grid.
    T = readtable(terrain_path);
    key = @(lat,lon) sprintf('%.6f_%.6f', round(lat,6), round(lon,6));
    lut = containers.Map();
    for i = 1:height(T)
        lut(key(T.lat(i), T.lon(i))) = T.elevation_m(i);
    end
    n = numel(candidates);
    is_water = false(n,1);
    for i = 1:n
        k = key(candidates(i).lat, candidates(i).lon);
        if ~isKey(lut, k)
            error('exclude_water_sites: no terrain data for candidate (%.4f, %.4f); re-fetch terrain for the current grid.', ...
                candidates(i).lat, candidates(i).lon);
        end
        is_water(i) = lut(k) == 0;
    end
    candidates = candidates(~is_water);
end
