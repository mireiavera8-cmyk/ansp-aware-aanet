% APPLY_SITING_CONSTRAINTS  Water exclusion and live spectrum budget for fixed-order topologies.
%
% M3c/M3g/M3h sort a per-candidate scalar once and deploy in that order; this
% applies the hard constraints the greedy modules enforce in-loop to such an order:
%   1. Water exclusion: Copernicus DEM elevation exactly 0 m (water fill), by
%      exact lookup in config.terrain_data_hex_path (fetch_hex_terrain.m), with
%      a nearest-neighbour fallback (exclude_water_sites_nn) if it is missing.
%   2. Spectrum budget: walking the order, a site is skipped if the accepted
%      set's conflict graph would need more channels than are available.
% Soft terrain difficulty is applied by the callers on their sort key, not here.
%
% INPUT  : candidates (.lat, .lon), order_in (indices, best first), config
% OUTPUT : order_out (same orientation, infeasible sites removed); diag with
%          .n_water_dropped .n_spectrum_dropped .n_in .n_out .D_min_km .water

function [order_out, diag] = apply_siting_constraints(candidates, order_in, config)

    % Orientation is preserved: downstream code transposes column orders.
    was_column = iscolumn(order_in);
    order_in = order_in(:)';

    % -- 1. WATER EXCLUSION (hard) --
    if exist(config.terrain_data_hex_path, 'file')
        [is_water, wdiag] = water_from_exact_terrain(candidates, config.terrain_data_hex_path);
    else
        fprintf(['[SITING] WARNING: %s not found - falling back to nearest-neighbour water\n' ...
                 '[SITING] detection, which UNDER-detects. Run fetch_hex_terrain.m.\n'], ...
                 config.terrain_data_hex_path);
        [is_water, wdiag] = exclude_water_sites_nn(candidates, ...
            config.terrain_data_path, config.water_match_max_deg);
    end
    keep = ~is_water(order_in);
    n_water_dropped = sum(~keep);
    order_w = order_in(keep);

    % -- 2. CO-CHANNEL SPECTRUM BUDGET (hard, live) --
    n_channels_avail = floor(config.spectrum_mhz / config.channel_bw_mhz);
    D_min_km = free_space_D_min(config.gs_radius_km, config.ci_required_db_max);

    lat = [candidates.lat]; lon = [candidates.lon];
    accepted = [];
    n_spectrum_dropped = 0;
    for k = 1:numel(order_w)
        trial = [accepted, order_w(k)];
        if channels_needed(lat(trial), lon(trial), D_min_km) <= n_channels_avail
            accepted = trial;
        else
            n_spectrum_dropped = n_spectrum_dropped + 1;
        end
    end

    order_out = accepted;
    if was_column, order_out = order_out(:); end

    diag.n_in                 = numel(order_in);
    diag.n_out                = numel(order_out);
    diag.n_water_dropped      = n_water_dropped;
    diag.n_spectrum_dropped   = n_spectrum_dropped;
    diag.D_min_km             = D_min_km;
    diag.n_channels_available = n_channels_avail;
    diag.water                = wdiag;

end


% WATER_FROM_EXACT_TERRAIN  Elevation exactly 0 m is the Copernicus GLO-90
% water-fill signature; negative elevations (polders) are land and are kept.
function [is_water, diag] = water_from_exact_terrain(candidates, terrain_path)
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
            error(['apply_siting_constraints: no terrain row for candidate (%.4f, %.4f) - ' ...
                   're-run fetch_hex_terrain.m for the current lattice/beacon list.'], ...
                   candidates(i).lat, candidates(i).lon);
        end
        is_water(i) = (lut(k) == 0);
    end
    diag.n_total = n;
    diag.n_water = sum(is_water);
    diag.n_unmatched = 0;
    diag.match_deg_p50 = 0;
    diag.match_deg_p90 = 0;
    diag.exact = true;
end


% CHANNELS_NEEDED  Greedy colouring of the conflict graph (edge if d < D_min).
function n_colors = channels_needed(lat, lon, D_min_km)
    n = numel(lat);
    if n == 0, n_colors = 0; return; end
    % Row orientation throughout, so the logical masks stay elementwise.
    lat = lat(:)'; lon = lon(:)';
    colors = zeros(1, n);
    for i = 1:n
        d = haversine_km(lat(i), lon(i), lat, lon);
        conflict = (d < D_min_km);
        conflict(i) = false;
        used = unique(colors(conflict & colors > 0));
        c = 1;
        while any(used == c), c = c + 1; end
        colors(i) = c;
    end
    n_colors = max(colors);
end
