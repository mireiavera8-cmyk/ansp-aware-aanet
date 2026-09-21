% M7_VISUALIZE_SIGNAL_QUALITY  Signal degradation curve per strategy plus a summary table.
%   For each strategy, plots the median and 25th-75th percentile band of
%   effective signal quality vs distance to the nearest station against the
%   distance-only (no DME interference) curve, with clean / FEC-recovered /
%   failed bands shaded. Then prints the share of flight time in each class.
%   Inputs : results_list (cell array of m7_signal_quality.m results, one
%            per strategy), config.
%   Output : m7_signal_degradation_<label>.png per strategy under
%            config.output_figures.
function m7_visualize_signal_quality(results_list, config)

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    for i = 1:numel(results_list)
        plot_degradation_curve(results_list{i}, config);
    end
    print_summary_table(results_list);
    fprintf('[M7-VIZ] Saved %d degradation figure(s) to %s\n', numel(results_list), config.output_figures);

end


function plot_degradation_curve(r, config)

    d = r.curve_distance_km;
    eff = r.curve_eff_prob;

    edges = linspace(0, r.R_outer_km, 25);
    centers = []; med = []; p25 = []; p75 = [];
    for b = 1:numel(edges)-1
        m = d >= edges(b) & d < edges(b+1);
        if sum(m) < 5, continue; end
        centers(end+1) = mean(edges(b:b+1)); %#ok<AGROW>
        med(end+1) = median(eff(m)); %#ok<AGROW>
        p25(end+1) = prctile(eff(m), 25); %#ok<AGROW>
        p75(end+1) = prctile(eff(m), 75); %#ok<AGROW>
    end

    theory_d = linspace(0, r.R_outer_km, 200);
    theory = max(0, min(1, (r.R_outer_km - theory_d) / (r.R_outer_km - r.R_inner_km)));

    green = [0.047 0.639 0.047]; amber = [0.937 0.624 0.153]; red = [0.886 0.294 0.290];
    blue = [0.224 0.529 0.898]; gray = [0.55 0.55 0.55];

    fig = figure('Visible', 'off', 'Position', [100 100 900 600]);
    hold on;

    patch([0 r.R_outer_km r.R_outer_km 0], [0.8 0.8 1.0 1.0], green, 'FaceAlpha', 0.08, 'EdgeColor', 'none');
    patch([0 r.R_outer_km r.R_outer_km 0], [0.5 0.5 0.8 0.8], amber, 'FaceAlpha', 0.08, 'EdgeColor', 'none');
    patch([0 r.R_outer_km r.R_outer_km 0], [0 0 0.5 0.5], red, 'FaceAlpha', 0.08, 'EdgeColor', 'none');
    text(r.R_outer_km*0.98, 0.9, 'clean', 'Color', green, 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    text(r.R_outer_km*0.98, 0.65, 'FEC-recovered', 'Color', amber, 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    text(r.R_outer_km*0.98, 0.25, 'direct link fails', 'Color', red, 'HorizontalAlignment', 'right', 'FontWeight', 'bold');

    plot(theory_d, theory, '--', 'Color', gray, 'LineWidth', 1.5);
    fill([centers, fliplr(centers)], [p25, fliplr(p75)], blue, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    plot(centers, med, '-o', 'Color', blue, 'LineWidth', 2, 'MarkerSize', 4);

    xlabel('Distance to nearest station (km)');
    ylabel('Effective signal quality (0-1)');
    title('How DME interference degrades signal quality below the distance-only curve', 'FontWeight', 'bold');
    subtitle(sprintf('%s — shaded band = 25th-75th percentile of real aircraft-ticks', strrep(r.label,'_',' ')));
    legend({'', '', '', 'distance only (no interference)', 'real signal quality (DME included)'}, ...
        'Location', 'southwest', 'Box', 'off');
    xlim([0, r.R_outer_km]); ylim([0, 1.05]);
    grid on; box off;

    exportgraphics(fig, fullfile(config.output_figures, sprintf('m7_signal_degradation_%s.png', r.label)), 'Resolution', 150);
    close(fig);

end


function print_summary_table(results_list)

    fprintf('\n=== SIGNAL QUALITY SUMMARY (%% of flight time) ===\n');
    fprintf('%-18s %8s %8s %8s %8s\n', 'Strategy', 'Clean', 'FEC-rec', 'A2A-res', 'Lost');
    for i = 1:numel(results_list)
        r = results_list{i};
        fprintf('%-18s %7.1f%% %7.1f%% %7.1f%% %7.1f%%\n', strrep(r.label,'_',' '), ...
            r.pct_clean, r.pct_fec, r.pct_relay, r.pct_lost);
    end
    fprintf('\nMessage/link context (COCRv2, Graupl & Ehammer 2011): typical message %d bytes;\n', results_list{1}.message_size_bytes);
    fprintf('FEC-recovered traffic realistically uses robust coding (%.1fkbit/s); clean traffic\n', results_list{1}.rate_robust_kbit_s);
    fprintf('can use aggressive coding (%.1fkbit/s) — not simulated per-message, reported as context.\n', results_list{1}.rate_fast_kbit_s);

end
