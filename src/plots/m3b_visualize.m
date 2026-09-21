% M3B_VISUALIZE  Headline figure: does ANSP-aware siting help?
%   Plots hotspot (border-crossing) coverage vs N for three placement
%   methods: ANSP-aware (M3b), naive traffic-only (M3) and the textbook
%   uniform hex grid (M3c), plus a bar chart of how many stations each
%   method needs to match naive's best-ever coverage. Uses the conservative
%   scenario only, where the aware-vs-naive advantage is monotonic in N.
%   Inputs : results_m3b (m3b_ansp_aware_topology.m), results_m3c
%            (m3c_literature_grid.m), config.
%   Outputs: m3b_hotspot_improvement.png, m3b_stations_needed.png under
%            config.output_figures.
function m3b_visualize(results_m3b, results_m3c, config)

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    plot_hotspot_improvement(results_m3b.conservative, results_m3c.conservative, ...
        results_m3b.fade_margin_db_hi, config);
    plot_stations_needed(results_m3b.conservative, results_m3c.conservative, ...
        results_m3b.fade_margin_db_hi, config);
    fprintf('[M3b-VIZ] Saved 2 figures to %s\n', config.output_figures);

end


% ── Coverage vs N, aware/naive gap shaded, callout where aware first matches
% naive's best-ever result (naive is non-decreasing in N, so max is at N=n_max) ──
function plot_hotspot_improvement(scen, lit_scen, F_db, config)

    n = numel(scen.hotspot_coverage_pct);
    x = (1:n)';
    aware = scen.hotspot_coverage_pct;
    naive = scen.hotspot_coverage_naive;
    lit   = lit_scen.hotspot_coverage_pct;      % may be shorter if the hex grid ran out of valid sites
    x_lit = (1:numel(lit))';

    % Colours: green = the option argued for, blue = baseline hue shared with M3,
    % gray = least relevant curve, accent orange reserved for annotations only.
    green  = [0.047 0.639 0.047];
    blue   = [0.224 0.529 0.898];
    gray   = [0.55 0.55 0.55];
    accent = [0.85 0.33 0.10];

    fig = figure('Visible', 'off', 'Position', [100 100 850 550]);
    hold on;

    fill([x; flipud(x)], [aware; flipud(naive)], green, 'FaceAlpha', 0.15, 'EdgeColor', 'none');

    h_naive = plot(x, naive, '--o', 'LineWidth', 1.3, 'MarkerSize', 5, 'Color', blue);
    h_lit   = plot(x_lit, lit, ':^', 'LineWidth', 1.3, 'MarkerSize', 5, 'Color', gray);
    h_aware = plot(x, aware, '-o', 'LineWidth', 2, 'MarkerSize', 6, 'Color', green, 'MarkerFaceColor', green);

    naive_max = naive(end);
    n_match = find(aware >= naive_max, 1);
    if ~isempty(n_match) && n_match < n

        % Reference segment spans only [n_match, n], the range being compared.
        plot([n_match, n], [naive_max, naive_max], 'LineStyle', '--', ...
            'Color', accent, 'LineWidth', 1.1);
        plot(n, naive_max, 'o', 'MarkerSize', 8, 'MarkerFaceColor', blue, ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1.2);
        text(n - 0.4, naive_max + 6, sprintf('%.1f%%', naive_max), ...
            'FontSize', 9.5, 'Color', blue, 'HorizontalAlignment', 'right');

        plot(n_match, aware(n_match), 'o', 'MarkerSize', 11, ...
            'MarkerFaceColor', accent, 'MarkerEdgeColor', 'w', 'LineWidth', 1.4);

        % Callout sits in the empty upper-left region with a leader line to the point.
        callout_x = 1.3; callout_y = 82;
        plot([callout_x + 0.3, n_match - 0.3], [callout_y - 5, aware(n_match) + 4], ...
            'Color', accent, 'LineWidth', 1.0);
        text(callout_x, callout_y, sprintf(['At N=%d, ANSP-aware placement already\n' ...
            'matches naive''s best case (N=%d, %.1f%%)'], n_match, n, naive_max), ...
            'FontSize', 9.5, 'FontWeight', 'bold', 'Color', accent, ...
            'VerticalAlignment', 'top');
    end

    xlabel('Number of ground stations (N)');
    ylabel('ANSP border-crossing coverage (%)');
    title('Border-crossing coverage by placement strategy', 'FontWeight', 'bold');
    subtitle(sprintf('Conservative scenario, F = %.1f dB', F_db));
    legend([h_aware, h_naive, h_lit], ...
        {'ANSP-aware (M3b)', 'Naive, traffic-only (M3)', 'Uniform hex grid (textbook, M3c)'}, ...
        'Location', 'southeast', 'Box', 'off');
    grid on; box off; xlim([1, n]); ylim([0, 100]);

    exportgraphics(fig, fullfile(config.output_figures, 'm3b_hotspot_improvement.png'), 'Resolution', 150);
    close(fig);

end


% ── Stations needed by each method to reach naive's best-ever hotspot coverage ──
function plot_stations_needed(scen, lit_scen, F_db, config)

    aware = scen.hotspot_coverage_pct;
    naive = scen.hotspot_coverage_naive;
    lit   = lit_scen.hotspot_coverage_pct;
    n_max = numel(aware);

    target = naive(end);   % naive's best-ever result (non-decreasing in N)

    n_aware = find(aware >= target, 1);
    n_naive = n_max;
    n_lit   = find(lit >= target, 1);
    lit_reaches = ~isempty(n_lit);
    if lit_reaches
        lit_bar = n_lit;
        lit_label = sprintf('N = %d', n_lit);
    else
        lit_bar = numel(lit);
        lit_label = sprintf('never reaches (max %.1f%% at N=%d)', max(lit), numel(lit));
    end

    green  = [0.047 0.639 0.047];
    blue   = [0.224 0.529 0.898];
    orange = [0.851 0.349 0.149];
    gray   = [0.55 0.55 0.55];

    fig = figure('Visible', 'off', 'Position', [100 100 850 450]);
    hold on;

    y = [3 2 1];
    barh(y(1), n_aware, 0.55, 'FaceColor', green, 'EdgeColor', 'none');
    barh(y(2), n_naive, 0.55, 'FaceColor', blue, 'EdgeColor', 'none');
    if lit_reaches
        barh(y(3), lit_bar, 0.55, 'FaceColor', orange, 'EdgeColor', 'none');
    else
        barh(y(3), lit_bar, 0.55, 'FaceColor', orange, 'FaceAlpha', 0.35, ...
            'EdgeColor', orange, 'LineWidth', 1.3, 'LineStyle', '--');
    end

    text(n_aware + 0.4, y(1), sprintf('N = %d', n_aware), 'FontSize', 13, ...
        'FontWeight', 'bold', 'Color', green, 'VerticalAlignment', 'middle');
    text(n_naive + 0.4, y(2), sprintf('N = %d', n_naive), 'FontSize', 13, ...
        'FontWeight', 'bold', 'Color', blue, 'VerticalAlignment', 'middle');
    text(lit_bar + 0.4, y(3), lit_label, 'FontSize', 11, ...
        'FontWeight', 'bold', 'Color', orange, 'VerticalAlignment', 'middle');

    % Bracket + headline reduction between the top two bars.
    y_gap = 2.5;
    plot([n_aware n_naive], [y_gap y_gap], 'Color', gray, 'LineWidth', 1.2);
    plot([n_aware n_aware], [y_gap-0.09 y_gap+0.09], 'Color', gray, 'LineWidth', 1.2);
    plot([n_naive n_naive], [y_gap-0.09 y_gap+0.09], 'Color', gray, 'LineWidth', 1.2);
    pct_reduction = 100 * (n_naive - n_aware) / n_naive;
    text(mean([n_aware n_naive]), y_gap, sprintf('  %.0f%% fewer stations  ', pct_reduction), ...
        'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.2 0.5 0.2], ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'BackgroundColor', 'w', 'Margin', 1);

    yticks(sort(y));
    yticklabels({'Uniform hex grid (textbook, M3c)', ...
        'Naive, traffic-only (M3)', 'ANSP-aware (M3b)'});
    ylim([0.3 3.7]);
    xlim([0, n_max + 10]);
    xlabel('Number of stations needed');
    title('How many stations does each method need for the same result?', 'FontWeight', 'bold');
    subtitle({sprintf('Stations needed to match naive''s best-ever coverage (%.1f%%)', target), ...
        sprintf('conservative scenario, F = %.1f dB', F_db)});
    grid on; ax = gca; ax.YGrid = 'off'; box off;

    exportgraphics(fig, fullfile(config.output_figures, 'm3b_stations_needed.png'), 'Resolution', 150);
    close(fig);

end