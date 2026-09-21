function difficulty_norm = load_difficulty(candidates, terrain_path, dme_beacons, dme_cost_weight)
% LOAD_DIFFICULTY  Siting difficulty in [0,1] per candidate: elevation (km)
%   + local ruggedness (std, per 100 m) + DME/VOR proximity (1/d aggregate,
%   normalised, weighted by dme_cost_weight). Requires an exact terrain match.
    T = readtable(terrain_path);
    key = @(lat,lon) sprintf('%.6f_%.6f', round(lat,6), round(lon,6));
    lut = containers.Map();
    for i = 1:height(T)
        lut(key(T.lat(i), T.lon(i))) = [T.elevation_m(i), T.ruggedness_std_m(i)];
    end
    n = numel(candidates);
    elevation_m = zeros(n,1); ruggedness_m = zeros(n,1);
    for i = 1:n
        k = key(candidates(i).lat, candidates(i).lon);
        if ~isKey(lut, k)
            error('load_difficulty: no terrain data for candidate (%.4f, %.4f); re-fetch terrain for the current grid.', ...
                candidates(i).lat, candidates(i).lon);
        end
        v = lut(k);
        elevation_m(i) = v(1); ruggedness_m(i) = v(2);
    end

    km_per_deg = 111.0;
    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';
    dme_raw = zeros(n,1);
    for b = 1:size(dme_beacons,1)
        d_km = sqrt(((cand_lat-dme_beacons(b,1))*km_per_deg).^2 + ...
                    ((cand_lon-dme_beacons(b,2))*km_per_deg.*cosd(cand_lat)).^2);
        d_km = max(d_km, 20);
        dme_raw = dme_raw + 1./d_km;
    end
    dme_norm = dme_raw / max(dme_raw);
    difficulty_raw = max(elevation_m,0)/1000 + ruggedness_m/100 + dme_cost_weight * dme_norm;
    difficulty_norm = difficulty_raw / max(difficulty_raw);
end
