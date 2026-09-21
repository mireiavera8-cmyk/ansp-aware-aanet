% PLOT_CORRIDOR_MAP  Corridor map of provider-boundary crossings, optionally with pinch-points.
%   Presentation only: no simulation, no .mat written. Draws the upper-
%   airspace provider polygons, every trajectory coloured by the provider
%   controlling that stretch, and a marker at every hysteresis-confirmed
%   crossing (M2). With overlay_pinchpoints = true, each M2b pinch-point is
%   added as a faint graded halo at its 90th-percentile radius, a centroid
%   marker scaled by crossings (same scaling as analyze_beacon_reach.m) and
%   one nominal cell circle for scale. Colours match web_visualizer/.
%   Reads  : results/tagged_data.mat (M1), results/border_crossings.mat (M2),
%            results/border_hotspots.mat (M2b, overlay only), ANSP polygons
%            via load_ansp_polygons(config).
%   Writes : corridor_crossing_map.png, or pinchpoint_map.png with overlay.
%   Usage  : plot_corridor_map           default decimation, no overlay
%            plot_corridor_map(5)        keep every 5th ping (denser tracks)
%            plot_corridor_map([], true) pinch-point overlay

function plot_corridor_map(decimate_step, overlay_pinchpoints)

    if nargin < 1 || isempty(decimate_step), decimate_step = 8; end
    if nargin < 2 || isempty(overlay_pinchpoints), overlay_pinchpoints = false; end

    config = setup_config();

    % ── LOAD ──
    S1 = load(fullfile(config.output_data, 'tagged_data.mat'), ...
              'tagged_data', 'ansp_names', 'COL');
    S2 = load(fullfile(config.output_data, 'border_crossings.mat'), 'border_stats');

    td         = S1.tagged_data;
    ansp_names = S1.ansp_names;
    COL        = S1.COL;
    bs         = S2.border_stats;

    fprintf('[MAP] %d state vectors, %d providers, %d confirmed crossings\n', ...
        size(td,1), numel(ansp_names), numel(bs.crossing_events));

    % Guarantee the ordering the block walk below assumes.
    [~, ord] = sortrows(td(:, [COL.ID, COL.TIME]));
    td = td(ord, :);

    % ── PROVIDER COLOURS (same palette as web_visualizer) ──
    pal = containers.Map( ...
        {'DFS','DSNA','MUAC','NATS (Continental)','Austro Control','Skyguide', ...
         'ANS CR','PANSA','HungaroControl','LPS'}, ...
        {'#2a78d6','#eb6834','#1baf7a','#eda100','#e87ba4','#4a3aa7', ...
         '#008300','#e34948','#8c6d1f','#616161'});
    grey = [0.78 0.76 0.72];

    n_ansp = numel(ansp_names);
    col = zeros(n_ansp, 3);
    for k = 1:n_ansp
        if isKey(pal, ansp_names{k})
            col(k,:) = hex2rgb(pal(ansp_names{k}));
        else
            col(k,:) = grey;
        end
    end

    % Traffic per provider drives legend order.
    pts_per_ansp = accumarray(td(:,COL.ANSP), 1, [n_ansp 1]);
    [~, rank] = sort(pts_per_ansp, 'descend');

    % ── ONE NaN-SEPARATED POLYLINE PER PROVIDER ──
    % Each track is split into runs of constant provider; the first point of
    % the next run is appended so coloured segments meet at the boundary.
    id_col      = td(:, COL.ID);
    block_start = [1; find(diff(id_col) ~= 0) + 1];
    block_end   = [block_start(2:end) - 1; numel(id_col)];
    n_ac        = numel(block_start);

    segs = repmat(struct('lon', [], 'lat', []), n_ansp, 1);

    for a = 1:n_ac
        rows = block_start(a):decimate_step:block_end(a);
        if numel(rows) < 2, continue; end

        lon = td(rows, COL.LON);
        lat = td(rows, COL.LAT);
        ans_seq = td(rows, COL.ANSP);

        cut = [1; find(diff(ans_seq) ~= 0) + 1; numel(ans_seq) + 1];
        for r = 1:numel(cut)-1
            i0 = cut(r);
            i1 = min(cut(r+1), numel(ans_seq));   % overlap into next run
            k  = ans_seq(i0);
            if k < 1 || k > n_ansp, continue; end
            segs(k).lon = [segs(k).lon; lon(i0:i1); NaN];
            segs(k).lat = [segs(k).lat; lat(i0:i1); NaN];
        end
    end

    % ── FIGURE ──
    fig_w = 1400; if overlay_pinchpoints, fig_w = 1600; end
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 fig_w 760]);
    % R2025a+ may apply a dark figure theme that exportgraphics honours; force light.
    try, theme(fig, 'light'); catch, end %#ok<CTCH>
    ax = axes(fig); hold(ax, 'on'); box(ax, 'on');
    set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');

    % Provider polygons (upper layer, the one the traffic is tagged against)
    polys = load_ansp_polygons(config);
    pad = 1.0;
    for i = 1:numel(polys)
        if ~strcmp(polys(i).layer, 'upper'), continue; end
        if max(polys(i).lat) < config.lat_min - pad || min(polys(i).lat) > config.lat_max + pad ...
        || max(polys(i).lon) < config.lon_min - pad || min(polys(i).lon) > config.lon_max + pad
            continue;
        end
        k = find(strcmp(ansp_names, polys(i).name), 1);
        if isempty(k), c = grey; else, c = col(k,:); end
        patch(ax, 'XData', polys(i).lon, 'YData', polys(i).lat, ...
              'FaceColor', c, 'FaceAlpha', 0.10, ...
              'EdgeColor', c*0.65, 'LineWidth', 1.1, 'HandleVisibility', 'off');
    end

    % Trajectories, fainter when the pinch-point overlay is the foreground.
    trk_alpha = 0.45; if overlay_pinchpoints, trk_alpha = 0.32; end
    h = gobjects(0); lbl = {};
    for k = rank(:)'
        if isempty(segs(k).lon), continue; end
        hk = plot(ax, segs(k).lon, segs(k).lat, '-', ...
                  'Color', [col(k,:) trk_alpha], 'LineWidth', 0.35);
        if pts_per_ansp(k) > 0.01 * sum(pts_per_ansp)
            h(end+1) = hk; %#ok<AGROW>
            lbl{end+1} = sprintf('%s (%.1f%%)', ansp_names{k}, ...
                          100 * pts_per_ansp(k) / sum(pts_per_ansp)); %#ok<AGROW>
        else
            set(hk, 'HandleVisibility', 'off');
        end
    end

    % ── PINCH-POINT HALOS (under the crossing markers) ──
    lat0 = mean([config.lat_min config.lat_max]);
    km_per_deg_lat = 111.0;
    km_per_deg_lon = 111.0 * cosd(lat0);

    if overlay_pinchpoints
        S3 = load(fullfile(config.output_data, 'border_hotspots.mat'), 'border_hotspots');
        H  = S3.border_hotspots;
        pp_lat = [H.centroid_lat]'; pp_lon = [H.centroid_lon]';
        pp_cnt = double([H.count]');  pp_r90 = [H.km_r90]';
        [~, pp_ord] = sort(pp_cnt, 'descend');

        navy = [0.08 0.16 0.42];

        % Graded halo: concentric patches whose alpha stacks towards the centre;
        % only the outermost ring gets an edge, marking the 90% radius.
        ring_frac  = [1.00 0.82 0.64 0.46 0.28];
        ring_alpha = 0.045;
        h_halo = gobjects(0);
        for i = 1:numel(pp_lat)
            for f = ring_frac
                hp = draw_disc(ax, pp_lat(i), pp_lon(i), pp_r90(i)*f, ...
                    km_per_deg_lat, km_per_deg_lon, navy, ring_alpha, ...
                    ternary(f == 1, 0.9, 0), ternary(f == 1, navy, 'none'));
                if f == 1 && isempty(h_halo), h_halo = hp; end
                set(hp, 'HandleVisibility', 'off');
            end
        end
        set(h_halo, 'HandleVisibility', 'on');
        h(end+1) = h_halo; lbl{end+1} = 'Pinch-point, 90% radius';
    end

    % Confirmed crossings
    ev = bs.crossing_events;
    if ~isempty(ev)
        hx = scatter(ax, [ev.lon], [ev.lat], 26, 'o', ...
                'MarkerFaceColor', [0.10 0.10 0.10], 'MarkerFaceAlpha', 0.55, ...
                'MarkerEdgeColor', 'w', 'LineWidth', 0.4);
        h(end+1) = hx;
        lbl{end+1} = sprintf('Confirmed crossing (n = %d)', numel(ev));
    end

    % ── PINCH-POINT CENTROIDS AND LABELS (over everything) ──
    if overlay_pinchpoints
        % Same area scaling as analyze_beacon_reach.m.
        pp_area = 50 + 320 * (pp_cnt / max(pp_cnt));
        hc = scatter(ax, pp_lon, pp_lat, pp_area, 'o', 'filled', ...
                'MarkerFaceColor', navy, 'MarkerFaceAlpha', 0.72, ...
                'MarkerEdgeColor', 'w', 'LineWidth', 1.0);
        h(end+1) = hc; lbl{end+1} = 'Pinch-point centroid, area = crossings';

        % Label the six largest pinch-points, above each halo.
        for k = 1:6
            i = pp_ord(k);
            txt = sprintf('%s/%s (%d)', short_ansp(H(i).ansp_a), short_ansp(H(i).ansp_b), pp_cnt(i));
            text(ax, pp_lon(i), pp_lat(i) + pp_r90(i)/km_per_deg_lat + 0.08, txt, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontSize', 8.5, 'FontWeight', 'bold', 'Color', navy, ...
                'BackgroundColor', [1 1 1], 'Margin', 1);
        end

        % One nominal cell for scale, outside the analysis box.
        R = config.gs_radius_km;
        cell_lon = config.lon_max + 0.55 + R/km_per_deg_lon;
        cell_lat = config.lat_min + 1.0 + R/km_per_deg_lat;
        hcell = draw_disc(ax, cell_lat, cell_lon, R, km_per_deg_lat, km_per_deg_lon, ...
            [0.85 0.45 0.05], 0.0, 1.5, [0.85 0.45 0.05]);
        set(hcell, 'LineStyle', '--');
        text(ax, cell_lon, cell_lat, sprintf('one %g km\ncell', R), ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', ...
            'Color', [0.6 0.3 0.0]);
        h(end+1) = hcell; lbl{end+1} = sprintf('One %g km cell, for scale', R);
    end

    % Analysis box
    hb = plot(ax, [config.lon_min config.lon_max config.lon_max config.lon_min config.lon_min], ...
                  [config.lat_min config.lat_min config.lat_max config.lat_max config.lat_min], ...
              'k--', 'LineWidth', 1.0);
    h(end+1) = hb; lbl{end+1} = 'Analysis box';

    % ── AXES ──
    x_hi = config.lon_max + 0.4;
    if overlay_pinchpoints
        x_hi = config.lon_max + 1.1 + 2*config.gs_radius_km/km_per_deg_lon;
    end
    xlim(ax, [config.lon_min - 0.4, x_hi]);
    ylim(ax, [config.lat_min - 0.4, config.lat_max + 0.4]);
    daspect(ax, [1 cosd(lat0) 1]);

    xlabel(ax, 'Longitude (\circE)', 'Color', 'k');
    ylabel(ax, 'Latitude (\circN)', 'Color', 'k');
    if overlay_pinchpoints
        title(ax, sprintf(['The %d crossings reduce to %d pinch-points ' ...
            '(median 90%% radius %.0f km against a %g km cell)'], ...
            bs.total_crossings, numel(pp_lat), median(pp_r90), config.gs_radius_km), ...
            'FontWeight', 'normal', 'Color', 'k');
    else
        title(ax, sprintf(['Provider-boundary crossings, design hour ' ...
            '(%d aircraft, %d crossings, %.1f%% of aircraft cross at least one border)'], ...
            bs.n_aircraft, bs.total_crossings, bs.pct_aircraft_crossing), ...
            'FontWeight', 'normal', 'Color', 'k');
    end

    lg = legend(ax, h, lbl, 'Location', 'eastoutside', 'FontSize', 8, 'Box', 'off');
    set(lg, 'TextColor', 'k');
    set(ax, 'Layer', 'top', 'FontSize', 9, 'TickDir', 'out', 'GridColor', 'k');
    grid(ax, 'on'); set(ax, 'GridAlpha', 0.10);

    % ── SAVE ──
    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    if overlay_pinchpoints
        out = fullfile(config.output_figures, 'pinchpoint_map.png');
    else
        out = fullfile(config.output_figures, 'corridor_crossing_map.png');
    end
    exportgraphics(fig, out, 'Resolution', 200);
    close(fig);
    fprintf('[MAP] Saved: %s\n', out);
end


% Filled circle of radius r_km, corrected for lat/lon anisotropy. Returns the patch.
function hp = draw_disc(ax, lat_c, lon_c, r_km, kmlat, kmlon, face, face_alpha, edge_lw, edge_col)
    t = linspace(0, 2*pi, 160);
    hp = patch(ax, 'XData', lon_c + (r_km/kmlon)*cos(t), ...
                   'YData', lat_c + (r_km/kmlat)*sin(t), ...
                   'FaceColor', face, 'FaceAlpha', face_alpha, ...
                   'EdgeColor', edge_col, 'LineWidth', max(edge_lw, 0.1));
    if edge_lw == 0, set(hp, 'EdgeColor', 'none'); end
end


function rgb = hex2rgb(hex)
    hex = char(hex);
    if hex(1) == '#', hex(1) = []; end
    rgb = double([hex2dec(hex(1:2)), hex2dec(hex(3:4)), hex2dec(hex(5:6))]) / 255;
end
