% M8_VISUALIZE  Figures for the matched-N topology sweep.
%   Plots inter-ANSP handover rate vs N and served traffic vs N for every
%   constrained topology on shared axes (the searched topology's separate
%   N=20 result is an isolated marker, not joined to the N=12 construction
%   prefix), and the failure concentration at matched N against the
%   even-spread floor of 100/N. Pre-constraint baselines are excluded since
%   they were not held to the same feasibility constraints.
%   Inputs : results (m8_topology_sweep.m), config; optionally reads
%            results/m3_optimal_search_Nsweep.mat (search_optimized_topology.m).
%   Outputs: m8_pct_inter_curves.png, m8_served_curves.png,
%            m8_concentration.png under config.output_figures.

function m8_visualize(results, config)

    fprintf('[M8v] Rendering topology-sweep figures...\n');
    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end

    sweep  = results.sweep;
    N_LIST = results.N_LIST;
    n = numel(sweep);

    % Pre-constraint variants are excluded from the comparison figures.
    is_parity = contains({sweep.name}, 'pre-constraint');

    % Explicit palette (lines() repeats after 7) plus a per-series marker so
    % every curve is separable by hue and marker. Rows 9-11 kept so indices line up.
    cmap = [0.00 0.45 0.74;   % 1  Naive            blue
            0.85 0.33 0.10;   % 2  ANSP-aware       orange
            0.93 0.69 0.13;   % 3  Geometric        amber
            0.49 0.18 0.56;   % 4  Traffic-weighted purple
            0.20 0.60 0.20;   % 5  Minimax          green
            0.30 0.75 0.93;   % 6  Resilient        cyan
            0.80 0.15 0.55;   % 7  Co-location      magenta
            0.00 0.00 0.00;   % 8  Optimized        black
            0.85 0.33 0.10;   % 9  Geometric pre
            0.93 0.69 0.13;   % 10 Traffic-w pre
            0.80 0.15 0.55];  % 11 Co-location pre
    if n > size(cmap,1), cmap = [cmap; lines(n - size(cmap,1))]; end
    mkset = {'o','s','^','v','d','>','<','p','s','s','s'};

    % The registry calls the coverage-greedy baseline "Naive"; the thesis calls it "Traffic-only".
    disp_name = @(s) strrep(s, 'Naive', 'Traffic-only');

    % ── 1. pct_inter vs N ──
    fig = figure('Visible','off','Position',[100 100 1100 640]);
    hold on; h = []; lbl = {};
    for i = 1:n
        v = sweep(i).pct_inter_hi;
        if all(isnan(v)) || is_parity(i), continue; end
        st = '-'; lw = 1.8; mk = mkset{min(i,numel(mkset))};
        h(end+1) = plot(N_LIST, v, st, 'Color', cmap(min(i,size(cmap,1)),:), ...
            'LineWidth', lw, 'Marker', mk, 'MarkerSize', 4.5); %#ok<AGROW>
        lbl{end+1} = disp_name(sweep(i).name); %#ok<AGROW>
    end
    % Searched topologies exist only at the N they were searched at: drawn as
    % isolated markers so no intermediate counts are implied.
    ns_file = fullfile(config.output_data, 'm3_optimal_search_Nsweep.mat');
    if exist(ns_file, 'file')
        NS = load(ns_file, 'sweep');
        for k = 1:numel(NS.sweep)
            s = NS.sweep(k);
            feas = s.pool_coverage >= s.coverage_floor;
            if ~any(feas), continue; end
            v = s.pool_pct_inter; v(~feas) = Inf;
            [best, ~] = min(v);
            h(end+1) = plot(s.N, best, 'p', 'MarkerSize', 14, ...
                'MarkerFaceColor', cmap(8,:), 'MarkerEdgeColor', 'w', 'LineWidth', 1.2); %#ok<AGROW>
            lbl{end+1} = sprintf('Optimized, searched at N=%d', s.N); %#ok<AGROW>
        end
    end

    xlabel('Number of ground stations (N)');
    ylabel('Inter-ANSP handovers (% of all handovers)');
    title('Inter-ANSP handover rate across the full station-count sweep', 'FontWeight','bold');
    subtitle('F = 5.5 dB. Lower is better. Every series under identical feasibility constraints.', ...
        'Interpreter','none','FontSize',9);
    legend(h, lbl, 'Location','eastoutside', 'Interpreter','none', 'FontSize',8);
    grid on; box off; xlim([min(N_LIST) max(N_LIST)]);
    exportgraphics(fig, fullfile(config.output_figures, 'm8_pct_inter_curves.png'), 'Resolution', 150);
    close(fig);

    % ── 2. served traffic vs N ──
    fig = figure('Visible','off','Position',[100 100 1100 640]);
    hold on; h = []; lbl = {};
    for i = 1:n
        v = sweep(i).served_hi;
        if all(isnan(v)) || is_parity(i), continue; end
        st = '-'; lw = 1.8; mk = mkset{min(i,numel(mkset))};
        h(end+1) = plot(N_LIST, v, st, 'Color', cmap(min(i,size(cmap,1)),:), ...
            'LineWidth', lw, 'Marker', mk, 'MarkerSize', 4.5); %#ok<AGROW>
        lbl{end+1} = disp_name(sweep(i).name); %#ok<AGROW>
    end
    if exist(ns_file, 'file')
        for k = 1:numel(NS.sweep)
            s = NS.sweep(k);
            feas = s.pool_coverage >= s.coverage_floor;
            if ~any(feas), continue; end
            v = s.pool_pct_inter; v(~feas) = Inf;
            [~, w] = min(v);                      % the same network figure 1 marks
            h(end+1) = plot(s.N, s.pool_served(w), 'p', 'MarkerSize', 14, ...
                'MarkerFaceColor', cmap(8,:), 'MarkerEdgeColor', 'w', 'LineWidth', 1.2); %#ok<AGROW>
            lbl{end+1} = sprintf('Optimized, searched at N=%d', s.N); %#ok<AGROW>
        end
    end

    xlabel('Number of ground stations (N)');
    ylabel('Traffic served (% of aircraft-ticks)');
    title('Served traffic across the station-count sweep', 'FontWeight','bold');
    subtitle('F = 5.5 dB. Measured identically for every topology from M4 served ticks.', ...
        'Interpreter','none','FontSize',10);
    legend(h, lbl, 'Location','eastoutside', 'Interpreter','none', 'FontSize',8);
    grid on; box off; xlim([min(N_LIST) max(N_LIST)]);
    exportgraphics(fig, fullfile(config.output_figures, 'm8_served_curves.png'), 'Resolution', 150);
    close(fig);

    % ── 3. concentration at matched N ──
    c = results.concentration;
    if ~isempty(c)
        [~, ord] = sort([c.concentration_ratio], 'ascend');
        c = c(ord);
        fig = figure('Visible','off','Position',[100 100 1000 600]);
        hold on;
        bar(1:numel(c), [c.top1_share_pct], 0.55, 'FaceColor',[0.224 0.529 0.898], ...
            'FaceAlpha',0.55, 'EdgeColor',[0.224 0.529 0.898], 'LineWidth',1.2);
        plot(1:numel(c), [c.even_spread_pct], 'k--', 'LineWidth',1.5);
        for i = 1:numel(c)
            text(i, c(i).top1_share_pct + 0.5, sprintf('%.2fx', c(i).concentration_ratio), ...
                'HorizontalAlignment','center','FontWeight','bold','FontSize',9);
        end
        set(gca,'XTick',1:numel(c),'XTickLabel', ...
            arrayfun(@(x) sprintf('%s (N=%d)', disp_name(x.name), x.N), c, 'UniformOutput', false), ...
            'TickLabelInterpreter','none');
        xtickangle(30);
        ylabel('Top-1 station share of forced inter-ANSP exposure (%)');
        title('Failure concentration at matched station count', 'FontWeight','bold');
        subtitle('Dashed line = even-spread floor (100/N). Labels give the ratio to that floor.', ...
            'Interpreter','none','FontSize',10);
        legend({'Top-1 share','Even spread (100/N)'}, 'Location','northwest');
        grid on; box off;
        exportgraphics(fig, fullfile(config.output_figures, 'm8_concentration.png'), 'Resolution', 150);
        close(fig);
    end

    fprintf('[M8v] Figures written to %s\n', config.output_figures);

end
