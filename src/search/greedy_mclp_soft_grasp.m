function selected_order = greedy_mclp_soft_grasp(candidates, demand_points, ...
    difficulty_norm, terrain_cost_weight, R_inner_km, R_outer_km, n_max, rcl_alpha, seed, D_min_km, n_channels_avail)
% GREEDY_MCLP_SOFT_GRASP  Randomised (GRASP) version of the traffic-only
%   greedy MCLP used by M3: same gains, spectrum gate and terrain cost, but
%   each step picks from a restricted candidate list. Seeded for
%   reproducibility.
    rng(seed);
    n_cand = numel(candidates);
    cand_lat = [candidates.lat]'; cand_lon = [candidates.lon]';
    dem_lat  = [demand_points.lat]'; dem_lon = [demand_points.lon]';
    dem_weight = [demand_points.weight]';

    conn_prob = zeros(n_cand, numel(demand_points));
    for i = 1:n_cand
        d = haversine_km(cand_lat(i), cand_lon(i), dem_lat, dem_lon);
        conn_prob(i,:) = connection_probability(d, R_inner_km, R_outer_km);
    end
    cost_divisor = 1 + terrain_cost_weight * difficulty_norm;

    best_prob = zeros(numel(demand_points), 1);
    selected_order = zeros(n_max, 1);
    picked = false(n_cand, 1);

    for step = 1:n_max
        picked_lat = cand_lat(picked); picked_lon = cand_lon(picked);
        gains = -Inf(n_cand,1);
        colors_needed = zeros(n_cand,1);
        for i = 1:n_cand
            if picked(i), continue; end
            colors_needed(i) = spectrum_colors_if_added(picked_lat, picked_lon, cand_lat(i), cand_lon(i), D_min_km);
            if colors_needed(i) > n_channels_avail, continue; end
            improvement = max(conn_prob(i,:)' - best_prob, 0);
            gains(i) = sum(dem_weight .* improvement) / cost_divisor(i);
        end
        if all(gains == -Inf)
            colors_needed(picked) = Inf;
            [~, best] = min(colors_needed);
        else
            best = grasp_pick(gains, rcl_alpha);
        end
        picked(best) = true;
        best_prob = max(best_prob, conn_prob(best,:)');
        selected_order(step) = best;
    end
end
