% M3D_VISUALIZE  Trade-off figure: traffic coverage vs border coverage.
%   One point per swept hotspot_weight_alpha, both coverages read at the
%   same fixed N (config.pareto_eval_N), so the frontier shows what a network
%   of that size can trade between the two objectives. The naive (M3)
%   reference is a separate fixed marker, not part of the alpha sweep (see
%   the candidate-pool caveat in m3d_pareto_frontier.m). Only the two alpha
%   endpoints are labelled; alpha=1 (the value used in M3b/M4/M5/M6) gets a
%   distinct marker and callout.
%   Inputs : results (m3d_pareto_frontier.m), config.
%   Output : m3d_pareto_frontier.png under config.output_figures.
function m3d_visualize(results, config)

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    plot_pareto_frontier(results, config);
    fprintf('[M3d-VIZ] Saved 1 figure to %s\n', config.output_figures);

end


function plot_pareto_frontier(results, config)

    sweep = results.alpha_sweep;
    N = results.pareto_eval_N;
    n_alpha = numel(sweep);

    x = zeros(n_alpha,1);   % traffic coverage at N
    y = zeros(n_alpha,1);   % hotspot coverage at N
    a = zeros(n_alpha,1);
    for k = 1:n_alpha
        x(k) = sweep(k).coverage_pct(N);
        y(k) = sweep(k).hotspot_coverage_pct(N);
        a(k) = sweep(k).alpha;
    end
    [a, order] = sort(a);
    x = x(order); y = y(order);

    x_naive = results.naive_reference.coverage_pct(N);
    y_naive = results.naive_reference.hotspot_coverage_pct(N);

    gray_pt   = [0.55 0.55 0.55];
    gray_txt  = [0.25 0.25 0.25];
    accent    = [0.85 0.33 0.10];
    naive_col = [0.3 0.3 0.3];

    fig = figure('Visible', 'off', 'Position', [100 100 820 620]);
    hold on;

    plot(x, y, '-', 'Color', gray_pt, 'LineWidth', 1.3);
    scatter(x, y, 70, a, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 1);
    colormap(gca, winter);
    cb = colorbar;
    cb.Label.String = 'alpha (weight on border coverage)';

    % Label only the endpoints; the colour scale carries the rest.
    [~, i_min] = min(a);
    [~, i_max] = max(a);
    text(x(i_min), y(i_min) + 2.5, sprintf('\\alpha=%.3g', a(i_min)), ...
        'FontSize', 9, 'HorizontalAlignment', 'center', 'Color', gray_txt);
    text(x(i_max), y(i_max) + 2.5, sprintf('\\alpha=%.3g', a(i_max)), ...
        'FontSize', 9, 'HorizontalAlignment', 'center', 'Color', gray_txt);

    % Highlight alpha=1 (diamond) with a leader line into the empty upper-right.
    [dist_to_one, i_one] = min(abs(a - 1));
    if dist_to_one < 1e-6
        plot(x(i_one), y(i_one), 'd', 'MarkerSize', 12, 'MarkerFaceColor', accent, ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1.3);
        callout_x = x(i_one) - 0.5; callout_y = max(y) - 4.5;
        plot([callout_x, x(i_one) + 0.1], [callout_y - 5.5, y(i_one) + 2], ...
            'Color', accent, 'LineWidth', 1.0);
        text(callout_x - 0.5, callout_y, sprintf('\\alpha=1 (used in\nM3b/M4/M5/M6)'), ...
            'FontSize', 9.5, 'FontWeight', 'bold', 'Color', accent, 'VerticalAlignment', 'bottom');
    end

    plot(x_naive, y_naive, 'p', 'MarkerSize', 16, 'MarkerFaceColor', naive_col, ...
        'MarkerEdgeColor', 'w', 'LineWidth', 1.3);
    text(x_naive, y_naive - 4, 'naive (M3)', 'FontSize', 10, 'FontWeight', 'bold', ...
        'Color', naive_col, 'HorizontalAlignment', 'center');

    % Diminishing-returns zone: the top two alpha values barely move border
    % coverage while still giving up traffic coverage. Callout in the empty bottom-left.
    if n_alpha >= 2
        plot(x(end-1:end), y(end-1:end), '-', 'Color', accent, 'LineWidth', 3, ...
            'Marker', 'none');
        dr_gain_y = y(end) - y(end-1);
        dr_cost_x = x(end-1) - x(end);
        callout2_x = min(x) + 0.3; callout2_y = min([y; y_naive]) + 2;
        plot([callout2_x + 1.2, x(end-1) - 0.15], [callout2_y + 3, y(end-1) - 2], ...
            'Color', accent, 'LineWidth', 1.0);
        text(callout2_x, callout2_y, sprintf(['Diminishing returns beyond \\alpha=%.3g:\n' ...
            'only +%.1fpp border coverage for\n-%.1fpp traffic coverage'], ...
            a(end-1), dr_gain_y, dr_cost_x), ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', accent, 'VerticalAlignment', 'bottom');
    end

    xlabel(sprintf('Traffic coverage at N=%d (%%)', N));
    ylabel(sprintf('Border-crossing coverage at N=%d (%%)', N));
    title('Trade-off between traffic coverage and border protection', 'FontWeight', 'bold');
    subtitle(sprintf('N=%d stations, border weight (\\alpha) swept from %.2g to %.2g', N, min(a), max(a)));
    grid on; box off;
    ylim([min([y; y_naive]) - 8, max(y) + 10]);   % headroom so the top label clears the title

    exportgraphics(fig, fullfile(config.output_figures, 'm3d_pareto_frontier.png'), 'Resolution', 150);
    close(fig);

end