% M7_VISUALIZE_HORIZON_EFFECT  Radio-horizon cut-offs overlaid on the real degradation curve.
%   Redraws the median signal-quality curve from m7_signal_quality.m and
%   marks where the radio horizon at illustrative low altitudes would block
%   the link, with a note that the dataset's real altitude range never binds.
%   Inputs : sig_results (m7_signal_quality.m), horizon_results
%            (m7_radio_horizon_effect.m), both for the same strategy; config.
%   Output : m7_horizon_effect_<label>.png under config.output_figures.
function m7_visualize_horizon_effect(sig_results, horizon_results, config)

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    plot_horizon_overlay(sig_results, horizon_results, config);
    fprintf('[M7-horizon-VIZ] Saved 1 figure to %s\n', config.output_figures);

end


function plot_horizon_overlay(sr, hr, config)

    d = sr.curve_distance_km;
    eff = sr.curve_eff_prob;

    edges = linspace(0, sr.R_outer_km, 25);
    centers = []; med = [];
    for b = 1:numel(edges)-1
        m = d >= edges(b) & d < edges(b+1);
        if sum(m) < 5, continue; end
        centers(end+1) = mean(edges(b:b+1)); %#ok<AGROW>
        med(end+1) = median(eff(m)); %#ok<AGROW>
    end

    blue = [0.224 0.529 0.898]; red = [0.886 0.294 0.290]; gray = [0.55 0.55 0.55];

    fig = figure('Visible', 'off', 'Position', [100 100 950 620]);
    hold on;

    plot(centers, med, '-o', 'Color', blue, 'LineWidth', 2, 'MarkerSize', 4);

    % Illustrative low altitudes (first three entries) are the ones that bind.
    low_alts = hr.illustrative_alt_m(1:3);
    low_horiz = hr.illustrative_horizon_km(1:3);
    y_labels = [0.95, 0.87, 0.79];
    for i = 1:3
        xline(low_horiz(i), ':', 'Color', red, 'LineWidth', 1.2);
        text(low_horiz(i)+3, y_labels(i), sprintf('%.0fm alt -> blocked beyond %.0fkm', low_alts(i), low_horiz(i)), ...
            'Color', red, 'FontSize', 9, 'FontWeight', 'bold');
    end

    % Real altitude range: one summary note, since horizon never binds there.
    text(sr.R_outer_km*0.98, 0.30, sprintf(['This dataset''s real altitude range\n' ...
        '(%.0fm-%.0fm): horizon never binds\n(always exceeds R_{outer}=%.0fkm)'], ...
        hr.real_alt_min_m, hr.real_alt_max_m, sr.R_outer_km), ...
        'Color', gray, 'FontSize', 9.5, 'HorizontalAlignment', 'right');

    xlabel('Distance to nearest station (km)');
    ylabel('Effective signal quality (0-1)');
    title('Where would radio horizon additionally cut off this signal?', 'FontWeight', 'bold');
    subtitle(sprintf('%s — real dataset reclassifies %.2f%% of aircraft-ticks (dashed = real altitude range, dotted = illustrative lower altitudes)', ...
        strrep(sr.label,'_',' '), hr.pct_reclassified));
    xlim([0, sr.R_outer_km]); ylim([0, 1.05]);
    grid on; box off;

    exportgraphics(fig, fullfile(config.output_figures, sprintf('m7_horizon_effect_%s.png', sr.label)), 'Resolution', 150);
    close(fig);

end
