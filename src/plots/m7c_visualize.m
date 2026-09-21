function m7c_visualize(results, config)
% M7C_VISUALIZE  Throughput against each swept link-budget parameter, one
%   panel per sweep, with the ranking-stability verdict in each title.
%   OUTPUT: results/figures/m7c_sensitivity.png
    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
    n = numel(results);
    fig = figure('Visible','off','Position',[100 100 1250 340*ceil(n/2)]);
    for s = 1:n
        subplot(ceil(n/2), 2, s); hold on;
        for i = 1:size(results(s).throughput,1)
            plot(results(s).values, results(s).throughput(i,:), '-o', 'LineWidth', 1.6, 'MarkerSize', 4);
        end
        xlabel(results(s).label); ylabel('Throughput (kbit/s)');
        title(sprintf('%s  [ranking: %s]', results(s).label, ...
            ternary(results(s).rank_stable, 'stable', 'CHANGES')), 'FontSize', 9);
        if s == 1
            legend(results(s).topologies, 'Location','southwest','Interpreter','none','FontSize',7);
        end
        grid on; box off;
    end
    n_stable = sum([results.rank_stable]);
    sgtitle(sprintf(['Link-budget sensitivity: throughput moves in every sweep; ' ...
        'the topology ordering survives %d of %d'], n_stable, n), 'FontWeight','bold');
    exportgraphics(fig, fullfile(config.output_figures, 'm7c_sensitivity.png'), 'Resolution', 150);
    close(fig);
end
