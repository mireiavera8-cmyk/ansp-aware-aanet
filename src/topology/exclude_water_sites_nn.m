% EXCLUDE_WATER_SITES_NN  Nearest-neighbour water detection for off-grid candidate pools.
%
% Fallback for candidates with no exact row in data/terrain_elevation.csv (keyed
% to the M3 grid). A site is water if its nearest sample lies within
% max_match_deg and has elevation exactly 0 m (Copernicus GLO-90 water fill;
% negative elevations are land). Unmatched candidates are KEPT, so the method
% under-excludes and any effect it measures is a lower bound.
%
% INPUT  : candidates (.lat, .lon), terrain_path, max_match_deg (degrees)
% OUTPUT : is_water; diag .n_water .n_unmatched .n_total .match_deg_p50/_p90

function [is_water, diag] = exclude_water_sites_nn(candidates, terrain_path, max_match_deg)

    T = readtable(terrain_path);
    tlat = T.lat; tlon = T.lon; telev = T.elevation_m;

    n = numel(candidates);
    is_water  = false(n, 1);
    unmatched = false(n, 1);
    match_deg = zeros(n, 1);

    for i = 1:n
        d2 = (tlat - candidates(i).lat).^2 + (tlon - candidates(i).lon).^2;
        [m2, j] = min(d2);
        match_deg(i) = sqrt(m2);
        if match_deg(i) > max_match_deg
            unmatched(i) = true;      % no nearby evidence -> keep the site
        else
            is_water(i) = (telev(j) == 0);
        end
    end

    diag.n_total       = n;
    diag.n_water       = sum(is_water);
    diag.n_unmatched   = sum(unmatched);
    diag.match_deg_p50 = median(match_deg);
    diag.match_deg_p90 = prctile_local(match_deg, 90);

end


% Percentile without the Statistics Toolbox.
function v = prctile_local(x, p)
    x = sort(x(:));
    if isempty(x), v = NaN; return; end
    idx = max(1, min(numel(x), ceil(p/100 * numel(x))));
    v = x(idx);
end
