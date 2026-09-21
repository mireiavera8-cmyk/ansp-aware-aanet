% M3E_VISUALIZE  Worst-case pinch-point exposure: minimax vs sum objective.
%   Plots the worst pinch-point exposure vs N for the minimax (k-center)
%   placement against M3b's sum-optimising placement replayed under the
%   same worst-case metric, with the gap shaded and a callout at N=12 (the
%   station count M4/M5/M6 build on).
%   Inputs : results (m3e_minimax_topology.m), config.
%   Output : m3e_worst_case_comparison.png under config.output_figures.
function m3e_visualize(results, config)

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    plot_worst_case_comparison(results, config);
    fprintf('[M3e-VIZ] Saved 1 figure to %s\n', config.output_figures);

end


function plot_worst_case_comparison(results, config)

    n = numel(results.max_risk_pct);
    x = (1:n)';
    mclp   = results.mclp_reference.max_risk_pct;
    mmax   = results.max_risk_pct;

    green  = [0.047 0.639 0.047];   % minimax (the option argued for)
    blue   = [0.224 0.529 0.898];   % M3b / MCLP reference
    accent = [0.85 0.33 0.10];      % callout only, never a curve

    fig = figure('Visible', 'off', 'Position', [100 100 850 560]);
    hold on;

    fill([x; flipud(x)], [mclp; flipud(mmax)], green, 'FaceAlpha', 0.10, 'EdgeColor', 'none');

    h_mclp = plot(x, mclp, '--o', 'LineWidth', 1.5, 'MarkerSize', 5, 'Color', blue);
    h_mmax = plot(x, mmax, '-o', 'LineWidth', 2, 'MarkerSize', 6, 'Color', green, 'MarkerFaceColor', green);

    % N=12 callout, values read from the curves; placed in the empty bottom-right.
    N_ref = 12;
    if N_ref <= n
        mclp_ref = mclp(N_ref);
        mmax_ref = mmax(N_ref);

        plot([N_ref N_ref], [0 100], ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.9);
        plot(N_ref, mclp_ref, 'o', 'MarkerSize', 9, 'MarkerFaceColor', blue, ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1.2);
        plot(N_ref, mmax_ref, 'o', 'MarkerSize', 11, 'MarkerFaceColor', accent, ...
            'MarkerEdgeColor', 'w', 'LineWidth', 1.4);

        callout_x = 13.5; callout_y = 22;
        plot([callout_x, N_ref + 0.3], [callout_y + 10, mmax_ref - 3], 'Color', accent, 'LineWidth', 1.0);
        text(callout_x, callout_y, sprintf([...
            'At N=%d (the network size used throughout):\n' ...
            'ANSP-aware (sum objective): worst pinch-point at %.0f%% exposed\n' ...
            'Minimax: already at its structural floor, %.0f%%'], ...
            N_ref, mclp_ref, mmax_ref), ...
            'FontSize', 9.5, 'FontWeight', 'bold', 'Color', accent, 'VerticalAlignment', 'top');
    end

    xlabel('Number of ground stations (N)');
    ylabel('Worst pinch-point exposed (%, no same-provider dual coverage)');
    title('Does minimising the worst case actually help the worst case?');
    subtitle(sprintf('Wide coverage band (F=%.1f dB) — same coverage model, different selection rule', ...
        results.fade_margin_db_hi));
    legend([h_mmax, h_mclp], ...
        {'Minimax (k-center, this work)', 'ANSP-aware, sum objective'}, ...
        'Location', 'northeast', 'Box', 'off');
    grid on; box off; xlim([1, n]); ylim([0, 100]);

    exportgraphics(fig, fullfile(config.output_figures, 'm3e_worst_case_comparison.png'), 'Resolution', 150);
    close(fig);

end