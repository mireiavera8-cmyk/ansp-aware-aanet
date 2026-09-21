% M2_ANSP_BORDER_CROSSINGS  Border-crossing exposure of the tagged traffic.
%   Independent of any ground-station layout: counts how many aircraft cross
%   an ANSP border at least once, total confirmed crossings, and which ANSP
%   pairs see the most crossings. For each aircraft the ANSP-tagged trace is
%   walked in time order; a label change is confirmed as a crossing only once
%   the new label holds for config.border_hysteresis_n consecutive pings, so
%   GPS jitter along a polygon edge is not counted.
%   Assumes tagged_data is sorted by [COL.ID, COL.TIME] with each aircraft's
%   rows contiguous, as produced by m1_data_pipeline.m.
%   Inputs : tagged_data, ansp_names, COL (m1_data_pipeline.m), config.
%   Outputs: border_stats struct; saved to results/border_crossings.mat.

function border_stats = m2_ansp_border_crossings(tagged_data, ansp_names, COL, config)

    fprintf('[M2] Border-crossing analysis starting...\n');

    n_ansp = numel(ansp_names);
    id_col = tagged_data(:, COL.ID);

    % ── GROUP ROWS BY AIRCRAFT (contiguous blocks) ──
    block_start = [1; find(diff(id_col) ~= 0) + 1];
    block_end   = [block_start(2:end) - 1; numel(id_col)];
    ac_ids      = id_col(block_start);
    n_ac        = numel(ac_ids);

    crossings_per_ac    = zeros(n_ac, 1);
    transition_counts   = zeros(n_ansp, n_ansp);   % directed: from -> to
    n_raw_transitions   = 0;
    crossing_events     = struct('ac_id',{}, 'from',{}, 'to',{}, 'time',{}, 'lat',{}, 'lon',{});

    for a = 1:n_ac
        rows = block_start(a):block_end(a);
        seq  = tagged_data(rows, COL.ANSP);
        tvec = tagged_data(rows, COL.TIME);
        lat  = tagged_data(rows, COL.LAT);
        lon  = tagged_data(rows, COL.LON);

        [n_cross, trans, n_raw, events] = confirm_crossings(seq, tvec, lat, lon, ...
            config.border_hysteresis_n, n_ansp, ac_ids(a));
        crossings_per_ac(a) = n_cross;
        transition_counts   = transition_counts + trans;
        n_raw_transitions   = n_raw_transitions + n_raw;
        crossing_events     = [crossing_events, events]; %#ok<AGROW>
    end

    n_crossing_ac   = sum(crossings_per_ac > 0);
    total_crossings = sum(crossings_per_ac);

    fprintf('[M2] ---- SUMMARY ----\n');
    fprintf('[M2] Aircraft analyzed             : %d\n', n_ac);
    fprintf('[M2] Aircraft crossing >=1 border  : %d (%.1f%%)\n', n_crossing_ac, 100*n_crossing_ac/n_ac);
    fprintf('[M2] Total confirmed crossings     : %d\n', total_crossings);
    fprintf('[M2] Raw (unfiltered) label changes: %d  |  confirmed after hysteresis>=%d: %d\n', ...
        n_raw_transitions, config.border_hysteresis_n, total_crossings);

    % ── TOP ANSP PAIRS (undirected) ──
    pair_counts = transition_counts + transition_counts';
    pair_counts(1:n_ansp+1:end) = 0;   % no self-pairs

    fprintf('[M2] ---- TOP ANSP BORDER PAIRS ----\n');
    [sorted_vals, sorted_idx] = sort(pair_counts(:), 'descend');
    n_printed = 0;
    for k = 1:numel(sorted_idx)
        if sorted_vals(k) == 0, break; end
        [i, j] = ind2sub(size(pair_counts), sorted_idx(k));
        if i >= j, continue; end   % symmetric matrix: print each pair once
        fprintf('[M2]   %-20s <-> %-20s : %d crossings\n', ansp_names{i}, ansp_names{j}, pair_counts(i,j));
        n_printed = n_printed + 1;
        if n_printed >= 10, break; end
    end
    if n_printed == 0
        fprintf('[M2]   (none — no confirmed crossings)\n');
    end

    % ── PACK RESULTS ──
    border_stats.n_aircraft             = n_ac;
    border_stats.n_aircraft_crossing    = n_crossing_ac;
    border_stats.pct_aircraft_crossing  = 100 * n_crossing_ac / n_ac;
    border_stats.total_crossings        = total_crossings;
    border_stats.n_raw_transitions      = n_raw_transitions;
    border_stats.crossings_per_aircraft = crossings_per_ac;
    border_stats.aircraft_ids           = ac_ids;
    border_stats.transition_counts      = transition_counts;   % directed, from -> to
    border_stats.pair_counts            = pair_counts;         % undirected
    border_stats.ansp_names             = ansp_names;
    border_stats.hysteresis_n           = config.border_hysteresis_n;
    border_stats.crossing_events        = crossing_events;   % one entry per confirmed crossing

    if ~exist(config.output_data, 'dir'), mkdir(config.output_data); end
    save(fullfile(config.output_data, 'border_crossings.mat'), 'border_stats');
    fprintf('[M2] Saved: %s\n', fullfile(config.output_data, 'border_crossings.mat'));
    fprintf('[M2] Border-crossing analysis complete.\n');

end


% ── Hysteresis-confirmed crossing detection for one aircraft's trace ──
% n_raw_transitions counts every unfiltered label change; n_cross only those
% that survive hyst_n. Each event is stamped at the ping where the threshold
% was reached (used by the web visualizer to place crossing markers).
function [n_cross, trans, n_raw_transitions, events] = confirm_crossings(seq, tvec, lat, lon, hyst_n, n_ansp, ac_id)

    trans             = zeros(n_ansp, n_ansp);
    n_cross           = 0;
    n_raw_transitions = sum(diff(seq) ~= 0);
    events            = struct('ac_id',{}, 'from',{}, 'to',{}, 'time',{}, 'lat',{}, 'lon',{});

    if isempty(seq), return; end

    state           = seq(1);   % last confirmed ANSP
    candidate       = state;    % ANSP currently accumulating consecutive pings
    candidate_count = 0;

    for i = 2:numel(seq)
        v = seq(i);
        if v == state
            candidate       = state;
            candidate_count = 0;
            continue;
        end
        if v == candidate
            candidate_count = candidate_count + 1;
        else
            candidate       = v;
            candidate_count = 1;
        end
        if candidate_count >= hyst_n
            trans(state, candidate) = trans(state, candidate) + 1;
            n_cross = n_cross + 1;
            events(end+1) = struct('ac_id', ac_id, 'from', state, 'to', candidate, ...
                'time', tvec(i), 'lat', lat(i), 'lon', lon(i)); %#ok<AGROW>
            state           = candidate;
            candidate_count = 0;
        end
    end

end
