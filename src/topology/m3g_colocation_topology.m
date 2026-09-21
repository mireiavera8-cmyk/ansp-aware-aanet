% M3G_COLOCATION_TOPOLOGY  Existing-infrastructure reuse baseline (DME/VOR sites).
%
% Station locations are FIXED at the DME/VOR beacon coordinates in
% config.dme_beacons that fall inside the corridor bounding box: a planner
% reusing existing sites (power, land, access, permitting) rather than building
% greenfield. Coverage and ANSP awareness are not inputs to the choice at all.
% Deployment order is descending local traffic weight within R_inner,
% discounted by terrain difficulty (DME-proximity term excluded, since every
% site IS a beacon), then water exclusion and the live spectrum budget are
% applied (apply_siting_constraints). The list is small by construction, so the
% sweep caps at the number of feasible beacons rather than n_max_sweep.
%
% INPUT  : tagged_data, COL (M1), ansp_polys, border_hotspots (M2b), config
% OUTPUT : results.optimistic / .conservative (+ pre-constraint order);
%          results/topology_study_colocation.mat

function results = m3g_colocation_topology(tagged_data, COL, ansp_polys, border_hotspots, config)

    fprintf('[M3g] Existing-infrastructure (co-location) baseline starting...\n');

    in_bbox = config.dme_beacons(:,1) >= config.lat_min & config.dme_beacons(:,1) <= config.lat_max & ...
              config.dme_beacons(:,2) >= config.lon_min & config.dme_beacons(:,2) <= config.lon_max;
    beacons = config.dme_beacons(in_bbox, :);
    names_excluded = config.dme_beacon_names(~in_bbox);
    fprintf('[M3g] %d/%d DME beacons fall inside this corridor''s bbox (excluded: %s)\n', ...
        size(beacons,1), size(config.dme_beacons,1), strjoin(names_excluded, ', '));

    candidates = tag_ansp_for_points(beacons(:,1), beacons(:,2), ansp_polys);
    fprintf('[M3g] Candidate co-location sites: %d\n', numel(candidates));

    % Guard: a beacon tagged 'UNKNOWN' would enter M4/M5 as a phantom provider
    % and inflate the inter-provider handover count.
    unknown = strcmp({candidates.ansp_name}, 'UNKNOWN');
    if any(unknown)
        error(['m3g: %d of %d beacon sites fall outside every ANSP polygon and would ' ...
               'enter M4/M5 as a provider named UNKNOWN. Fix the coordinates in ' ...
               'config.dme_beacons or drop those beacons before continuing.'], ...
               sum(unknown), numel(candidates));
    end

    grid_points = build_adaptive_grid(tagged_data, COL, config);

    [R_inner_hi, R_outer_hi] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_hi);
    local_weight = local_traffic_weight(candidates, grid_points, R_inner_hi);

    % include_dme = false: every candidate is a beacon, so a DME-proximity penalty
    % would be a constant offset that the [0,1] normalisation turns into noise.
    [difficulty_norm, dparts] = load_difficulty_hex(candidates, ...
        config.terrain_data_hex_path, config.dme_beacons, config.dme_cost_weight, false);
    fprintf('[M3g] Siting difficulty (0-1, terrain only — DME term excluded by design): median=%.2f\n', ...
        median(difficulty_norm));

    score = local_weight(:) ./ (1 + config.terrain_cost_weight * difficulty_norm(:));
    [~, order] = sort(score, 'descend');

    % Pre-constraint order kept so the cost of the feasibility filter is reportable.
    n_unc = numel(order);
    selected_order_unconstrained = order(1:n_unc);

    [order, site_diag] = apply_siting_constraints(candidates, order, config);
    fprintf(['[M3g] Feasibility: %d water sites and %d spectrum-budget sites dropped ' ...
             'from the deployment order (%d -> %d available)\n'], ...
        site_diag.n_water_dropped, site_diag.n_spectrum_dropped, site_diag.n_in, site_diag.n_out);
    if site_diag.n_water_dropped > 0
        fprintf(['[M3g] WARNING: a DME/VOR beacon coordinate resolved to open water. ' ...
                 'Check config.dme_beacons — a beacon cannot physically be at sea, so this ' ...
                 'is more likely a wrong coordinate than a wrong water flag.\n']);
    end

    n_use = numel(order);
    fprintf('[M3g] Deployment order (busiest reused site first): N=1..%d (caps here — see file header)\n', n_use);

    anchors = compute_hotspot_anchors(border_hotspots, ansp_polys);
    hotspot_weight = config.hotspot_weight_alpha * [border_hotspots.count]';

    [R_inner_lo, R_outer_lo] = soft_edge_radii(config.gs_radius_km, config.fade_margin_db_lo);

    optimistic   = run_scenario_fixed(candidates, order, grid_points, anchors, hotspot_weight, R_inner_lo, R_outer_lo, n_use);
    conservative = run_scenario_fixed(candidates, order, grid_points, anchors, hotspot_weight, R_inner_hi, R_outer_hi, n_use);

    fprintf('[M3g] At N=%d — coverage: %.1f%%, hotspot coverage: %.1f%% (conservative)\n', ...
        n_use, conservative.coverage_pct(end), conservative.hotspot_coverage_pct(end));

    results.optimistic        = optimistic;
    results.conservative      = conservative;
    results.fade_margin_db_lo = config.fade_margin_db_lo;
    results.fade_margin_db_hi = config.fade_margin_db_hi;
    results.n_stations_available = n_use;
    results.selected_order_unconstrained = selected_order_unconstrained;
    results.siting_constraint_diag       = site_diag;
    results.config_snapshot   = config;

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'topology_study_colocation.mat'), 'results');
    fprintf('[M3g] Saved: %s\n', fullfile(config.output_data, 'topology_study_colocation.mat'));
    fprintf('[M3g] Co-location baseline complete.\n');

end


function scen = run_scenario_fixed(candidates, selected_order, grid_points, anchors, hotspot_weight, R_inner_km, R_outer_km, n_use)
    coverage_pct = grid_coverage_curve(candidates, selected_order, grid_points, R_inner_km, R_outer_km, n_use);
    hotspot_cov  = hotspot_coverage_curve_dual(candidates, selected_order, anchors, hotspot_weight, R_inner_km, R_outer_km, n_use);
    scen.candidates           = candidates;
    scen.selected_order       = selected_order;
    scen.coverage_pct         = coverage_pct;
    scen.hotspot_coverage_pct = hotspot_cov;
    scen.R_inner_km           = R_inner_km;
    scen.R_outer_km           = R_outer_km;
end


% TAG_ANSP_FOR_POINTS  Point-in-polygon ANSP lookup for fixed named sites (upper
% layer first, then lower); errors if a site resolves to no ANSP.
function candidates = tag_ansp_for_points(lat, lon, ansp_polys)
    n_pts = numel(lat);
    ansp_idx = zeros(n_pts, 1);
    upper_idx = find(strcmp({ansp_polys.layer}, 'upper'));
    for k = upper_idx
        poly = ansp_polys(k);
        bbox_mask = lon >= min(poly.lon) & lon <= max(poly.lon) & lat >= min(poly.lat) & lat <= max(poly.lat);
        if ~any(bbox_mask), continue; end
        in_poly = false(n_pts, 1);
        in_poly(bbox_mask) = inpolygon(lon(bbox_mask), lat(bbox_mask), poly.lon, poly.lat);
        ansp_idx(in_poly & ansp_idx == 0) = k;
    end
    remaining = ansp_idx == 0;
    if any(remaining)
        lower_idx = find(strcmp({ansp_polys.layer}, 'lower'));
        for k = lower_idx
            poly = ansp_polys(k);
            bbox_mask = remaining & lon >= min(poly.lon) & lon <= max(poly.lon) & lat >= min(poly.lat) & lat <= max(poly.lat);
            if ~any(bbox_mask), continue; end
            in_poly = false(n_pts, 1);
            in_poly(bbox_mask) = inpolygon(lon(bbox_mask), lat(bbox_mask), poly.lon, poly.lat);
            ansp_idx(in_poly & remaining) = k;
        end
    end
    if any(ansp_idx == 0)
        error('m3g: %d beacon(s) did not resolve to any known ANSP polygon.', sum(ansp_idx==0));
    end
    candidates = struct('lat', {}, 'lon', {}, 'weight', {}, 'ansp_name', {});
    for i = 1:n_pts
        candidates(i).lat = lat(i);
        candidates(i).lon = lon(i);
        candidates(i).weight = 0;
        candidates(i).ansp_name = ansp_polys(ansp_idx(i)).name;
    end
end
