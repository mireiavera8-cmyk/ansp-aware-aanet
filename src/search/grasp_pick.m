function best = grasp_pick(gains, rcl_alpha)
% GRASP_PICK  Restricted-candidate-list selection (Feo & Resende 1995):
%   pick uniformly at random among candidates within rcl_alpha of the best
%   gain. rcl_alpha = 0 recovers the deterministic greedy.
    valid = gains > -Inf;
    g_max = max(gains(valid));
    g_min = min(gains(valid));
    threshold = g_max - rcl_alpha * (g_max - g_min);
    rcl = find(gains >= threshold);
    if rcl_alpha <= 0 || numel(rcl) <= 1
        [~, best] = max(gains);
    else
        best = rcl(randi(numel(rcl)));
    end
end
