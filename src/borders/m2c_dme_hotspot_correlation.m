% M2C_DME_HOTSPOT_CORRELATION  Does DME interference co-locate with border-crossing hotspots?
%   Cheap side-check of whether the administrative-fragmentation
%   vulnerability (M2/M2b) and physical L-band interference compound each
%   other: evaluates the aggregate 1/d DME beacon proximity score
%   (config.dme_beacons, floor 20 km, normalised to the corridor-grid max)
%   at each hotspot centroid and correlates it with the crossing count
%   (Pearson and Spearman). A weak correlation leaves M4's uniform
%   fade-margin assumption in place.
%   Inputs : border_hotspots (m2b_muac_control_analysis.m), config.
%   Outputs: results struct; results/dme_hotspot_correlation.mat and
%            m2c_dme_vs_hotspot.png under config.output_figures.

function results = m2c_dme_hotspot_correlation(border_hotspots, config)

    fprintf('[M2c] DME interference vs. border-hotspot correlation starting...\n');

    dme_beacons = config.dme_beacons;
    beacon_names = config.dme_beacon_names;
    km_per_deg = 111.0;

    % ── Reference grid, only to fix the 0-1 normalisation scale ──
    grid_res = 0.5;
    lat_vec = config.lat_min:grid_res:config.lat_max;
    lon_vec = config.lon_min:grid_res:config.lon_max;
    [LON_grid, LAT_grid] = meshgrid(lon_vec, lat_vec);
    dme_map = zeros(size(LAT_grid));
    for b = 1:size(dme_beacons,1)
        d_km = sqrt(((LAT_grid-dme_beacons(b,1))*km_per_deg).^2 + ...
                    ((LON_grid-dme_beacons(b,2))*km_per_deg.*cosd(LAT_grid)).^2);
        d_km = max(d_km, 20);
        dme_map = dme_map + 1./d_km;
    end
    norm_factor = max(dme_map(:));

    % ── DME score at each hotspot centroid ──
    n_hs = numel(border_hotspots);
    dme_score = zeros(n_hs, 1);
    for h = 1:n_hs
        lat = border_hotspots(h).centroid_lat;
        lon = border_hotspots(h).centroid_lon;
        d_km = sqrt(((lat-dme_beacons(:,1))*km_per_deg).^2 + ...
                    ((lon-dme_beacons(:,2))*km_per_deg*cosd(lat)).^2);
        d_km = max(d_km, 20);
        dme_score(h) = sum(1./d_km) / norm_factor;
    end

    counts = [border_hotspots.count]';

    % ── Correlation ──
    % corrcoef is base MATLAB (corr/tiedrank need the Statistics Toolbox);
    % Spearman = Pearson on tie-averaged ranks, via rank_with_ties below.
    R = corrcoef(counts, dme_score);
    r_pearson = R(1,2);
    R_rank = corrcoef(rank_with_ties(counts), rank_with_ties(dme_score));
    r_spearman = R_rank(1,2);

    fprintf('[M2c] Pearson r = %.3f, Spearman rho = %.3f (n=%d hotspots)\n', ...
        r_pearson, r_spearman, n_hs);
    fprintf('[M2c] ---- HOTSPOTS RANKED BY CROSSING COUNT ----\n');
    fprintf('[M2c] %-20s %-20s %8s %10s\n', 'ANSP A', 'ANSP B', 'Count', 'DME score');
    [~, sort_idx] = sort(counts, 'descend');
    for i = sort_idx'
        fprintf('[M2c] %-20s %-20s %8d %10.3f\n', ...
            border_hotspots(i).ansp_a, border_hotspots(i).ansp_b, ...
            border_hotspots(i).count, dme_score(i));
    end

    % ── Interpretation guardrail ──
    if abs(r_pearson) < 0.3
        fprintf('[M2c] -> Weak/no correlation: administrative and DME-interference ');
        fprintf('vulnerabilities appear INDEPENDENT in this corridor. Report as such —\n');
        fprintf('       do not feed this into M4; the uniform fade-margin assumption stands.\n');
    else
        fprintf('[M2c] -> Non-trivial correlation found: co-location is worth carrying into M4\n');
        fprintf('       as a per-station DME-based fade-margin adjustment.\n');
    end

    % ── PACKAGE + SAVE ──
    results.dme_score     = dme_score;
    results.counts        = counts;
    results.pearson_r     = r_pearson;
    results.spearman_rho  = r_spearman;
    results.dme_beacons   = dme_beacons;
    results.beacon_names  = beacon_names;
    results.norm_factor   = norm_factor;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'dme_hotspot_correlation.mat'), 'results');
    fprintf('[M2c] Saved: %s\n', fullfile(config.output_data, 'dme_hotspot_correlation.mat'));

    % ── SCATTER PLOT (only the busiest pinch-points are labelled) ──
    fig = figure('Name', 'M2c - DME vs border-crossing hotspots', 'NumberTitle', 'off', ...
           'Visible', 'off', 'Color', 'w', 'Position', [100 100 900 600]);
    ax = axes(fig); hold(ax, 'on');
    scatter(ax, counts, dme_score, 90, 'filled', 'MarkerFaceColor', [0.75 0.2 0.2], ...
            'MarkerFaceAlpha', 0.85, 'MarkerEdgeColor', 'w');

    label_floor = 78;   % crossings; below this the labels collide
    for i = 1:n_hs
        if counts(i) < label_floor, continue; end
        nm = sprintf('%s / %s', border_hotspots(i).ansp_a, border_hotspots(i).ansp_b);
        % keep the busiest point's label inside the axes
        if counts(i) > 0.8 * max(counts)
            text(ax, counts(i)-4, dme_score(i), nm, 'FontSize', 8.5, ...
                 'HorizontalAlignment', 'right', 'Color', [0.15 0.15 0.15]);
        else
            text(ax, counts(i)+3, dme_score(i), nm, 'FontSize', 8.5, ...
                 'Color', [0.15 0.15 0.15]);
        end
    end

    xlabel(ax, 'Confirmed border crossings at this pinch-point', 'FontSize', 11);
    ylabel(ax, 'Normalised DME interference score at the same location', 'FontSize', 11);
    title(ax, sprintf(['Do provider crossings and L-band interference occur in the same places?' ...
        '  (Pearson r = %.2f)'], r_pearson), 'FontSize', 12, 'FontWeight', 'normal');
    xlim(ax, [-8, max(counts)*1.10]);
    grid(ax, 'on'); box(ax, 'on'); set(ax, 'GridAlpha', 0.12, 'FontSize', 10);
    hold(ax, 'off');

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    exportgraphics(fig, fullfile(config.output_figures, 'm2c_dme_vs_hotspot.png'), 'Resolution', 200);
    close(fig);
    fprintf('[M2c] Plot saved: %s\n', fullfile(config.output_figures, 'm2c_dme_vs_hotspot.png'));

    fprintf('[M2c] DME/hotspot correlation analysis complete.\n');

end


% Tie-averaged ranking (equal values share the mean rank), i.e. tiedrank without the toolbox.
function r = rank_with_ties(x)
    [sorted_x, idx] = sort(x);
    n = numel(x);
    r_sorted = zeros(n, 1);
    i = 1;
    while i <= n
        j = i;
        while j < n && sorted_x(j+1) == sorted_x(i)
            j = j + 1;
        end
        r_sorted(i:j) = mean(i:j);
        i = j + 1;
    end
    r = zeros(n, 1);
    r(idx) = r_sorted;
end
