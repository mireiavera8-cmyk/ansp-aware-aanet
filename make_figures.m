function make_figures(mode, tex_dir)
% MAKE_FIGURES  Rebuild every figure the thesis uses from saved results/*.mat.
%
%   make_figures()                  rebuild all thesis figures (light theme)
%   make_figures('list')            print figure -> generating function
%   make_figures('check', tex_dir)  scan a LaTeX tree for \includegraphics and
%                                   report every figure that has no generator here
%
%   No simulation is re-run. Two steps (beacon reach, throughput band) are
%   deterministic post-processing of saved module outputs.

    if nargin < 1 || isempty(mode), mode = 'build'; end
    init_paths();
    config = setup_config();
    R = config.output_data;
    L = @(f, v) getfield(load(fullfile(R, f), v), v);

    % png name | generator name | call
    FIG = { ...
        'corridor_crossing_map.png',   'plot_corridor_map',          @() plot_corridor_map(); ...
        'pinchpoint_map.png',          'plot_corridor_map([],true)', @() plot_corridor_map([], true); ...
        'm2c_beacon_reach.png',        'analyze_beacon_reach',       @() evalc('analyze_beacon_reach()'); ...
        'm3b_hotspot_improvement.png', 'm3b_visualize',              @() m3b_visualize(L('topology_study_ansp_aware.mat', 'results'), L('topology_study_literature_grid.mat', 'results'), config); ...
        'm3d_pareto_frontier.png',     'm3d_visualize',              @() m3d_visualize(L('topology_study_pareto.mat', 'results'), config); ...
        'm7b_throughput_tradeoff.png', 'm7b_throughput_tradeoff',    @() m7b_throughput_tradeoff(signal_list(R, ''), config, signal_list(R, '_F26')); ...
        'm7c_sensitivity.png',         'm7c_visualize',              @() m7c_visualize(L('m7c_sensitivity.mat', 'results'), config); ...
        'm8_pct_inter_curves.png',     'm8_visualize',               @() m8_visualize(L('m8_topology_sweep.mat', 'results'), config); ...
        'm8_served_curves.png',        'm8_visualize',               @() m8_visualize(L('m8_topology_sweep.mat', 'results'), config); ...
        'm9_singleton_mechanism.png',  'm9_visualize',               @() m9_visualize(L('m9_singleton_analysis.mat', 'results'), config)};

    switch lower(mode)
        case 'list'
            fprintf('%-30s %s\n', 'figure', 'generator');
            for k = 1:size(FIG,1), fprintf('%-30s %s\n', FIG{k,1}, FIG{k,2}); end

        case 'check'
            if nargin < 2, error('make_figures:check', 'make_figures(''check'', tex_dir) needs the LaTeX folder.'); end
            check_against_tex(FIG, tex_dir);

        case 'build'
            force_light_theme();
            if ~exist(config.output_figures, 'dir'), mkdir(config.output_figures); end
            [~, first] = unique(FIG(:,2), 'stable');
            ok = 0;
            for k = first'
                fprintf('[FIG] %s\n', FIG{k,2});
                try
                    FIG{k,3}();
                    ok = ok + 1;
                catch ME
                    fprintf('[FIG] !! %s failed: %s\n', FIG{k,2}, ME.message);
                end
                close all;
            end
            fprintf('\n%d/%d generators ran. Figures:\n', ok, numel(first));
            for k = 1:size(FIG,1)
                p = fullfile(config.output_figures, FIG{k,1});
                if exist(p, 'file')
                    d = dir(p);
                    fprintf('  %-30s %s\n', FIG{k,1}, d.date);
                else
                    fprintf('  %-30s MISSING\n', FIG{k,1});
                end
            end
        otherwise
            error('make_figures:mode', 'Unknown mode "%s".', mode);
    end
end


function check_against_tex(FIG, tex_dir)
% Every \includegraphics{...} in tex_dir (drafts excluded) must map to a
% generator above, or be a static asset the pipeline never produced.
    files = dir(fullfile(tex_dir, '**', '*.tex'));
    used = {};
    for i = 1:numel(files)
        if contains(files(i).folder, '_drafts'), continue; end
        txt = fileread(fullfile(files(i).folder, files(i).name));
        toks = regexp(txt, '\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}', 'tokens');
        for t = 1:numel(toks)
            [~, nm, ext] = fileparts(strtrim(toks{t}{1}));
            used{end+1} = [nm ext]; %#ok<AGROW>
        end
    end
    used = unique(used);
    gen  = FIG(:,1);

    fprintf('\n%-42s %s\n', 'figure in LaTeX', 'generator');
    n_missing = 0;
    for i = 1:numel(used)
        k = find(strcmp(gen, used{i}), 1);
        if isempty(k)
            [~, ~, ext] = fileparts(used{i});
            if strcmpi(ext, '.png') && ~isempty(regexp(used{i}, '^(m\d|corridor|pinchpoint)', 'once'))
                tag = 'NO GENERATOR  <-- add a step to make_figures';
                n_missing = n_missing + 1;
            else
                tag = 'static asset (not produced by the pipeline)';
            end
        else
            tag = FIG{k,2};
        end
        fprintf('%-42s %s\n', used{i}, tag);
    end
    unused = setdiff(gen, used);
    if ~isempty(unused)
        fprintf('\nGenerated here but not used by the LaTeX:\n');
        fprintf('  %s\n', unused{:});
    end
    fprintf('\n%d LaTeX figures, %d without a generator.\n', numel(used), n_missing);
end


function Lst = signal_list(R, suffix)
% M7 outputs in the order main.m produces them (sets the M7b bar order).
    labels = {'naive_N20','naive_N12','aware_N12','minimax_N12','optimized_N12','hex_N12','weighted_hex_N12'};
    Lst = {};
    for k = 1:numel(labels)
        p = fullfile(R, ['signal_quality_' labels{k} suffix '.mat']);
        if exist(p, 'file'), Lst{end+1} = getfield(load(p, 'results'), 'results'); end %#ok<AGROW>
    end
end


function force_light_theme()
% R2025a+ default to a dark figure theme, which exportgraphics honours.
    try
        s = settings;
        s.matlab.appearance.figure.GraphicsTheme.TemporaryValue = "light";
    catch
    end
    set(groot, 'defaultFigureColor', 'w', 'defaultAxesColor', 'w', ...
               'defaultAxesXColor', 'k', 'defaultAxesYColor', 'k', 'defaultAxesZColor', 'k', ...
               'defaultAxesGridColor', [0.15 0.15 0.15], 'defaultTextColor', 'k');
end
