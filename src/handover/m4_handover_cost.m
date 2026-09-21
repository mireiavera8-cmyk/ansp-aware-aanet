% M4_HANDOVER_COST  Station assignment, handover detection and ANSP-cost split.
%
% Each tick is assigned to the nearest active station using a soft range edge
% [R_inner, R_outer] = [R/10^(F/20), R*10^(F/20)] from L-band two-ray fade
% depths F (every margin in config.ci_fade_margin_db_list is run), and station
% changes are confirmed by an n-tick hysteresis. Each confirmed change between
% two real stations is costed by station ownership: same ANSP = intra
% (make-before-break), different ANSP = inter (break-before-make, RFC 9372).
% Gap entry/exit is reported as coverage statistics, not as a handover. Also
% reports p-median/k-center serving-distance metrics, per-aircraft rates and
% an illustrative PMIPv6-analogy exposure time (not an LDACS measurement).
%
% INPUT : tagged_data, COL (M1); topology (flat, or M3 struct with
%         .optimistic/.conservative); N; config; scenario (default 'conservative').
% OUTPUT: results.by_margin, saved to results/m4_<label>_N<N>.mat when
%         config.m4_save_label is set.

function results = m4_handover_cost(tagged_data, COL, topology, N, config, scenario)

    % Unwrap M3-style {optimistic, conservative} output; default to conservative.
    if nargin < 6 || isempty(scenario)
        scenario = 'conservative';
    end
    if isfield(topology, 'optimistic') || isfield(topology, 'conservative')
        if ~isfield(topology, scenario)
            error('m4_handover_cost: topology has no "%s" scenario. Available: %s', ...
                scenario, strjoin(fieldnames(topology), ', '));
        end
        fprintf('[M4] Topology has optimistic/conservative scenarios -> using .%s\n', scenario);
        topology = topology.(scenario);
    end

    fprintf('[M4] Handover cost analysis starting (N=%d)...\n', N);

    active_idx = topology.selected_order(1:N);
    active = topology.candidates(active_idx);
    active_lat  = [active.lat]';
    active_lon  = [active.lon]';
    active_ansp = {active.ansp_name}';

    R = config.gs_radius_km;
    n_hyst = config.assignment_hysteresis_n;

    n_margins = numel(config.ci_fade_margin_db_list);
    % Field list must match every entry assigned below (struct-array assignment).
    by_margin = struct('fade_margin_db', {}, 'R_inner_km', {}, 'R_outer_km', {}, ...
        'total_handovers', {}, 'n_intra', {}, 'n_inter', {}, 'pct_inter', {}, ...
        'coverage_gap_pct', {}, 'mean_quality_served', {}, ...
        'mean_served_distance_km', {}, 'p95_served_distance_km', {}, ...
        'max_served_distance_km', {}, 'handovers_per_aircraft', {}, ...
        'inter_per_aircraft', {}, 'inter_per_aircraft_served', {}, ...
        'illustrative_exposure_s_min', {}, 'illustrative_exposure_s_typ', {}, ...
        'illustrative_exposure_s_max', {});

    ac_ids = unique(tagged_data(:, COL.ID));
    n_ac = numel(ac_ids);

    for m = 1:n_margins
        F_db = config.ci_fade_margin_db_list(m);
        ratio = 10^(F_db/20);
        R_inner = R / ratio;
        R_outer = R * ratio;

        fprintf('[M4]  Margin F=%.1fdB -> R_inner=%.0fkm, R_outer=%.0fkm\n', F_db, R_inner, R_outer);

        total_handovers = 0;
        n_intra = 0;
        n_inter = 0;
        total_ticks = 0;
        unserved_ticks = 0;
        quality_sum = 0;
        quality_n = 0;
        % Distances to the confirmed serving station (p-median / k-center metrics)
        d_served = [];

        for a = 1:n_ac
            rows = tagged_data(tagged_data(:,COL.ID) == ac_ids(a), :);
            % rows are already time-sorted (M1 sorts by [ID, TIME])
            lat = rows(:, COL.LAT);
            lon = rows(:, COL.LON);
            ntk = numel(lat);
            if ntk < 2, continue; end

            d = zeros(ntk, N);
            for s = 1:N
                d(:,s) = haversine_km(lat, lon, active_lat(s), active_lon(s));
            end
            [dmin, idxmin] = min(d, [], 2);

            raw_station = idxmin;
            raw_station(dmin > R_outer) = 0; % 0 = out of range (unserved)

            confirmed_station = hysteresis_confirm(raw_station, n_hyst);

            % Per-tick quality of the confirmed station (diagnostic only)
            for t = 1:ntk
                total_ticks = total_ticks + 1;
                cs = confirmed_station(t);
                if cs == 0
                    unserved_ticks = unserved_ticks + 1;
                else
                    dd = d(t, cs);
                    q = soft_quality(dd, R_inner, R_outer);
                    quality_sum = quality_sum + q;
                    quality_n = quality_n + 1;
                    d_served(end+1) = dd; %#ok<AGROW>
                end
            end

            % Handovers: confirmed changes between two real stations (gap state 0 skipped)
            changes = find(diff(confirmed_station) ~= 0);
            for c = changes'
                before = confirmed_station(c);
                after  = confirmed_station(c+1);
                if before > 0 && after > 0
                    total_handovers = total_handovers + 1;
                    if strcmp(active_ansp{before}, active_ansp{after})
                        n_intra = n_intra + 1;
                    else
                        n_inter = n_inter + 1;
                    end
                end
            end
        end

        pct_inter = 100 * n_inter / max(1, total_handovers);
        coverage_gap_pct = 100 * unserved_ticks / max(1, total_ticks);
        mean_q = quality_sum / max(1, quality_n);

        % Illustrative time exposure: PMIPv6 analogy, not LDACS-specific
        exp_min = n_inter * config.pmipv6_handover_s(1);
        exp_typ = n_inter * config.pmipv6_handover_s(2);
        exp_max = n_inter * config.pmipv6_handover_s(3);

        entry.fade_margin_db = F_db;
        entry.R_inner_km = R_inner;
        entry.R_outer_km = R_outer;
        entry.total_handovers = total_handovers;
        entry.n_intra = n_intra;
        entry.n_inter = n_inter;
        entry.pct_inter = pct_inter;
        entry.coverage_gap_pct = coverage_gap_pct;
        entry.mean_quality_served = mean_q;

        % ── Serving-distance metrics ──
        ds = sort(d_served(:));
        if isempty(ds)
            entry.mean_served_distance_km = NaN;
            entry.p95_served_distance_km  = NaN;
            entry.max_served_distance_km  = NaN;
        else
            entry.mean_served_distance_km = mean(ds);
            entry.p95_served_distance_km  = ds(max(1, ceil(0.95*numel(ds))));
            entry.max_served_distance_km  = ds(end);
        end

        % ── Handover rates ──
        % pct_inter is a ratio whose denominator depends on coverage, so the
        % absolute count and per-aircraft (and per-aircraft-served) rates are kept too.
        served_frac = max(eps, 1 - coverage_gap_pct/100);
        entry.handovers_per_aircraft       = total_handovers / max(1, n_ac);
        entry.inter_per_aircraft           = n_inter / max(1, n_ac);
        entry.inter_per_aircraft_served    = (n_inter / max(1, n_ac)) / served_frac;
        entry.illustrative_exposure_s_min = exp_min;
        entry.illustrative_exposure_s_typ = exp_typ;
        entry.illustrative_exposure_s_max = exp_max;
        by_margin(m) = entry;

        fprintf('[M4]  Handovers: %d total, %d intra-ANSP, %d inter-ANSP (%.1f%% inter)\n', ...
            total_handovers, n_intra, n_inter, pct_inter);
        fprintf('[M4]  Coverage gap: %.2f%% of ticks unserved | mean link quality (served): %.2f\n', ...
            coverage_gap_pct, mean_q);
        fprintf('[M4]  Serving distance: mean %.0fkm, p95 %.0fkm, max %.0fkm\n', ...
            entry.mean_served_distance_km, entry.p95_served_distance_km, entry.max_served_distance_km);
        fprintf('[M4]  Rates: %.3f handovers/aircraft, %.3f inter/aircraft, %.3f inter/aircraft-served\n', ...
            entry.handovers_per_aircraft, entry.inter_per_aircraft, entry.inter_per_aircraft_served);
        fprintf('[M4]  Illustrative exposure (PMIPv6 analogy, NOT LDACS-measured): %.0f-%.0f-%.0f s\n', ...
            exp_min, exp_typ, exp_max);
    end

    results.N = N;
    results.by_margin = by_margin;
    results.config_snapshot = config;

    if isfield(config, 'm4_save_label') && ~isempty(config.m4_save_label)
        if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
        fname = sprintf('m4_%s_N%d.mat', config.m4_save_label, N);
        save(fullfile(config.output_data, fname), 'results');
        fprintf('[M4] Saved: %s\n', fullfile(config.output_data, fname));
    end

    fprintf('[M4] Handover cost analysis complete.\n');

end


% SOFT_QUALITY  Linear taper from 1 (at R_inner) to 0 (at R_outer).
function q = soft_quality(d, R_inner, R_outer)
    if d <= R_inner
        q = 1;
    elseif d >= R_outer
        q = 0;
    else
        q = (R_outer - d) / (R_outer - R_inner);
    end
end
