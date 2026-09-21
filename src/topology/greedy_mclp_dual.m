function [selected_order, coverage_pct] = greedy_mclp_dual(candidates, grid_points, ...
    border_hotspots, anchors, hotspot_weight, difficulty_norm, terrain_cost_weight, ...
    R_inner_km, R_outer_km, n_max, D_min_km, n_channels_avail)
% GREEDY_MCLP_DUAL  Greedy maximal-covering placement over two demand sets:
%   the traffic grid (ordinary soft coverage) and the border pinch-points
%   (dual-anchor: min of the two anchor probabilities). Each step picks the
%   candidate with the largest terrain-cost-weighted marginal gain that
%   stays within the live spectrum budget. Used by M3b and the M3d sweep.
    n_cand = numel(candidates);
    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';

    grid_lat = [grid_points.lat]'; grid_lon = [grid_points.lon]';
    grid_weight = [grid_points.weight]';
    grid_prob = zeros(n_cand, numel(grid_points));
    for i = 1:n_cand
        d = haversine_km(cand_lat(i), cand_lon(i), grid_lat, grid_lon);
        grid_prob(i,:) = connection_probability(d, R_inner_km, R_outer_km);
    end

    n_hs = numel(border_hotspots);
    HP = zeros(n_cand, n_hs);
    for i = 1:n_cand
        dA = haversine_km(cand_lat(i), cand_lon(i), [anchors.lat_a]', [anchors.lon_a]');
        dB = haversine_km(cand_lat(i), cand_lon(i), [anchors.lat_b]', [anchors.lon_b]');
        pA = connection_probability(dA, R_inner_km, R_outer_km);
        pB = connection_probability(dB, R_inner_km, R_outer_km);
        HP(i,:) = min(pA, pB)';
    end

    total_weight = sum(grid_weight) + sum(hotspot_weight);
    best_grid = zeros(numel(grid_points), 1);
    best_hs   = zeros(n_hs, 1);
    cost_divisor = 1 + terrain_cost_weight * difficulty_norm;

    selected_order = zeros(n_max, 1);
    coverage_pct = zeros(n_max, 1);
    picked = false(n_cand, 1);

    for step = 1:n_max
        picked_lat = cand_lat(picked); picked_lon = cand_lon(picked);
        gains = zeros(n_cand, 1);
        colors_needed = zeros(n_cand, 1);
        for i = 1:n_cand
            if picked(i), continue; end
            colors_needed(i) = spectrum_colors_if_added(picked_lat, picked_lon, cand_lat(i), cand_lon(i), D_min_km);
            if colors_needed(i) > n_channels_avail
                gains(i) = -Inf;
                continue;
            end
            grid_gain = sum(grid_weight .* max(grid_prob(i,:)' - best_grid, 0));
            hs_gain   = sum(hotspot_weight .* max(HP(i,:)' - best_hs, 0));
            gains(i) = (grid_gain + hs_gain) / cost_divisor(i);
        end
        if all(gains(~picked) == -Inf)
            colors_needed(picked) = Inf;
            [~, best] = min(colors_needed);   % least-bad fallback when the spectrum budget is exhausted
        else
            [~, best] = max(gains);
        end
        picked(best) = true;
        best_grid = max(best_grid, grid_prob(best,:)');
        best_hs   = max(best_hs, HP(best,:)');
        selected_order(step) = best;
        coverage_pct(step) = 100 * (sum(grid_weight .* best_grid) + sum(hotspot_weight .* best_hs)) / total_weight;
    end
end
