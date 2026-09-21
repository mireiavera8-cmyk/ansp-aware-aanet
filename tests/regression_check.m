function n_fail = regression_check()
% REGRESSION_CHECK  Re-run the deterministic modules from the committed M1
%   checkpoint into a temporary folder and compare against results/*.mat.
%   Confirms that a code change moved no number. About 10 minutes; M8/M9
%   (35 min) are left out. Returns the number of failed comparisons.

    init_paths();
    config = setup_config();
    Rref = config.output_data;
    tmp = fullfile(tempdir, 'ansp_aware_regression');
    if exist(tmp, 'dir'), rmdir(tmp, 's'); end
    mkdir(tmp); mkdir(fullfile(tmp, 'figures'));
    config.output_data    = tmp;
    config.output_figures = fullfile(tmp, 'figures');

    S = load(fullfile(Rref, 'tagged_data.mat'));
    tagged_data = S.tagged_data; ansp_names = S.ansp_names; COL = S.COL;
    ansp_polys = load_ansp_polygons(config);
    ref = @(f) getfield(load(fullfile(Rref, f), 'results'), 'results');
    n_fail = 0;

    % M2 / M2b
    bs = evalc_call(@() m2_ansp_border_crossings(tagged_data, ansp_names, COL, config));
    bs_ref = getfield(load(fullfile(Rref, 'border_crossings.mat'), 'border_stats'), 'border_stats');
    n_fail = n_fail + report('M2  confirmed crossings', isequal(bs.total_crossings, bs_ref.total_crossings));
    [~, bh] = evalc_call2(@() m2b_muac_control_analysis(tagged_data, ansp_names, COL, bs, config));
    bh_ref = getfield(load(fullfile(Rref, 'border_hotspots.mat'), 'border_hotspots'), 'border_hotspots');
    n_fail = n_fail + report('M2b pinch-point counts', isequal([bh.count], [bh_ref.count]));

    % M3 family (all deterministic)
    r3 = evalc_call(@() m3_topology_study(tagged_data, COL, ansp_polys, config));
    n_fail = n_fail + report('M3  traffic-only', struct_close(r3, ref('topology_study.mat')));
    r3b = evalc_call(@() m3b_ansp_aware_topology(tagged_data, COL, ansp_polys, bh_ref, r3, config));
    n_fail = n_fail + report('M3b provider-aware', struct_close(r3b, ref('topology_study_ansp_aware.mat')));
    r3c = evalc_call(@() m3c_literature_grid(tagged_data, COL, ansp_polys, bh_ref, config));
    n_fail = n_fail + report('M3c geometric lattice', struct_close(r3c, ref('topology_study_literature_grid.mat')));
    r3g = evalc_call(@() m3g_colocation_topology(tagged_data, COL, ansp_polys, bh_ref, config));
    n_fail = n_fail + report('M3g co-location', struct_close(r3g, ref('topology_study_colocation.mat')));
    r3h = evalc_call(@() m3h_weighted_hex_topology(tagged_data, COL, ansp_polys, bh_ref, config));
    n_fail = n_fail + report('M3h weighted lattice', struct_close(r3h, ref('topology_study_weighted_hex.mat')));
    r3d = evalc_call(@() m3d_pareto_frontier(tagged_data, COL, ansp_polys, bh_ref, r3.conservative, config));
    n_fail = n_fail + report('M3d Pareto sweep', struct_close(r3d, ref('topology_study_pareto.mat')));
    r3e = evalc_call(@() m3e_minimax_topology(tagged_data, COL, ansp_polys, bh_ref, r3b, config));
    n_fail = n_fail + report('M3e minimax', struct_close(r3e, ref('topology_study_minimax.mat')));
    r3f = evalc_call(@() m3f_resilient_topology(tagged_data, COL, ansp_polys, bh_ref, r3b, config));
    n_fail = n_fail + report('M3f resilient', struct_close(r3f, ref('topology_study_resilient.mat')));

    % M4 / M5 / M7 on the provider-aware topology at N = 12
    config.m4_save_label = 'aware';
    r4 = evalc_call(@() m4_handover_cost(tagged_data, COL, r3b.conservative, 12, config));
    n_fail = n_fail + report('M4  handover cost', struct_close(r4, ref('m4_aware_N12.mat')));
    config.m5_save_label = 'aware';
    r5 = evalc_call(@() m5_station_failure(tagged_data, COL, r3b.conservative, 12, config));
    n_fail = n_fail + report('M5  station failure', struct_close(r5, ref('m5_aware_N12.mat')));
    r7 = evalc_call(@() m7_signal_quality(tagged_data, COL, r3b.conservative, 12, config, 'aware_N12'));
    n_fail = n_fail + report('M7  signal quality', struct_close(r7, ref('signal_quality_aware_N12.mat')));

    fprintf('\nREGRESSION: %d failure(s)\n', n_fail);
    rmdir(tmp, 's');
end


function out = evalc_call(fn) %#ok<INUSD>  (fn is used inside the evalc string)
    [~, out] = evalc('fn()');
end

function [a, b] = evalc_call2(fn) %#ok<INUSD>
    [~, a, b] = evalc('fn()');
end

function n = report(label, ok)
    if ok, fprintf('  PASS  %s\n', label); n = 0; else, fprintf('  FAIL  %s\n', label); n = 1; end
end

function ok = struct_close(a, b, tol)
% Recursive comparison: numeric within tol, everything else isequal. The
% config_snapshot a module stores (paths, labels) is not a result and is skipped.
    if nargin < 3, tol = 1e-9; end
    if isstruct(a) && isstruct(b)
        for f = {'config_snapshot'}
            if isfield(a, f{1}), a = rmfield(a, f{1}); end
            if isfield(b, f{1}), b = rmfield(b, f{1}); end
        end
        fa = sort(fieldnames(a)); fb = sort(fieldnames(b));
        if ~isequal(fa, fb) || ~isequal(size(a), size(b)), ok = false; return; end
        for i = 1:numel(a)
            for k = 1:numel(fa)
                if ~struct_close(a(i).(fa{k}), b(i).(fa{k}), tol), ok = false; return; end
            end
        end
        ok = true;
    elseif iscell(a) && iscell(b)
        if ~isequal(size(a), size(b)), ok = false; return; end
        ok = all(arrayfun(@(i) struct_close(a{i}, b{i}, tol), 1:numel(a)));
    elseif (isnumeric(a) || islogical(a)) && (isnumeric(b) || islogical(b))
        if ~isequal(size(a), size(b)), ok = false; return; end
        d = abs(double(a(:)) - double(b(:)));
        d(a(:) == b(:)) = 0;                       % identical values, including Inf
        d(isnan(a(:)) & isnan(b(:))) = 0;
        ok = isempty(d) || (all(~isnan(d)) && max(d) <= tol);
    else
        ok = isequal(a, b);
    end
end
