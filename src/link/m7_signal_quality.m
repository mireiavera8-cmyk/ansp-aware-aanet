% M7_SIGNAL_QUALITY  Signal-quality classification of traffic per deployment.
%
% For one placement (scen, n stations) every sampled aircraft-tick is scored
% against its nearest station and classified as CLEAN (decodes at the fast
% 64QAM ACM mode), FEC-RECOVERED (decodes only at the robust QPSK mode),
% A2A-RESCUED (direct link fails but a directly-connected neighbour within
% config.r_a_km can relay) or LOST. With config.m7_model = 'linkbudget' the
% score is CINR in dB (carrier from the nearest station, interference from
% the DME beacons, thermal noise, propagation margins from link_margin_db,
% optional radio-horizon gate) thresholded at the LDACS decode range;
% otherwise a legacy dimensionless index (distance soft edge x (1 - I_dme)).
% Other aircraft's transmissions are not counted as G2A interference: the
% forward link is contention-free and FDD-separated (Graupl & Ehammer 2011).
% Reference rates (COCRv2 125-byte message; 303.3 kbit/s QPSK r=0.45,
% 1373.3 kbit/s 64QAM r=0.68) are attached as constants, not simulated.
%
% INPUT : tagged_data, COL, scen, n, config, label, fade_margin_db (optional,
%         default config.fade_margin_db_hi; pass fade_margin_db_lo for the other bound).
% OUTPUT: results struct saved to results/signal_quality_<label>[_F<10F>].mat.
function results = m7_signal_quality(tagged_data, COL, scen, n, config, label, fade_margin_db)

    if nargin < 7 || isempty(fade_margin_db)
        fade_margin_db = config.fade_margin_db_hi;
    end

    fprintf('[M7] Signal quality classification starting (%s, N=%d, F=%.1fdB)...\n', ...
        label, n, fade_margin_db);

    TIME = COL.TIME; LAT = COL.LAT; LON = COL.LON;

    if isfield(config, 'dme_beacons')
        dme_beacons = config.dme_beacons;
    else
        dme_beacons = [
            51.48,  -0.45; 48.72, 2.38; 50.03, 8.57; 48.35, 11.79; 48.11, 16.57;
            50.90,   4.48; 52.31, 4.77; 49.01, 2.55; 51.14,  1.83; 50.47, 30.47];
        fprintf('[M7] config.dme_beacons not set — using the 10-beacon table from m2_scenario_setup.m\n');
    end

    [R_inner_km, R_outer_km] = soft_edge_radii(config.gs_radius_km, fade_margin_db);
    nbr_radius = config.nbr_radius_km;
    r_a_km = config.r_a_km;

    cand = scen.candidates;
    idx  = scen.selected_order(1:n);
    gs_lat = arrayfun(@(i) cand(i).lat, idx);
    gs_lon = arrayfun(@(i) cand(i).lon, idx);

    lat_grid = min(tagged_data(:,LAT)) : 0.5 : max(tagged_data(:,LAT));
    lon_grid = min(tagged_data(:,LON)) : 0.5 : max(tagged_data(:,LON));
    [LONg, LATg] = meshgrid(lon_grid, lat_grid);
    dme_grid = zeros(size(LATg));
    for b = 1:size(dme_beacons,1)
        d = sqrt(((LATg-dme_beacons(b,1))*111.0).^2 + ((LONg-dme_beacons(b,2))*111.0.*cosd(LATg)).^2);
        d = max(d, 20);
        dme_grid = dme_grid + 1./d;
    end
    dme_norm = max(dme_grid(:));

    % Temporal subsampling: every 30th timestamp (~30 s at ~1 Hz). An airliner
    % moves ~7 km in 30 s, far below the cell radius, so classification is stable.
    times_all = unique(tagged_data(:,TIME));
    times = times_all(1:30:end);

    use_linkbudget = isfield(config,'m7_model') && strcmpi(config.m7_model,'linkbudget');
    if use_linkbudget
        lb = linkbudget_params(config);
        fprintf(['[M7]  Link-budget model: EIRP %.0f dBm, noise floor %.1f dBm, ' ...
                 'decode threshold %.1f dB (64QAM needs %.1f dB)\n'], ...
            lb.eirp_dbm, lb.noise_dbm, lb.ci_required_db, lb.ci_64qam_db);
    end

    n_clean = 0; n_fec = 0; n_relay = 0; n_lost = 0; n_total = 0;
    curve_d = []; curve_eff = [];   % for the degradation graph

    for ti = 1:numel(times)
        t = times(ti);
        mask = tagged_data(:,TIME) == t;
        ac_lat = tagged_data(mask, LAT); ac_lon = tagged_data(mask, LON);
        ac_alt = tagged_data(mask, COL.ALT);
        n_ac = numel(ac_lat);
        if n_ac == 0, continue; end
        n_total = n_total + n_ac;

        d_gs = haversine_km(ac_lat, ac_lon, gs_lat', gs_lon');
        d_min = min(d_gs, [], 2);

        if use_linkbudget
            % ── Physical model: CINR (dB) minus propagation margins ──
            cinr_db = compute_cinr_db(ac_lat, ac_lon, d_min, dme_beacons, lb) ...
                      - link_margin_db(d_min, ac_alt, lb, fade_margin_db);

            if config.m7_apply_radio_horizon
                % Hard line-of-sight gate past the geometric horizon
                d_horizon_km = 3.57 * (sqrt(max(lb.gs_mast_height_m,0)) + sqrt(max(ac_alt,0)));
                cinr_db(d_min > d_horizon_km) = -Inf;
            end

            quality = cinr_db;                       % dB, the reported curve
            clean     = cinr_db >= lb.ci_64qam_db;
            fec       = cinr_db >= lb.ci_required_db & cinr_db < lb.ci_64qam_db;
            direct_ok = cinr_db >= lb.ci_required_db;
        else
            % ── Legacy index model (kept for comparison) ──
            I_dme = compute_I_dme(ac_lat, ac_lon, dme_beacons, dme_norm);
            base_prob = max(0, min(1, (R_outer_km - d_min) / (R_outer_km - R_inner_km)));
            eff_prob = base_prob .* (1 - I_dme);
            quality = eff_prob;
            clean     = eff_prob >= 0.8;
            fec       = eff_prob >= 0.5 & eff_prob < 0.8;
            direct_ok = eff_prob >= 0.5;
        end

        curve_d = [curve_d; d_min]; %#ok<AGROW>
        curve_eff = [curve_eff; quality]; %#ok<AGROW>

        n_clean = n_clean + sum(clean);
        n_fec   = n_fec + sum(fec);

        need_relay = find(~direct_ok);
        if isempty(need_relay), continue; end
        if n_ac < 2
            n_lost = n_lost + numel(need_relay);
            continue;
        end

        dlat = ac_lat' - ac_lat; dlon = ac_lon' - ac_lon;
        D = sqrt((dlat*111.0).^2 + (dlon.*(111.0*cosd(ac_lat))).^2);
        rescued = false(n_ac, 1);
        for i = need_relay'
            cand_j = find(D(i,:) <= r_a_km & D(i,:) > 0.1 & direct_ok');
            rescued(i) = ~isempty(cand_j);
        end
        n_relay = n_relay + sum(rescued(need_relay));
        n_lost  = n_lost + sum(~rescued(need_relay));
    end

    results.label = label;
    results.n_stations = n;
    results.pct_clean   = 100 * n_clean / n_total;
    results.pct_fec      = 100 * n_fec / n_total;
    results.pct_relay     = 100 * n_relay / n_total;
    results.pct_lost      = 100 * n_lost / n_total;
    results.curve_distance_km = curve_d;
    results.curve_eff_prob    = curve_eff;
    results.R_inner_km = R_inner_km;
    results.R_outer_km = R_outer_km;
    results.fade_margin_db = fade_margin_db;
    if use_linkbudget
        results.model = 'linkbudget';
        results.linkbudget = lb;
        results.quality_units = 'CINR_dB';
    else
        results.model = 'index';
        results.quality_units = 'dimensionless_index';
    end
    results.message_size_bytes = 125;          % COCRv2 typical, Graupl & Ehammer sec 4.2
    results.rate_robust_kbit_s = 303.3;         % QPSK, coding rate 0.45 (default)
    results.rate_fast_kbit_s   = 1373.3;        % 64QAM, coding rate 0.68 (aggressive ACM)

    fprintf('[M7] %-16s  clean=%5.1f%%  fec-recovered=%5.1f%%  a2a-rescued=%5.1f%%  lost=%5.1f%%\n', ...
        label, results.pct_clean, results.pct_fec, results.pct_relay, results.pct_lost);

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    % Filename carries the fade margin only for the non-default bound
    if abs(fade_margin_db - config.fade_margin_db_hi) < 1e-9
        fname = sprintf('signal_quality_%s.mat', label);
    else
        fname = sprintf('signal_quality_%s_F%.0f.mat', label, fade_margin_db*10);
    end
    save(fullfile(config.output_data, fname), 'results');

end


function I_dme = compute_I_dme(ac_lat, ac_lon, dme_beacons, dme_norm)
    n_ac = numel(ac_lat);
    raw = zeros(n_ac, 1);
    for b = 1:size(dme_beacons,1)
        d = sqrt(((ac_lat-dme_beacons(b,1))*111.0).^2 + ((ac_lon-dme_beacons(b,2))*111.0.*cosd(ac_lat)).^2);
        d = max(d, 20);
        raw = raw + 1./d;
    end
    % Clamped to [0,1]: dme_norm is a grid maximum, not a physical ceiling, so an
    % aircraft closer to a beacon than any grid node would otherwise exceed 1.
    I_dme = min(1, max(0, raw / dme_norm));
end
