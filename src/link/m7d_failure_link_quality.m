% M7D_FAILURE_LINK_QUALITY  Radio-link degradation after a single station failure.
%
% Uses the same temporal subsampling and link budget as m7_signal_quality,
% so the intact figures must reproduce that module's, then re-scores the
% sampled hour once per active station k with k removed, redirecting each
% tick instantaneously to the nearest surviving station (M5's rule, no
% hysteresis). Two views per removed station: NETWORK-WIDE, the CINR
% distribution over all traffic with k down; DISPLACED, the same restricted
% to the ticks k was serving. Free-space propagation with the configured
% margins only: no capacity or contention limit, so a surviving station
% absorbs any redirected traffic and the degradation reported is geometric.
%
% INPUT : tagged_data, COL, scen (.candidates/.selected_order), n, config, label.
% OUTPUT: results struct (.intact, .per_station, .summary), saved to
%         results/m7d_failure_link_<label>.mat.

function results = m7d_failure_link_quality(tagged_data, COL, scen, n, config, label)

    fprintf('[M7d] Failure link-quality analysis starting (%s, N=%d)...\n', label, n);

    TIME = COL.TIME; LAT = COL.LAT; LON = COL.LON; ALT = COL.ALT;

    if isfield(config, 'dme_beacons')
        dme_beacons = config.dme_beacons;
    else
        error('[M7d] config.dme_beacons is required.');
    end

    cand = scen.candidates;
    idx  = scen.selected_order(1:n);
    gs_lat = arrayfun(@(i) cand(i).lat, idx);
    gs_lon = arrayfun(@(i) cand(i).lon, idx);
    if isfield(cand, 'ansp_name')
        gs_ansp = arrayfun(@(i) string(cand(i).ansp_name), idx);
    else
        gs_ansp = strings(1, n);
    end

    lb = linkbudget_params(config);
    apply_horizon = isfield(config,'m7_apply_radio_horizon') && config.m7_apply_radio_horizon;
    % Same conservative bound m7_signal_quality defaults to
    fade_margin_db = config.fade_margin_db_hi;

    % Same subsampling as m7_signal_quality: every 30th distinct timestamp
    times_all = unique(tagged_data(:,TIME));
    times = times_all(1:30:end);

    % cinr_intact: one value per sampled tick; cinr_fail: one column per removed station
    cinr_intact  = [];
    d_intact     = [];
    owner_intact = [];
    cinr_fail    = [];
    d_fail       = [];

    for ti = 1:numel(times)
        t = times(ti);
        mask = tagged_data(:,TIME) == t;
        ac_lat = tagged_data(mask, LAT);
        ac_lon = tagged_data(mask, LON);
        ac_alt = tagged_data(mask, ALT);
        n_ac = numel(ac_lat);
        if n_ac == 0, continue; end

        d_gs = haversine_km(ac_lat, ac_lon, gs_lat', gs_lon');   % n_ac x n
        [dmin, owner] = min(d_gs, [], 2);

        if apply_horizon
            d_horizon = 3.57 * (sqrt(max(lb.gs_mast_height_m,0)) + sqrt(max(ac_alt,0)));
        else
            d_horizon = inf(n_ac,1);
        end

        c0 = compute_cinr_db(ac_lat, ac_lon, dmin, dme_beacons, lb) ...
             - link_margin_db(dmin, ac_alt, lb, fade_margin_db);
        c0(dmin > d_horizon) = -Inf;

        % One column per removed station: nearest surviving station
        dk = zeros(n_ac, n);
        ck = zeros(n_ac, n);
        for k = 1:n
            dtmp = d_gs;
            dtmp(:,k) = Inf;
            dk(:,k) = min(dtmp, [], 2);
            ctmp = compute_cinr_db(ac_lat, ac_lon, dk(:,k), dme_beacons, lb) ...
                   - link_margin_db(dk(:,k), ac_alt, lb, fade_margin_db);
            ctmp(dk(:,k) > d_horizon) = -Inf;
            ck(:,k) = ctmp;
        end

        cinr_intact  = [cinr_intact;  c0];      %#ok<AGROW>
        d_intact     = [d_intact;     dmin];    %#ok<AGROW>
        owner_intact = [owner_intact; owner];   %#ok<AGROW>
        cinr_fail    = [cinr_fail;    ck];      %#ok<AGROW>
        d_fail       = [d_fail;       dk];      %#ok<AGROW>
    end

    n_ticks = numel(cinr_intact);
    fast_th = lb.ci_64qam_db;

    results.label = label;
    results.n_stations = n;
    results.n_ticks = n_ticks;
    results.fast_threshold_db = fast_th;
    results.decode_threshold_db = lb.ci_required_db;

    % ── Intact reference (must match m7_signal_quality) ──
    results.intact.p50 = prctile(cinr_intact, 50);
    results.intact.p10 = prctile(cinr_intact, 10);
    results.intact.p5  = prctile(cinr_intact,  5);
    results.intact.p1  = prctile(cinr_intact,  1);
    results.intact.pct_below_fast = 100 * mean(cinr_intact < fast_th);
    results.intact.pct_beyond_horizon = 100 * mean(~isfinite(cinr_intact));
    results.intact.median_distance_km = median(d_intact);

    % ── Per removed station ──
    per = struct('station_idx', {}, 'ansp_name', {}, 'served_ticks', {}, ...
        'net_p5', {}, 'net_p1', {}, 'net_pct_below_fast', {}, 'net_pct_beyond_horizon', {}, ...
        'disp_median_d_before_km', {}, 'disp_median_d_after_km', {}, ...
        'disp_median_cinr_before', {}, 'disp_median_cinr_after', {}, ...
        'disp_p5_after', {}, 'disp_pct_below_fast_after', {}, 'disp_pct_beyond_horizon_after', {});

    for k = 1:n
        ck = cinr_fail(:,k);
        e.station_idx = k;
        e.ansp_name = char(gs_ansp(k));
        sel = owner_intact == k;
        e.served_ticks = sum(sel);

        e.net_p5 = prctile(ck, 5);
        e.net_p1 = prctile(ck, 1);
        e.net_pct_below_fast = 100 * mean(ck < fast_th);
        e.net_pct_beyond_horizon = 100 * mean(~isfinite(ck));

        if e.served_ticks > 0
            e.disp_median_d_before_km = median(d_intact(sel));
            e.disp_median_d_after_km  = median(d_fail(sel,k));
            e.disp_median_cinr_before = median(cinr_intact(sel));
            e.disp_median_cinr_after  = median(ck(sel));
            e.disp_p5_after           = prctile(ck(sel), 5);
            e.disp_pct_below_fast_after     = 100 * mean(ck(sel) < fast_th);
            e.disp_pct_beyond_horizon_after = 100 * mean(~isfinite(ck(sel)));
        else
            e.disp_median_d_before_km = NaN; e.disp_median_d_after_km = NaN;
            e.disp_median_cinr_before = NaN; e.disp_median_cinr_after = NaN;
            e.disp_p5_after = NaN;
            e.disp_pct_below_fast_after = NaN; e.disp_pct_beyond_horizon_after = NaN;
        end
        per(k) = e;
    end
    results.per_station = per;

    % ── Topology summary: the worst single failure is the deployment-relevant number ──
    net_p5 = [per.net_p5];
    net_below = [per.net_pct_below_fast];
    disp_loss = [per.disp_median_cinr_before] - [per.disp_median_cinr_after];
    disp_extra = [per.disp_median_d_after_km] - [per.disp_median_d_before_km];

    [worst_p5, worst_k] = min(net_p5);
    results.summary.worst_station = worst_k;
    results.summary.worst_station_ansp = per(worst_k).ansp_name;
    results.summary.intact_p5 = results.intact.p5;
    results.summary.worst_net_p5 = worst_p5;
    results.summary.worst_net_p5_drop_db = results.intact.p5 - worst_p5;
    results.summary.mean_net_p5_drop_db = results.intact.p5 - mean(net_p5);
    results.summary.worst_net_pct_below_fast = max(net_below);
    results.summary.intact_pct_below_fast = results.intact.pct_below_fast;
    results.summary.max_displaced_median_loss_db = max(disp_loss);
    results.summary.mean_displaced_median_loss_db = mean(disp_loss, 'omitnan');
    results.summary.max_displaced_extra_km = max(disp_extra);
    results.summary.mean_displaced_extra_km = mean(disp_extra, 'omitnan');
    results.summary.worst_disp_pct_beyond_horizon = max([per.disp_pct_beyond_horizon_after]);

    fprintf(['[M7d] %-18s intact p5=%.2f dB | worst failure (#%d %s): p5=%.2f dB ' ...
             '(-%.2f), below-fast %.2f%% -> %.2f%%\n'], label, results.intact.p5, ...
        worst_k, per(worst_k).ansp_name, worst_p5, results.summary.worst_net_p5_drop_db, ...
        results.intact.pct_below_fast, results.summary.worst_net_pct_below_fast);
    fprintf(['[M7d]   displaced traffic: median +%.0f km worst / +%.0f km mean, ' ...
             'median loss %.2f dB worst / %.2f dB mean\n'], ...
        results.summary.max_displaced_extra_km, results.summary.mean_displaced_extra_km, ...
        results.summary.max_displaced_median_loss_db, results.summary.mean_displaced_median_loss_db);

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, sprintf('m7d_failure_link_%s.mat', label)), 'results');

end
