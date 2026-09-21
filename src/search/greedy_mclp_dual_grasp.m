function selected_order = greedy_mclp_dual_grasp(candidates, grid_points, border_hotspots, ...
    anchors, hotspot_weight, difficulty_norm, terrain_cost_weight, R_inner_km, R_outer_km, n_max, rcl_alpha, seed, D_min_km, n_channels_avail)
% GREEDY_MCLP_DUAL_GRASP  Randomised (GRASP) version of the provider-aware
%   dual-anchor greedy used by M3b (see greedy_mclp_dual). Seeded.
    rng(seed);
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
    cost_divisor = 1 + terrain_cost_weight * difficulty_norm;

    best_grid = zeros(numel(grid_points), 1);
    best_hs   = zeros(n_hs, 1);
    selected_order = zeros(n_max, 1);
    picked = false(n_cand, 1);

    for step = 1:n_max
        picked_lat = cand_lat(picked); picked_lon = cand_lon(picked);
        gains = -Inf(n_cand, 1);
        colors_needed = zeros(n_cand,1);
        for i = 1:n_cand
            if picked(i), continue; end
            colors_needed(i) = spectrum_colors_if_added(picked_lat, picked_lon, cand_lat(i), cand_lon(i), D_min_km);
            if colors_needed(i) > n_channels_avail, continue; end
            grid_gain = sum(grid_weight .* max(grid_prob(i,:)' - best_grid, 0));
            hs_gain   = sum(hotspot_weight .* max(HP(i,:)' - best_hs, 0));
            gains(i) = (grid_gain + hs_gain) / cost_divisor(i);
        end
        if all(gains == -Inf)
            colors_needed(picked) = Inf;
            [~, best] = min(colors_needed);
        else
            best = grasp_pick(gains, rcl_alpha);
        end
        picked(best) = true;
        best_grid = max(best_grid, grid_prob(best,:)');
        best_hs   = max(best_hs, HP(best,:)');
        selected_order(step) = best;
    end
end
