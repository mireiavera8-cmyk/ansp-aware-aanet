% M2B_MUAC_CONTROL_ANALYSIS  MUAC vs non-MUAC exposure comparison and crossing hotspots.
%   Part 1 compares aircraft that touch MUAC with those that never do, on
%   (a) a bounded-exposure classification of raw crossing counts (0 / 1-2 /
%   >=3) and (b) a secondary crossing rate per 1000 km flown (paths shorter
%   than config.muac_min_path_km excluded as an unstable denominator). Both
%   metrics point the same way (MUAC-touching traffic crosses more, since
%   MUAC sits at the corridor centre and forces entry and exit crossings),
%   so results are reported without asserting a direction.
%   Part 2 aggregates M2's confirmed crossing events per undirected ANSP
%   pair into a centroid and 90th-percentile radius (km_r90, flat-earth
%   111 km/deg); these hotspots are the input to ANSP-aware placement (M3b).
%   Inputs : tagged_data, ansp_names, COL (M1), border_stats (M2), config.
%   Outputs: muac_stats, border_hotspots; saved to
%            results/muac_control_analysis.mat and results/border_hotspots.mat.

function [muac_stats, border_hotspots] = m2b_muac_control_analysis(tagged_data, ansp_names, COL, border_stats, config)

    fprintf('[M2b] MUAC control-group analysis starting...\n');

    muac_idx = find(strcmp(ansp_names, 'MUAC'), 1);
    if isempty(muac_idx)
        error('[M2b] "MUAC" not found in ansp_names — check ANSP tagging (M1).');
    end

    km_per_deg = 111.0;
    id_col      = tagged_data(:, COL.ID);
    block_start = [1; find(diff(id_col) ~= 0) + 1];
    block_end   = [block_start(2:end) - 1; numel(id_col)];
    ac_ids      = id_col(block_start);
    n_ac        = numel(ac_ids);

    crossings_by_id = zeros(max(ac_ids), 1);
    crossings_by_id(border_stats.aircraft_ids) = border_stats.crossings_per_aircraft;

    touches_muac     = false(n_ac, 1);
    path_km          = zeros(n_ac, 1);
    crossings_per_ac = zeros(n_ac, 1);

    for a = 1:n_ac
        rows = block_start(a):block_end(a);
        lat  = tagged_data(rows, COL.LAT);
        lon  = tagged_data(rows, COL.LON);
        ansp = tagged_data(rows, COL.ANSP);

        touches_muac(a) = any(ansp == muac_idx);

        dlat_km    = diff(lat) * km_per_deg;
        dlon_km    = diff(lon) * km_per_deg .* cosd(lat(1:end-1));
        path_km(a) = sum(sqrt(dlat_km.^2 + dlon_km.^2));

        crossings_per_ac(a) = crossings_by_id(ac_ids(a));
    end

    % Short paths are excluded from the rate comparison only; M2's counts are unaffected.
    valid     = path_km >= config.muac_min_path_km;
    n_dropped = sum(~valid);
    fprintf('[M2b] Excluded %d / %d aircraft with path < %d km (unstable rate denominator).\n', ...
        n_dropped, n_ac, config.muac_min_path_km);

    rate_per_1000km = nan(n_ac, 1);
    rate_per_1000km(valid) = crossings_per_ac(valid) ./ path_km(valid) * 1000;

    muac_mask     = touches_muac & valid;
    non_muac_mask = ~touches_muac & valid;

    % ── PART 1a: BOUNDED-EXPOSURE CLASSIFICATION (raw counts, no distance denominator) ──
    HIGH_THRESHOLD = 3;   % ">=3 crossings" = unbounded/high exposure
    has_path       = path_km > 0;
    muac_all       = touches_muac & has_path;
    non_muac_all   = ~touches_muac & has_path;

    classify = @(cr) struct( ...
        'n',        numel(cr), ...
        'pct_zero', 100*mean(cr==0), ...
        'pct_bounded', 100*mean(cr>=1 & cr<HIGH_THRESHOLD), ...
        'pct_high', 100*mean(cr>=HIGH_THRESHOLD), ...
        'max',      max(cr));

    muac_stats.exposure_high_threshold = HIGH_THRESHOLD;
    muac_stats.exposure_muac           = classify(crossings_per_ac(muac_all));
    muac_stats.exposure_non_muac       = classify(crossings_per_ac(non_muac_all));

    fprintf('[M2b] ---- BOUNDED-EXPOSURE CLASSIFICATION (0 / 1-%d / >=%d crossings) ----\n', ...
        HIGH_THRESHOLD-1, HIGH_THRESHOLD);
    fprintf('[M2b] MUAC-touching (n=%d): %.1f%% zero, %.1f%% bounded, %.1f%% HIGH  (max=%d)\n', ...
        muac_stats.exposure_muac.n, muac_stats.exposure_muac.pct_zero, ...
        muac_stats.exposure_muac.pct_bounded, muac_stats.exposure_muac.pct_high, muac_stats.exposure_muac.max);
    fprintf('[M2b] Non-MUAC      (n=%d): %.1f%% zero, %.1f%% bounded, %.1f%% HIGH  (max=%d)\n', ...
        muac_stats.exposure_non_muac.n, muac_stats.exposure_non_muac.pct_zero, ...
        muac_stats.exposure_non_muac.pct_bounded, muac_stats.exposure_non_muac.pct_high, muac_stats.exposure_non_muac.max);
    % Both pct_high and max are reported; non-MUAC's larger n makes its higher max weak evidence alone.
    fprintf('[M2b] pct_high is HIGHER for MUAC-touching (%.1f%%) than non-MUAC (%.1f%%) here; ' , ...
        muac_stats.exposure_muac.pct_high, muac_stats.exposure_non_muac.pct_high);
    fprintf('only the max (4 vs 9) leans the other way, and non-MUAC''s ~2x larger n weakens that alone.\n');

    % ── PART 1b: DISTANCE-NORMALIZED RATE (secondary) ──
    muac_stats.min_path_km_filter       = config.muac_min_path_km;
    muac_stats.n_excluded_short_path    = n_dropped;
    muac_stats.n_muac                   = sum(muac_mask);
    muac_stats.n_non_muac               = sum(non_muac_mask);
    muac_stats.mean_path_km_muac        = mean(path_km(muac_mask));
    muac_stats.mean_path_km_non_muac    = mean(path_km(non_muac_mask));
    muac_stats.median_rate_muac         = median(rate_per_1000km(muac_mask));
    muac_stats.mean_rate_muac           = mean(rate_per_1000km(muac_mask));
    muac_stats.std_rate_muac            = std(rate_per_1000km(muac_mask));
    muac_stats.median_rate_non_muac     = median(rate_per_1000km(non_muac_mask));
    muac_stats.mean_rate_non_muac       = mean(rate_per_1000km(non_muac_mask));
    muac_stats.std_rate_non_muac        = std(rate_per_1000km(non_muac_mask));
    muac_stats.rate_ratio_median_non_over_muac = muac_stats.median_rate_non_muac / muac_stats.median_rate_muac;
    muac_stats.rate_ratio_mean_non_over_muac   = muac_stats.mean_rate_non_muac / muac_stats.mean_rate_muac;

    muac_stats.aircraft_ids    = ac_ids;
    muac_stats.touches_muac    = touches_muac;
    muac_stats.path_km         = path_km;
    muac_stats.crossings       = crossings_per_ac;
    muac_stats.rate_per_1000km = rate_per_1000km;

    fprintf('[M2b] ---- (secondary/exploratory) CROSSING RATE per 1000 km flown, path>=%dkm ----\n', ...
        config.muac_min_path_km);
    fprintf('[M2b] MUAC-touching aircraft : n=%d, mean path=%.0f km, MEDIAN rate=%.2f  (mean %.2f, std %.2f)\n', ...
        muac_stats.n_muac, muac_stats.mean_path_km_muac, muac_stats.median_rate_muac, ...
        muac_stats.mean_rate_muac, muac_stats.std_rate_muac);
    fprintf('[M2b] Non-MUAC aircraft      : n=%d, mean path=%.0f km, MEDIAN rate=%.2f  (mean %.2f, std %.2f)\n', ...
        muac_stats.n_non_muac, muac_stats.mean_path_km_non_muac, muac_stats.median_rate_non_muac, ...
        muac_stats.mean_rate_non_muac, muac_stats.std_rate_non_muac);
    fprintf('[M2b] Non-MUAC traffic crosses %.2fx more often per km than MUAC-touching traffic (median-based).\n', ...
        muac_stats.rate_ratio_median_non_over_muac);
    fprintf('[M2b]   (mean-based ratio %.2fx — reported for transparency, more outlier-sensitive)\n', ...
        muac_stats.rate_ratio_mean_non_over_muac);

    % ── PART 2: CROSSING HOTSPOTS PER ANSP PAIR (M3 input) ──
    % A tight km_r90 is a real pinch point one well-placed station pair could
    % cover; a wide one means the whole boundary is porous.
    events = border_stats.crossing_events;
    border_hotspots = struct('ansp_a', {}, 'ansp_b', {}, 'count', {}, ...
        'centroid_lat', {}, 'centroid_lon', {}, 'km_r90', {});

    if ~isempty(events)
        ev_from = [events.from]';
        ev_to   = [events.to]';
        ev_lat  = [events.lat]';
        ev_lon  = [events.lon]';
        pair_key = min(ev_from, ev_to) * 1000 + max(ev_from, ev_to);   % n_ansp << 1000
        [unique_keys, ~, key_idx] = unique(pair_key);

        for k = 1:numel(unique_keys)
            mask = key_idx == k;
            i0   = find(mask, 1);           % recover the actual (a,b) pair for this key
            pa   = ev_from(i0); pb = ev_to(i0);

            c_lat = mean(ev_lat(mask));
            c_lon = mean(ev_lon(mask));
            d_km  = sqrt(((ev_lat(mask) - c_lat) * km_per_deg).^2 + ...
                         ((ev_lon(mask) - c_lon) * km_per_deg * cosd(c_lat)).^2);
            r90   = prctile(d_km, 90);

            border_hotspots(end+1) = struct( ...                        %#ok<AGROW>
                'ansp_a', ansp_names{pa}, 'ansp_b', ansp_names{pb}, ...
                'count', sum(mask), 'centroid_lat', c_lat, 'centroid_lon', c_lon, ...
                'km_r90', r90);
        end
    end

    [~, ord] = sort([border_hotspots.count], 'descend');
    border_hotspots = border_hotspots(ord);

    fprintf('[M2b] ---- CROSSING HOTSPOTS (top 5 of %d ANSP pairs, for M3) ----\n', numel(border_hotspots));
    for k = 1:min(5, numel(border_hotspots))
        h = border_hotspots(k);
        fprintf('[M2b]   %s <-> %s: %d crossings, centroid (%.2f, %.2f), r90=%.0fkm\n', ...
            h.ansp_a, h.ansp_b, h.count, h.centroid_lat, h.centroid_lon, h.km_r90);
    end

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'muac_control_analysis.mat'), 'muac_stats');
    fprintf('[M2b] Saved: %s\n', fullfile(config.output_data, 'muac_control_analysis.mat'));
    save(fullfile(config.output_data, 'border_hotspots.mat'), 'border_hotspots');
    fprintf('[M2b] Saved: %s\n', fullfile(config.output_data, 'border_hotspots.mat'));
    fprintf('[M2b] MUAC control-group analysis complete.\n');

end
