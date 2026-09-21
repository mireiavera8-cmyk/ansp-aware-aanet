% M3_VISUALIZE  Static figures for the M3 topology study.
%   Plots the soft-edge coverage sweep (optimistic vs conservative fade
%   margin, elbows marked), the frequency-reuse pattern at each scenario's
%   elbow N (stations coloured by assigned channel, dotted edges between any
%   pair closer than D_min) and the station-siting map with R_inner/R_outer
%   coverage rings, all over the upper-airspace ANSP boundaries.
%   Inputs : results (m3_topology_study.m), ansp_polys (load_ansp_polygons.m),
%            config.
%   Outputs: m3_coverage_curve.png, m3_frequency_reuse_{optimistic,
%            conservative}.png, m3_station_map_{optimistic,conservative}.png
%            under config.output_figures.
function m3_visualize(results, ansp_polys, config)

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end

    plot_coverage_band(results, config);

    plot_frequency_reuse_map(results.optimistic, ansp_polys, config, 'optimistic', ...
        sprintf('optimistic, F=%.1fdB', results.fade_margin_db_lo));
    plot_frequency_reuse_map(results.conservative, ansp_polys, config, 'conservative', ...
        sprintf('conservative, F=%.1fdB', results.fade_margin_db_hi));

    plot_station_map(results.optimistic, ansp_polys, config, 'optimistic', ...
        sprintf('optimistic, F=%.1fdB (R_{inner}=%.0f, R_{outer}=%.0f km)', ...
        results.fade_margin_db_lo, results.optimistic.R_inner_km, results.optimistic.R_outer_km));
    plot_station_map(results.conservative, ansp_polys, config, 'conservative', ...
        sprintf('conservative, F=%.1fdB (R_{inner}=%.0f, R_{outer}=%.0f km)', ...
        results.fade_margin_db_hi, results.conservative.R_inner_km, results.conservative.R_outer_km));

    fprintf('[M3-VIZ] Saved 5 figures to %s\n', config.output_figures);

end


% ── Coverage band: coverage% (top) and marginal gain per station (bottom) ──
function plot_coverage_band(results, config)

    opt = results.optimistic;
    con = results.conservative;
    n = numel(opt.coverage_pct);
    x = (1:n)';
    blue       = [0.16 0.47 0.84];
    light_blue = [0.53 0.73 0.92];
    orange     = [0.85 0.33 0.10];

    fig = figure('Visible', 'off', 'Position', [100 100 800 650]);

    subplot(2,1,1);
    hold on;
    fill([x; flipud(x)], [con.coverage_pct; flipud(opt.coverage_pct)], blue, ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none');
    plot(x, opt.coverage_pct, '--o', 'LineWidth', 1, 'MarkerSize', 3, 'Color', light_blue);
    plot(x, con.coverage_pct, '-o', 'LineWidth', 1.5, 'MarkerSize', 4, 'Color', blue);
    xline(opt.elbow_N, ':', sprintf('opt. elbow N=%d', opt.elbow_N), ...
        'Color', light_blue, 'LabelVerticalAlignment', 'bottom');
    xline(con.elbow_N, '--', sprintf('cons. elbow N=%d', con.elbow_N), ...
        'Color', orange, 'LabelVerticalAlignment', 'bottom');
    xlabel('Number of ground stations (N)');
    ylabel('Coverage (%)');
    title(sprintf('M3 - Soft-edge coverage sweep (fade margin %.1f-%.1fdB)', ...
        results.fade_margin_db_lo, results.fade_margin_db_hi));
    legend({'literature uncertainty band', ...
        sprintf('optimistic (F=%.1fdB)', results.fade_margin_db_lo), ...
        sprintf('conservative (F=%.1fdB)', results.fade_margin_db_hi)}, ...
        'Location', 'southeast', 'Box', 'off');
    grid on; box off; xlim([1, n]); ylim([0, 100]);

    subplot(2,1,2);
    hold on;
    bar(x - 0.15, opt.marginal_gain, 0.3, 'FaceColor', light_blue, 'EdgeColor', 'none');
    bar(x + 0.15, con.marginal_gain, 0.3, 'FaceColor', blue, 'EdgeColor', 'none');
    xlabel('Number of ground stations (N)');
    ylabel('Marginal coverage gain (pp)');
    title('Marginal gain per additional station');
    legend({'optimistic', 'conservative'}, 'Location', 'northeast', 'Box', 'off');
    grid on; box off; xlim([0.5, n+0.5]);

    exportgraphics(fig, fullfile(config.output_figures, 'm3_coverage_curve.png'), 'Resolution', 150);
    close(fig);

end


% ── Frequency reuse map: elbow-N stations coloured by channel, conflict edges ──
% Channel assignment is scen.channel_assignment_elbow (conservative C/I bound,
% see m3_topology_study.m); no two same-coloured stations should share an edge.
function plot_frequency_reuse_map(scen, ansp_polys, config, tag, label)

    fig = figure('Visible', 'off', 'Position', [100 100 900 700]);
    hold on;

    upper = ansp_polys(strcmp({ansp_polys.layer}, 'upper'));
    for k = 1:numel(upper)
        plot(upper(k).lon, upper(k).lat, '-', 'Color', [0.82 0.82 0.82], ...
            'LineWidth', 0.75, 'HandleVisibility', 'off');
    end

    elbow_N = scen.elbow_N;
    sel_idx = scen.selected_order(1:elbow_N);
    cand    = scen.candidates;
    cand_lat = [cand.lat]';
    cand_lon = [cand.lon]';
    sel_lat  = cand_lat(sel_idx);
    sel_lon  = cand_lon(sel_idx);
    ch       = scen.channel_assignment_elbow;
    n_ch     = max(ch);

    % Conflict edges (pairs within D_min_km_hi) drawn first, under the markers.
    for i = 1:elbow_N
        for j = i+1:elbow_N
            d = haversine_km(sel_lat(i), sel_lon(i), sel_lat(j), sel_lon(j));
            if d < scen.D_min_km_hi
                plot([sel_lon(i) sel_lon(j)], [sel_lat(i) sel_lat(j)], ':', ...
                    'Color', [0.55 0.55 0.55], 'LineWidth', 0.6, 'HandleVisibility', 'off');
            end
        end
    end

    cmap = lines(max(n_ch, 1));
    for c = 1:n_ch
        mask = ch == c;
        scatter(sel_lon(mask), sel_lat(mask), 90, cmap(c,:), 'filled', ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1, 'DisplayName', sprintf('Channel %d', c));
    end
    for k = 1:elbow_N
        text(sel_lon(k), sel_lat(k), sprintf(' %d', k), 'FontSize', 8, ...
            'FontWeight', 'bold', 'Color', [0.15 0.15 0.15], 'HandleVisibility', 'off');
    end

    xlim([config.lon_min, config.lon_max]);
    ylim([config.lat_min, config.lat_max]);
    xlabel('Longitude (deg)'); ylabel('Latitude (deg)');
    title(sprintf('M3 - Frequency reuse pattern at elbow N=%d, %s (%d channels)', ...
        elbow_N, label, n_ch));
    legend('Location', 'eastoutside', 'Box', 'off');
    axis equal; grid on; box on;

    exportgraphics(fig, fullfile(config.output_figures, sprintf('m3_frequency_reuse_%s.png', tag)), ...
        'Resolution', 150);
    close(fig);

end


function plot_station_map(scen, ansp_polys, config, tag, label)

    blue   = [0.16 0.47 0.84];
    orange = [0.85 0.33 0.10];

    fig = figure('Visible', 'off', 'Position', [100 100 900 700]);
    hold on;

    upper = ansp_polys(strcmp({ansp_polys.layer}, 'upper'));
    for k = 1:numel(upper)
        plot(upper(k).lon, upper(k).lat, '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.75);
    end

    cand     = scen.candidates;
    cand_lat = [cand.lat]';
    cand_lon = [cand.lon]';
    weight   = [cand.weight]';
    scatter(cand_lon, cand_lat, 6 + 20*weight/max(weight), [0.82 0.82 0.82], ...
        'filled', 'MarkerFaceAlpha', 0.5);

    elbow_N = scen.elbow_N;
    sel_idx = scen.selected_order(1:elbow_N);
    sel_lat = cand_lat(sel_idx);
    sel_lon = cand_lon(sel_idx);

    for k = 1:elbow_N
        draw_soft_edge(sel_lon(k), sel_lat(k), scen.R_inner_km, scen.R_outer_km, blue);
    end
    scatter(sel_lon, sel_lat, 70, orange, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 1);
    for k = 1:elbow_N
        text(sel_lon(k), sel_lat(k), sprintf(' %d', k), 'FontSize', 9, ...
            'FontWeight', 'bold', 'Color', [0.2 0.2 0.2]);
    end

    xlim([config.lon_min, config.lon_max]);
    ylim([config.lat_min, config.lat_max]);
    xlabel('Longitude (deg)'); ylabel('Latitude (deg)');
    title(sprintf('M3 - Station siting at elbow N=%d, %s, coverage %.1f%%', ...
        elbow_N, label, scen.coverage_pct(elbow_N)));
    axis equal; grid on; box on;

    exportgraphics(fig, fullfile(config.output_figures, sprintf('m3_station_map_%s.png', tag)), ...
        'Resolution', 150);
    close(fig);

end


% ── Soft-edge rings: solid at R_inner (guaranteed link), dashed at R_outer ──
% Flat-earth 111 km/deg approximation, adequate at this disc scale.
function draw_soft_edge(lon0, lat0, R_inner_km, R_outer_km, color)
    km_per_deg = 111.0;
    th = linspace(0, 2*pi, 60);

    dlat_in = (R_inner_km/km_per_deg) * sin(th);
    dlon_in = (R_inner_km/km_per_deg/cosd(lat0)) * cos(th);
    plot(lon0+dlon_in, lat0+dlat_in, '-', 'Color', color, 'LineWidth', 1);

    dlat_out = (R_outer_km/km_per_deg) * sin(th);
    dlon_out = (R_outer_km/km_per_deg/cosd(lat0)) * cos(th);
    plot(lon0+dlon_out, lat0+dlat_out, '--', 'Color', color, 'LineWidth', 0.6);
end
