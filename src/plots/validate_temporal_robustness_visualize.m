% VALIDATE_TEMPORAL_ROBUSTNESS_VISUALIZE  Out-of-sample consistency figure.
%   Three grouped-bar panels comparing the original design hour against an
%   independent validation hour: M2/M2b border-crossing exposure, M4
%   inter-ANSP handover share at N=12, and M5 top-1 failure concentration.
%   Colour encodes the dataset (blue = original, amber = validation), not
%   the topology, since each bar pair is one topology compared across time.
%   Reads  : results/validation/temporal_robustness_comparison.mat
%            (validate_temporal_robustness.m).
%   Writes : temporal_robustness_check.png under config.output_figures.
function validate_temporal_robustness_visualize()

    config = setup_config();
    S = load(fullfile(config.output_data, 'validation', 'temporal_robustness_comparison.mat'), 'consistency');
    c = S.consistency;

    if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end

    blue  = [0.145 0.412 0.702];   % original design hour
    amber = [0.796 0.482 0.043];   % validation hour (warm/cool pair, CVD-safe)
    ink   = [0.10 0.10 0.10];
    pagebg = [1 1 1];

    % Background set explicitly: tiledlayout's canvas does not always inherit it.
    fig = figure('Visible', 'off', 'Position', [100 100 1500 520], 'Color', pagebg);
    tl = tiledlayout(fig, 1, 3, 'Padding', 'loose', 'TileSpacing', 'loose');

    % ── Panel A: M2 / M2b descriptive consistency ──
    ax1 = nexttile(tl);
    labels_a = {'>=1 crossing (any)', 'MUAC >=3 crossings', 'non-MUAC >=3 crossings'};
    orig_a = [c.m2.pct_crossing_orig, c.m2b.muac_pct_high_orig, c.m2b.non_muac_pct_high_orig];
    val_a  = [c.m2.pct_crossing_val,  c.m2b.muac_pct_high_val,  c.m2b.non_muac_pct_high_val];
    grouped_bar(ax1, labels_a, orig_a, val_a, blue, amber, ink, ...
        'Aircraft (%)', 'Border-crossing exposure (M2 / M2b)');

    % Map internal strategy labels to the names the thesis uses.
    dn = @(s) strrep(strrep(s, 'Naive', 'Traffic-only'), 'Hex', 'Geometric lattice');

    % ── Panel B: M4 handover cost, same N=12 control ──
    ax2 = nexttile(tl);
    labels_b = arrayfun(@(i) sprintf('%s (N=%d)', dn(c.m4.topology{i}), c.m4.N(1)), ...
        1:numel(c.m4.topology), 'UniformOutput', false);
    grouped_bar(ax2, labels_b, c.m4.pct_inter_orig, c.m4.pct_inter_val, blue, amber, ink, ...
        'Inter-ANSP handovers (%)', 'Handover cost (M4), F = 5.5 dB');

    % ── Panel C: M5 failure-concentration, headline trio ──
    ax3 = nexttile(tl);
    labels_c = arrayfun(@(i) sprintf('%s (N=%d)', dn(c.m5.topology{i}), c.m5.N(i)), ...
        1:numel(c.m5.topology), 'UniformOutput', false);
    grouped_bar(ax3, labels_c, c.m5.top1_pct_orig, c.m5.top1_pct_val, blue, amber, ink, ...
        'Top-1 station share of failures (%)', 'Failure concentration (M5), F = 5.5 dB');

    lg = legend(ax3, {sprintf('Original (%s)', c.meta.orig_window), ...
                       sprintf('Validation (%s)', c.meta.val_window)}, ...
        'Orientation', 'horizontal', 'Box', 'off', 'TextColor', ink, 'Color', 'none');
    lg.Layout.Tile = 'south';

    t = title(tl, 'Temporal robustness check: same topologies, independent traffic sample', ...
        'FontWeight', 'bold', 'FontSize', 13);
    t.Color = ink;

    exportgraphics(fig, fullfile(config.output_figures, 'temporal_robustness_check.png'), 'Resolution', 150);
    close(fig);
    fprintf('[VIZ] Saved %s\n', fullfile(config.output_figures, 'temporal_robustness_check.png'));

end


% ── Two-series (orig/val) grouped bars with a value label on every bar ──
function grouped_bar(ax, labels, orig_vals, val_vals, blue, amber, ink, ylab, ttl)

    axes(ax); hold(ax, 'on');
    x = 1:numel(labels);
    b = bar(ax, x, [orig_vals(:), val_vals(:)], 0.75, 'EdgeColor', 'none');
    b(1).FaceColor = blue;
    b(2).FaceColor = amber;

    for i = 1:numel(x)
        xo = b(1).XEndPoints(i); xv = b(2).XEndPoints(i);
        text(ax, xo, orig_vals(i) + 1.5, sprintf('%.1f', orig_vals(i)), ...
            'HorizontalAlignment', 'center', 'FontSize', 8.5, 'Color', ink);
        text(ax, xv, val_vals(i) + 1.5, sprintf('%.1f', val_vals(i)), ...
            'HorizontalAlignment', 'center', 'FontSize', 8.5, 'Color', ink);
    end

    ax.XTick = x;
    ax.XTickLabel = labels;
    ax.XTickLabelRotation = 15;
    ax.XLim = [0.4, numel(x) + 0.6];
    ax.Color = [1 1 1];
    ax.XColor = ink; ax.YColor = ink;
    ax.GridColor = ink; ax.GridAlpha = 0.18;
    yl = ylabel(ax, ylab); yl.Color = ink;
    tt = title(ax, ttl, 'FontWeight', 'normal', 'FontSize', 10.5); tt.Color = ink;
    ymax = max([orig_vals(:); val_vals(:)]);
    ylim(ax, [0, ymax * 1.22 + 5]);
    grid(ax, 'on'); box(ax, 'off');
    ax.YGrid = 'on'; ax.XGrid = 'off';

end
