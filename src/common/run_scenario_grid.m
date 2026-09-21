function scen = run_scenario_grid(candidates, selected_order, demand_grid, anchors, hotspot_weight, R_inner_km, R_outer_km, n_use)
% RUN_SCENARIO_GRID  Evaluate a fixed station order (lattice baselines)
%   under one soft-edge band: demand coverage and dual-anchor pinch-point
%   coverage curves, packed as a scenario struct.
    coverage_pct = grid_coverage_curve(candidates, selected_order, demand_grid, R_inner_km, R_outer_km, n_use);
    hotspot_cov  = hotspot_coverage_curve_dual(candidates, selected_order, anchors, hotspot_weight, R_inner_km, R_outer_km, n_use);

    scen.candidates           = candidates;
    scen.selected_order       = selected_order;
    scen.coverage_pct         = coverage_pct;
    scen.hotspot_coverage_pct = hotspot_cov;
    scen.R_inner_km           = R_inner_km;
    scen.R_outer_km           = R_outer_km;
end
