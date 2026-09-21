% M9_VISUALIZE  Two-panel figure for the singleton-ANSP mechanism.
%   Left: every single-station addition as a point, change in singleton
%   count vs change in inter-ANSP handover rate, with a linear fit. Right:
%   mean change per group (creates / no change / removes a singleton) with
%   the share of steps that made the network worse printed on each bar.
%   Inputs : results (m9_singleton_analysis.m), config.
%   Output : m9_singleton_mechanism.png under config.output_figures.

function m9_visualize(results, config)

    fprintf('[M9v] Rendering singleton-mechanism figure...\n');
    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end

    ds = results.delta_singleton;
    dp = results.delta_pct_inter;
    g  = results.groups;

    fig = figure('Visible','off','Position',[100 100 1200 520]);

    % ── LEFT: scatter ──
    subplot(1,2,1); hold on;
    jit = (rand(size(ds)) - 0.5) * 0.18;   % horizontal jitter only, ds is integer
    worse = dp > 0;
    scatter(ds(~worse)+jit(~worse), dp(~worse), 34, [0.20 0.60 0.35], 'filled', ...
        'MarkerFaceAlpha', 0.65);
    scatter(ds(worse)+jit(worse),  dp(worse),  34, [0.85 0.25 0.20], 'filled', ...
        'MarkerFaceAlpha', 0.65);
    xs = linspace(min(ds)-0.3, max(ds)+0.3, 20);
    plot(xs, results.linear_fit(1) + results.linear_fit(2)*xs, 'k-', 'LineWidth', 1.6);
    yline(0, 'k:', 'LineWidth', 1);
    xlabel('Change in number of singleton ANSPs');
    ylabel('Change in inter-ANSP handover rate (pp)');
    title(sprintf('Each station addition (n = %d)', numel(ds)), 'FontWeight','bold');
    legend({'network improved','network got worse','linear fit'}, 'Location','northwest','FontSize',8);
    grid on; box off;
    xticks(unique(ds));

    % ── RIGHT: group means ──
    subplot(1,2,2); hold on;
    vals = [g.mean_delta];
    cols = [0.85 0.25 0.20; 0.20 0.60 0.35; 0.30 0.45 0.75];
    for i = 1:numel(vals)
        bar(i, vals(i), 0.55, 'FaceColor', cols(i,:), 'FaceAlpha', 0.7, ...
            'EdgeColor', cols(i,:), 'LineWidth', 1.2);
    end
    yline(0, 'k-', 'LineWidth', 1);
    for i = 1:numel(vals)
        off = 0.35; if vals(i) < 0, off = -0.75; end
        text(i, vals(i) + off, sprintf('%.0f%% worse\n(n=%d)', g(i).pct_worse, g(i).n), ...
            'HorizontalAlignment','center','FontWeight','bold','FontSize',9);
    end
    % One line per tick label: MATLAB flattens embedded \n into extra ticks.
    set(gca,'XTick',1:numel(vals),'XTickLabel', ...
        {'creates one', 'no change', 'removes one'});
    ylabel('Mean change in inter-ANSP rate (pp)');
    title('Adding one station that... (singleton ANSPs)', 'FontWeight','bold');
    grid on; box off;
    ylim([min(vals)-2.5, max(vals)+2.5]);

    sgtitle('An ANSP with exactly one station is a forced-handover island', ...
        'FontWeight','bold','FontSize',13);

    exportgraphics(fig, fullfile(config.output_figures, 'm9_singleton_mechanism.png'), 'Resolution', 150);
    close(fig);

    fprintf('[M9v] Figure written to %s\n', fullfile(config.output_figures, 'm9_singleton_mechanism.png'));

end
