function confirmed = hysteresis_confirm(raw, n)
% HYSTERESIS_CONFIRM  Run-length hysteresis on a categorical sequence: a new
%   label (including 0 = unserved) is accepted only after n consecutive
%   observations. Same mechanism for border crossings and station assignment.
    m = numel(raw);
    confirmed = raw;
    current = raw(1);
    run_candidate = raw(1);
    run_len = 1;
    confirmed(1) = current;
    for t = 2:m
        if raw(t) == run_candidate
            run_len = run_len + 1;
        else
            run_candidate = raw(t);
            run_len = 1;
        end
        if run_len >= n
            current = run_candidate;
        end
        confirmed(t) = current;
    end
end
