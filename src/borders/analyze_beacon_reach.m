% ANALYZE_BEACON_REACH  Can existing beacon sites reach the border pinch-points?
%   Read-only post-processing: loads the M2b pinch-point centroids
%   and the beacon register (config.dme_beacons) and reports the distance
%   from each pinch-point to the nearest reusable site against the nominal
%   cell radius, then plots crossings vs distance with every pinch-point
%   labelled. Chosen over a crossings-vs-1/d-score correlation (m2c), which
%   is weak and confounded by airport proximity; reach needs no
%   distributional assumption and is something a planner can act on.
%   Reads  : results/border_hotspots.mat.
%   Writes : m2c_beacon_reach.png under config.output_figures.
%   Usage  : analyze_beacon_reach
function analyze_beacon_reach()
addpath(fullfile(fileparts(mfilename('fullpath')), '..', '..')); init_paths();
config = setup_config();
S = load(fullfile(config.output_data, 'border_hotspots.mat')); bh = S.border_hotspots;
B = config.dme_beacons; names = config.dme_beacon_names;
km = 111.0;

n = numel(bh); R = config.gs_radius_km;
fprintf('Pinch-points: %d   beacons: %d   cell radius: %g km\n\n', n, size(B,1), R);

d_near = zeros(n,1); who = cell(n,1);
for h = 1:n
    la = bh(h).centroid_lat; lo = bh(h).centroid_lon;
    d = sqrt(((la-B(:,1))*km).^2 + ((lo-B(:,2))*km.*cosd(la)).^2);
    [d_near(h), j] = min(d);
    who{h} = names{j};
end

c = double([bh.count]');
[~,ord] = sort(c,'descend');
fprintf('%-22s %7s %10s %12s\n','pinch-point pair','cross','nearest','dist (km)');
for k = 1:n
    h = ord(k);
    fprintf('%-10s/%-11s %7d %10s %12.0f\n', bh(h).ansp_a, bh(h).ansp_b, ...
        bh(h).count, who{h}, d_near(h));
end

within = d_near <= R;
fprintf('\nWithin one cell radius (%g km) of a reusable beacon: %d of %d pinch-points\n', ...
    R, sum(within), n);
fprintf('  crossings they carry: %d of %d (%.1f%%)\n', ...
    sum(c(within)), sum(c), 100*sum(c(within))/sum(c));
fprintf('Beyond it: %d pinch-points carrying %d crossings (%.1f%%)\n', ...
    sum(~within), sum(c(~within)), 100*sum(c(~within))/sum(c));
fprintf('\nmedian distance to nearest beacon: %.0f km   (min %.0f, max %.0f)\n', ...
    median(d_near), min(d_near), max(d_near));

% ── FIGURE ──
try, theme('light'); catch, end %#ok<CTCH>
set(groot,'defaultFigureColor','w','defaultAxesColor','w', ...
          'defaultAxesXColor','k','defaultAxesYColor','k','defaultTextColor','k');
% Same short provider names and marker-area scaling as plot_corridor_map([], true),
% so the biggest circle on the map is the biggest marker here.
fig = figure('Visible','off','Color','w','Position',[100 100 1000 660]);
ax = axes(fig); hold(ax,'on');

inR  = d_near <= R;
area = 50 + 320 * (c / max(c));          % same scaling as the pinch-point map
green = [0.15 0.55 0.30];
red   = [0.75 0.25 0.20];

scatter(ax, c(inR),  d_near(inR),  area(inR),  'filled', 'MarkerFaceColor',green, ...
        'MarkerFaceAlpha',0.80, 'MarkerEdgeColor','w', 'LineWidth',0.8);
scatter(ax, c(~inR), d_near(~inR), area(~inR), 'filled', 'MarkerFaceColor',red, ...
        'MarkerFaceAlpha',0.80, 'MarkerEdgeColor','w', 'LineWidth',0.8);
yline(ax, R, '--', sprintf('%g km: one cell radius', R), 'Color',[0.2 0.2 0.2], ...
      'LineWidth',1.2, 'LabelHorizontalAlignment','left', 'FontSize',9);

xmax = max(c) * 1.52;                     % room for labels to the right
ymax = max(d_near) * 1.10;
xlim(ax, [-6 xmax]); ylim(ax, [0 ymax]);

% ── Label every pinch-point, pushed apart vertically where they would collide;
% a leader line is drawn whenever a label has been moved ──
[~, by_y] = sort(d_near, 'ascend');
min_gap = 0.030 * ymax;                   % ~11 pt of vertical space
y_lab   = d_near;
for k = 2:numel(by_y)
    i = by_y(k); j = by_y(k-1);
    if y_lab(i) < y_lab(j) + min_gap
        y_lab(i) = y_lab(j) + min_gap;
    end
end

for h = 1:n
    x_lab = c(h) + 0.035*xmax + 0.00012*xmax*sqrt(area(h));
    if abs(y_lab(h) - d_near(h)) > 0.5    % label was nudged: show where it belongs
        plot(ax, [c(h) x_lab-0.008*xmax], [d_near(h) y_lab(h)], '-', ...
            'Color', [0.65 0.65 0.65], 'LineWidth', 0.5);
    end
    txt = sprintf('%s/%s  (%d)', short_ansp(bh(h).ansp_a), short_ansp(bh(h).ansp_b), c(h));
    text(ax, x_lab, y_lab(h), txt, 'FontSize',8, 'HorizontalAlignment','left', ...
        'VerticalAlignment','middle', 'Color',[0.15 0.15 0.15]);
end

xlabel(ax,'Confirmed border crossings at this pinch-point','FontSize',11);
ylabel(ax,'Distance to nearest existing beacon site (km)','FontSize',11);
title(ax, sprintf(['How much border exposure is within reach of existing infrastructure?' ...
    '  (%d of %d pinch-points, %.0f%% of crossings)'], sum(inR), n, ...
    100*sum(c(inR))/sum(c)), 'FontSize',12,'FontWeight','normal');
lg = legend(ax, {'within one cell radius','beyond reach'}, 'Location','northeast', ...
       'Box','off','FontSize',9);
set(lg,'TextColor','k');
grid(ax,'on'); box(ax,'on');
set(ax,'GridAlpha',0.12,'FontSize',10); hold(ax,'off');

if ~exist(config.output_figures,'dir'), mkdir(config.output_figures); end
out = fullfile(config.output_figures,'m2c_beacon_reach.png');
exportgraphics(fig, out, 'Resolution', 200); close(fig);
fprintf('\n[REACH] Figure saved: %s\n', out);

% Is the busiest end better or worse served?
fprintf('\nTop-6 pinch-points: median distance %.0f km\n', median(d_near(ord(1:6))));
fprintf('Bottom-6:           median distance %.0f km\n', median(d_near(ord(end-5:end))));
end
