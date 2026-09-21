% M6_VISUALIZE  Before/after figures for the M6 backup station and M6b interconnection.
%   Plots a per-station dumbbell of the forced inter-provider share before
%   vs after adding the M6 backup station, and the cumulative M6b mitigation
%   curve as real-world ANSP pairs are interconnected in order of M2 crossing
%   volume. Uses the conservative fade margin (index 2 of
%   config.ci_fade_margin_db_list) throughout, matching the M6/M6b console.
%   Inputs : m5_before, m5_after (m5_station_failure.m results for the
%            topology without/with the backup), m6_report
%            (m6_redundancy_placement.m, needs .found=true), m6b_report
%            (m6b_interconnection_scenario.m), config.
%   Outputs: m6_redundancy_before_after.png, m6b_interconnection_curve.png
%            under config.output_figures.

function m6_visualize(m5_before, m5_after, m6_report, m6b_report, config)

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    F_db = config.ci_fade_margin_db_list(2);

    plot_redundancy_before_after(m5_before.by_margin(2).per_station, m5_after.by_margin(2).per_station, F_db, config);
    plot_interconnection_curve(m6b_report, m6_report.risky_ansp, F_db, config);

    fprintf('[M6-VIZ] Saved 2 figures to %s\n', config.output_figures);

end


% ── Dumbbell: pct_forced_inter per station, before vs after the backup.
% Green after-dot = improved, orange = got worse; the new station gets its own row ──
function plot_redundancy_before_after(before, after, F_db, config)

    n_before = numel(before);
    pct_before = [before.pct_forced_inter];
    pct_after  = [after(1:n_before).pct_forced_inter];

    green  = [0.047 0.639 0.047];
    orange = [0.851 0.349 0.149];
    blue   = [0.224 0.529 0.898];
    gray   = [0.55 0.55 0.55];

    [~, ord] = sort(pct_before, 'descend');   % rank 1 = worst before

    fig = figure('Visible', 'off', 'Position', [100 100 900 560]);
    hold on;

    label_all = cell(n_before + 1, 1);
    for rank = 1:n_before
        k = ord(rank);
        y = n_before - rank + 1;   % rank 1 (worst) at the top
        plot([pct_before(k), pct_after(k)], [y y], '-', 'Color', gray, 'LineWidth', 1.5);
        plot(pct_before(k), y, 'o', 'MarkerSize', 7, 'MarkerFaceColor', 'none', ...
            'MarkerEdgeColor', gray, 'LineWidth', 1.5);
        if pct_after(k) <= pct_before(k)
            after_color = green;
        else
            after_color = orange;
        end
        plot(pct_after(k), y, 'o', 'MarkerSize', 10, 'MarkerFaceColor', after_color, ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1);
        label_all{y+1} = sprintf('#%d %s', k, before(k).ansp_name);
    end

    new_pct = after(end).pct_forced_inter;
    plot(new_pct, 0, 'p', 'MarkerSize', 13, 'MarkerFaceColor', blue, 'MarkerEdgeColor', 'w', 'LineWidth', 1);
    label_all{1} = sprintf('#%d %s (NEW)', numel(after), after(end).ansp_name);

    h_before   = plot(nan, nan, 'o', 'MarkerSize', 7, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', gray, 'LineWidth', 1.5);
    h_improved = plot(nan, nan, 'o', 'MarkerSize', 10, 'MarkerFaceColor', green, 'MarkerEdgeColor', 'w');
    h_worsened = plot(nan, nan, 'o', 'MarkerSize', 10, 'MarkerFaceColor', orange, 'MarkerEdgeColor', 'w');
    h_new      = plot(nan, nan, 'p', 'MarkerSize', 13, 'MarkerFaceColor', blue, 'MarkerEdgeColor', 'w');

    yticks(0:n_before);
    yticklabels(label_all);
    ylim([-0.7, n_before + 0.7]);
    xlim([0, 100]);
    xlabel('% of served traffic redirected across a provider boundary if the station fails');
    title('Does the backup station solve the problem, or only move it?');
    subtitle(sprintf('Per-station forced inter-provider share, before vs after the reactive backup — wide coverage band (F=%.1f dB)', F_db));
    legend([h_before, h_improved, h_worsened, h_new], ...
        {'Before backup', 'After — improved', 'After — got worse', 'New backup station'}, ...
        'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
    grid on; ax = gca; ax.YGrid = 'off'; box off;

    exportgraphics(fig, fullfile(config.output_figures, 'm6_redundancy_before_after.png'), 'Resolution', 150);
    close(fig);

end


% ── Cumulative % of forced-inter exposure neutralised vs interconnected pairs;
% vertical markers show where the risky ANSP's pairs fall in the rollout order ──
function plot_interconnection_curve(report, risky_ansp, F_db, config)

    green  = [0.047 0.639 0.047];
    orange = [0.851 0.349 0.149];

    curve = report.mitigation_curve_pct;
    n_pairs = numel(curve);
    x = (1:n_pairs)';

    fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
    hold on;

    plot(x, curve, '-o', 'Color', green, 'MarkerFaceColor', green, 'MarkerSize', 5, 'LineWidth', 2);

    checkpoints = unique(min(n_pairs, [1, 3, 5, 10, n_pairs]));
    for K = checkpoints
        text(K + 0.15, curve(K) + 2, sprintf('%.0f%%', curve(K)), 'FontSize', 9, 'FontWeight', 'bold');
        plot(K, curve(K), 'o', 'MarkerSize', 8, 'MarkerFaceColor', green, 'MarkerEdgeColor', 'w');
    end

    % Only the pairs involving the ANSP M6 flagged as riskiest are highlighted.
    matches = struct('ansp_a', {}, 'ansp_b', {}, 'forced_inter_count', {}, 'real_world_rank', {});
    for i = 1:numel(report.top_m5_pairs_ranked)
        p = report.top_m5_pairs_ranked(i);
        if isnan(p.real_world_rank), continue; end
        if strcmp(p.ansp_a, risky_ansp) || strcmp(p.ansp_b, risky_ansp)
            matches(end+1) = p; %#ok<AGROW>
        end
    end

    label_heights = [82, 55, 28];   % staggered so close-together ranks don't overlap
    for i = 1:numel(matches)
        p = matches(i);
        xline(p.real_world_rank, ':', 'Color', orange, 'LineWidth', 1.2);
        y_lab = label_heights(min(i, numel(label_heights)));
        text(p.real_world_rank + 0.25, y_lab, sprintf('%s\\leftrightarrow%s\n(rank %d of %d)', ...
            p.ansp_a, p.ansp_b, p.real_world_rank, n_pairs), ...
            'Color', orange, 'FontSize', 9, 'FontWeight', 'bold');
    end

    xlabel('Provider pairs interconnected (order: real crossing volume)');
    ylabel('% of forced inter-provider exposure neutralised');
    title('How many interconnection agreements does it take to neutralise the exposure?');
    subtitle(sprintf('Cumulative curve, %d forced inter-provider aircraft-ticks in total — %s pairs highlighted — F=%.1f dB', ...
        report.total_forced_inter_ticks, risky_ansp, F_db));
    grid on; box off; xlim([0.5, n_pairs + 0.5]); ylim([0, 100]);

    exportgraphics(fig, fullfile(config.output_figures, 'm6b_interconnection_curve.png'), 'Resolution', 150);
    close(fig);

end
