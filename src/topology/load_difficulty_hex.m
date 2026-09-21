% LOAD_DIFFICULTY_HEX  Siting difficulty in [0,1] for off-grid candidate pools.
%
% Same formula as the M3 load_difficulty, by exact lookup in
% data/terrain_elevation_hex.csv (fetch_hex_terrain.m; a missing row is an error):
%   difficulty_raw  = max(elevation_m,0)/1000 + ruggedness_std_m/100
%                     + dme_cost_weight * dme_score_norm,  normalised to [0,1].
% 1000 m of elevation and 100 m of ruggedness each count one unit, so a steep
% site is penalised ~10x more per metre than a merely high one. Not literature-
% calibrated (no LDACS siting-cost dataset exists); flagged for sensitivity.
%
% INPUT  : candidates (.lat, .lon), terrain_path, dme_beacons, dme_cost_weight,
%          include_dme (false for M3g: every site IS a beacon)
% OUTPUT : difficulty_norm [0,1]; parts .elevation_m .ruggedness_std_m
%          .dme_score_norm .difficulty_raw

function [difficulty_norm, parts] = load_difficulty_hex(candidates, terrain_path, ...
    dme_beacons, dme_cost_weight, include_dme)

    if nargin < 5 || isempty(include_dme), include_dme = true; end

    T = readtable(terrain_path);
    key = @(lat,lon) sprintf('%.6f_%.6f', round(lat,6), round(lon,6));

    lut = containers.Map();
    for i = 1:height(T)
        lut(key(T.lat(i), T.lon(i))) = [T.elevation_m(i), T.ruggedness_std_m(i)];
    end

    n = numel(candidates);
    elevation_m  = zeros(n,1);
    ruggedness_m = zeros(n,1);
    for i = 1:n
        k = key(candidates(i).lat, candidates(i).lon);
        if ~isKey(lut, k)
            error(['load_difficulty_hex: no terrain row for candidate (%.4f, %.4f). ' ...
                   'The hex lattice or beacon list has changed — re-run fetch_hex_terrain.m.'], ...
                   candidates(i).lat, candidates(i).lon);
        end
        v = lut(k);
        elevation_m(i)  = v(1);
        ruggedness_m(i) = v(2);
    end

    % DME proximity: sum of 1/d over beacons, with a 20 km floor so the term
    % does not diverge on top of a beacon (same model as m2c).
    km_per_deg = 111.0;
    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';
    dme_raw = zeros(n,1);
    if include_dme
        for b = 1:size(dme_beacons,1)
            d_km = sqrt(((cand_lat-dme_beacons(b,1))*km_per_deg).^2 + ...
                        ((cand_lon-dme_beacons(b,2))*km_per_deg.*cosd(cand_lat)).^2);
            d_km = max(d_km, 20);
            dme_raw = dme_raw + 1./d_km;
        end
    end
    if max(dme_raw) > 0
        dme_score_norm = dme_raw / max(dme_raw);
    else
        dme_score_norm = zeros(n,1);
    end

    % Elevation clamped at 0: a polder below sea level is not easier to build on.
    difficulty_raw = max(elevation_m,0)/1000 + ruggedness_m/100 + ...
                     dme_cost_weight * dme_score_norm;

    if max(difficulty_raw) > 0
        difficulty_norm = difficulty_raw / max(difficulty_raw);
    else
        difficulty_norm = zeros(n,1);
    end

    parts.elevation_m      = elevation_m;
    parts.ruggedness_std_m = ruggedness_m;
    parts.dme_score_norm   = dme_score_norm;
    parts.difficulty_raw   = difficulty_raw;

end
