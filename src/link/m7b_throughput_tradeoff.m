% M7B_THROUGHPUT_TRADEOFF  Expected effective throughput per topology from the M7 split.
%
% Weights each topology's clean/FEC/relay/lost percentages by bit rate:
% clean traffic gets the fast 64QAM rate, FEC-recovered traffic the robust
% QPSK rate, relayed traffic between half and all of the robust rate (two
% hops that may or may not contend for airtime), lost traffic zero. The
% result is a throughput band per topology. If a second results list at the
% other fade margin is supplied, the band also spans that uncertainty. The
% H4 test (is the between-strategy spread inside the within-strategy band?)
% is computed at matched station count and printed.
%
% INPUT : results_list (cell of m7_signal_quality results), config,
%         results_list_alt (optional, same strategies at the other fade margin).
% OUTPUT: tradeoff struct array, saved to results/m7b_throughput_tradeoff.mat,
%         and results/figures/m7b_throughput_tradeoff.png.
function tradeoff = m7b_throughput_tradeoff(results_list, config, results_list_alt)

    fprintf('\n[M7b] Throughput tradeoff analysis starting...\n');

    has_alt = nargin >= 3 && ~isempty(results_list_alt);
    if has_alt
        fprintf('[M7b] Band spans both fade margins (%.1f and %.1f dB) and both relay bounds.\n', ...
            config.fade_margin_db_hi, config.fade_margin_db_lo);
    else
        fprintf('[M7b] Band spans the relay-rate bounds only, at a single fade margin.\n');
    end

    n_strat = numel(results_list);
    tradeoff = struct('label', {}, 'n_stations', {}, 'throughput_lo_kbit_s', {}, ...
        'throughput_hi_kbit_s', {}, 'throughput_per_station_kbit_s', {}, ...
        'pct_clean', {}, 'pct_fec', {}, 'pct_relay', {}, 'pct_lost', {}, 'band_spans_fade', {});

    for i = 1:n_strat
        r = results_list{i};
        [thr_lo, thr_hi] = band_for(r);

        if has_alt
            k = find(cellfun(@(x) strcmp(x.label, r.label) && x.n_stations == r.n_stations, ...
                results_list_alt), 1);
            if ~isempty(k)
                [a_lo, a_hi] = band_for(results_list_alt{k});
                thr_lo = min(thr_lo, a_lo);
                thr_hi = max(thr_hi, a_hi);
            end
        end

        tradeoff(i).label = r.label;
        tradeoff(i).n_stations = r.n_stations;
        tradeoff(i).throughput_lo_kbit_s = thr_lo;
        tradeoff(i).throughput_hi_kbit_s = thr_hi;
        tradeoff(i).pct_clean = r.pct_clean;
        tradeoff(i).pct_fec   = r.pct_fec;
        tradeoff(i).pct_relay = r.pct_relay;
        tradeoff(i).pct_lost  = r.pct_lost;
        tradeoff(i).band_spans_fade = has_alt;
        tradeoff(i).throughput_per_station_kbit_s = ((thr_lo+thr_hi)/2) / r.n_stations;

        fprintf('[M7b] %-18s N=%2d  throughput=%5.1f-%5.1f kbit/s  (%.1f kbit/s per station)  (clean=%.1f%% fec=%.1f%% relay=%.1f%%)\n', ...
            strrep(r.label,'_',' '), r.n_stations, thr_lo, thr_hi, tradeoff(i).throughput_per_station_kbit_s, r.pct_clean, r.pct_fec, r.pct_relay);
    end

    % ── H4 test: between-strategy spread vs within-strategy band, at matched N ──
    Ns = [tradeoff.n_stations];
    for N = unique(Ns)
        sel = Ns == N;
        if sum(sel) < 2, continue; end
        mid = ([tradeoff(sel).throughput_lo_kbit_s] + [tradeoff(sel).throughput_hi_kbit_s]) / 2;
        band = ([tradeoff(sel).throughput_hi_kbit_s] - [tradeoff(sel).throughput_lo_kbit_s]) ./ mid;
        spread = (max(mid) - min(mid)) / min(mid);
        fprintf(['[M7b] At matched N=%d (%d strategies): between-strategy spread %.1f%%, ' ...
                 'within-strategy band %.1f%%-%.1f%% -> spread is %s the modelling uncertainty\n'], ...
            N, sum(sel), 100*spread, 100*min(band), 100*max(band), ...
            ternary(spread <= max(band), 'INSIDE', 'OUTSIDE'));
    end

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'm7b_throughput_tradeoff.mat'), 'tradeoff');

    plot_tradeoff(tradeoff, config);

    fprintf('[M7b] Throughput tradeoff analysis complete.\n');
end


% Throughput band under the two relay-rate bounds (half / full robust rate).
function [thr_lo, thr_hi] = band_for(r)
    rate_fast   = r.rate_fast_kbit_s;
    rate_robust = r.rate_robust_kbit_s;
    relay_lo = 0.5 * rate_robust;
    relay_hi = 1.0 * rate_robust;
    thr_lo = (r.pct_clean*rate_fast + r.pct_fec*rate_robust + r.pct_relay*relay_lo + r.pct_lost*0) / 100;
    thr_hi = (r.pct_clean*rate_fast + r.pct_fec*rate_robust + r.pct_relay*relay_hi + r.pct_lost*0) / 100;
end


function plot_tradeoff(tradeoff, config)

    n_strat = numel(tradeoff);
    labels = arrayfun(@(t) sprintf('%s (N=%d)', disp_name(t.label), t.n_stations), ...
        tradeoff, 'UniformOutput', false);

    lo  = [tradeoff.throughput_lo_kbit_s];
    hi  = [tradeoff.throughput_hi_kbit_s];
    mid = (lo + hi) / 2;

    split = [ [tradeoff.pct_clean]', [tradeoff.pct_fec]', ...
              [tradeoff.pct_relay]', [tradeoff.pct_lost]' ];

    cols = [0.16 0.50 0.72;    % clean
            0.55 0.75 0.88;    % FEC-recovered
            0.97 0.74 0.35;    % relayed
            0.85 0.33 0.29];   % lost

    fig = figure('Visible','off','Position',[100 100 1250 580]);
    tl = tiledlayout(fig, 1, 2, 'TileSpacing','compact', 'Padding','compact');

    % ── left: classification split ──
    ax1 = nexttile(tl);
    b = barh(ax1, 1:n_strat, split, 0.62, 'stacked', 'EdgeColor','none');
    for k = 1:4, b(k).FaceColor = cols(k,:); end
    set(ax1, 'YTick', 1:n_strat, 'YTickLabel', labels, 'YDir','reverse');
    xlim(ax1, [0 100]); xlabel(ax1, 'Share of traffic (%)');
    title(ax1, 'Link quality, as classified', 'FontWeight','bold', 'FontSize',10);
    legend(ax1, {'Clean (64QAM)','FEC-recovered (QPSK)','Relayed via aircraft','Lost'}, ...
        'Location','southoutside', 'Orientation','horizontal', 'Box','off', 'FontSize',8);
    grid(ax1,'on'); box(ax1,'off');

    for i = 1:n_strat
        text(ax1, 2, i, sprintf('%.1f%% clean', split(i,1)), ...
            'Color','w', 'FontWeight','bold', 'FontSize',8.5, 'VerticalAlignment','middle');
    end

    % ── right: throughput mid-band ──
    ax2 = nexttile(tl);
    barh(ax2, 1:n_strat, mid, 0.62, 'FaceColor',[0.16 0.50 0.72], ...
        'FaceAlpha',0.55, 'EdgeColor',[0.16 0.50 0.72], 'LineWidth',1.1);
    set(ax2, 'YTick', 1:n_strat, 'YTickLabel', {}, 'YDir','reverse');
    pad = 0.08 * (max(mid) - min(mid));
    xlim(ax2, [min(mid) - 4*pad, max(mid) + 2.5*pad]);
    xlabel(ax2, 'Expected effective throughput (kbit/s)');
    % Spread quoted at matched N=12 only, to agree with the console line
    m12 = mid([tradeoff.n_stations] == 12);
    title(ax2, sprintf('Throughput, spread %.1f%% across the N=12 field', ...
        100*(max(m12)-min(m12))/max(m12)), 'FontWeight','bold', 'FontSize',10);
    for i = 1:n_strat
        text(ax2, mid(i) + 0.3*pad, i, sprintf('%.0f', mid(i)), ...
            'FontWeight','bold', 'FontSize',9, 'VerticalAlignment','middle');
    end
    grid(ax2,'on'); box(ax2,'off');

    title(tl, 'What the signal-quality split is, and what it is worth', 'FontWeight','bold');
    subtitle(ax2, sprintf(['Relay-rate band spans only %.0f-%.0f kbit/s, narrower than the ' ...
        'marker, so it is not drawn.'], min(hi-lo), max(hi-lo)), 'FontSize', 8.5);

    exportgraphics(fig, fullfile(config.output_figures, 'm7b_throughput_tradeoff.png'), 'Resolution', 150);
    close(fig);
end


function s = disp_name(raw)
% Registry labels to the names used in the thesis tables.
    s = strrep(char(raw), '_', ' ');
    map = { 'naive',        'Traffic-only'
            'aware',        'ANSP-aware'
            'hex',          'Geometric lattice'
            'weighted hex', 'Traffic-weighted lattice'
            'minimax',      'Minimax'
            'optimized',    'Optimized' };
    s = regexprep(s, '\s*N\d+$', '');          % drop the trailing "N12"
    for k = 1:size(map,1)
        if strcmpi(strtrim(s), map{k,1}), s = map{k,2}; return; end
    end
end
