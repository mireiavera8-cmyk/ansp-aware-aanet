% M7_RADIO_HORIZON_EFFECT  Does the radio horizon reclassify any traffic?
%
% Using each aircraft's real altitude and its distance to the nearest
% station, counts the sampled ticks that the distance soft-edge model would
% serve but that lie beyond the 4/3-earth radio horizon,
% d = 3.57*(sqrt(4/3*h_gs) + sqrt(4/3*h_ac)) km, with mast height
% config.gs_mast_height_m (default 25 m). Also reports the crossover
% altitude where the horizon equals R_outer and an illustrative
% altitude/horizon table bracketing the corridor's real altitude range.
% Kept separate from m7_signal_quality: horizon is a hard geometric cutoff,
% not a signal degradation.
%
% INPUT : tagged_data, COL, scen, n, config, label.
% OUTPUT: results struct saved to results/horizon_effect_<label>.mat.

function results = m7_radio_horizon_effect(tagged_data, COL, scen, n, config, label)

    fprintf('[M7-horizon] Radio horizon effect starting (%s, N=%d)...\n', label, n);

    TIME = COL.TIME; LAT = COL.LAT; LON = COL.LON; ALT = COL.ALT;

    if isfield(config, 'gs_mast_height_m')
        gs_mast_height_m = config.gs_mast_height_m;
    else
        gs_mast_height_m = 25;
    end

    [R_inner_km, R_outer_km] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);

    cand = scen.candidates;
    idx  = scen.selected_order(1:n);
    gs_lat = arrayfun(@(i) cand(i).lat, idx);
    gs_lon = arrayfun(@(i) cand(i).lon, idx);

    times_all = unique(tagged_data(:,TIME));
    times = times_all(1:30:end);

    n_total = 0; n_reclassified = 0;
    real_alt_min = Inf; real_alt_max = -Inf;

    for ti = 1:numel(times)
        t = times(ti);
        mask = tagged_data(:,TIME) == t;
        ac_lat = tagged_data(mask, LAT); ac_lon = tagged_data(mask, LON); ac_alt = tagged_data(mask, ALT);
        n_ac = numel(ac_lat);
        if n_ac == 0, continue; end
        n_total = n_total + n_ac;
        real_alt_min = min(real_alt_min, min(ac_alt));
        real_alt_max = max(real_alt_max, max(ac_alt));

        d_gs = haversine_km(ac_lat, ac_lon, gs_lat', gs_lon');
        d_min = min(d_gs, [], 2);
        base_prob = max(0, min(1, (R_outer_km - d_min) / (R_outer_km - R_inner_km)));
        within_range_by_distance = base_prob > 0;   % served per the distance model alone

        d_horizon = radio_horizon_km(gs_mast_height_m, ac_alt);
        blocked_by_horizon = d_min > d_horizon;

        n_reclassified = n_reclassified + sum(within_range_by_distance & blocked_by_horizon);
    end

    results.label = label;
    results.n_stations = n;
    results.pct_reclassified = 100 * n_reclassified / n_total;
    results.real_alt_min_m = real_alt_min;
    results.real_alt_max_m = real_alt_max;
    results.gs_mast_height_m = gs_mast_height_m;
    results.R_outer_km = R_outer_km;

    % Crossover altitude: where horizon(gs_mast, alt) == R_outer
    alt_grid = linspace(0, 16000, 2000);
    h_grid = radio_horizon_km(gs_mast_height_m, alt_grid);
    below = h_grid < R_outer_km;
    if any(below)
        results.crossover_altitude_m = alt_grid(find(below, 1, 'last'));
    else
        results.crossover_altitude_m = NaN;
    end

    illustrative_alts = [500, 1000, 3000, real_alt_min, mean([real_alt_min,real_alt_max]), real_alt_max];
    results.illustrative_alt_m = illustrative_alts;
    results.illustrative_horizon_km = radio_horizon_km(gs_mast_height_m, illustrative_alts);

    fprintf('[M7-horizon] %s: horizon reclassifies %.2f%% of aircraft-ticks (real altitude range %.0fm-%.0fm)\n', ...
        label, results.pct_reclassified, real_alt_min, real_alt_max);
    fprintf('[M7-horizon]   crossover altitude (horizon=R_outer): %.0fm — this dataset sits %s it\n', ...
        results.crossover_altitude_m, ternary(real_alt_min > results.crossover_altitude_m, 'entirely above', 'partly below'));

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, sprintf('horizon_effect_%s.mat', label)), 'results');

end


function d_km = radio_horizon_km(h1_m, h2_m)
    k = 4/3;
    d_km = 3.57 * (sqrt(k * max(h1_m,0)) + sqrt(k * max(h2_m,0)));
end
