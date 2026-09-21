function [n_colors, color] = greedy_graph_color(adj)
% GREEDY_GRAPH_COLOR  Largest-degree-first greedy colouring of a conflict
%   graph (logical adjacency). Returns the channel count and per-node
%   assignment. Upper bound on the chromatic number; errs conservatively.
    n = size(adj,1);
    degrees = sum(adj,2);
    [~, order] = sort(degrees, 'descend');
    color = zeros(n,1);
    for oi = 1:n
        v = order(oi);
        neighbor_colors = color(adj(v,:) & color'>0);
        c = 1;
        while any(neighbor_colors == c)
            c = c + 1;
        end
        color(v) = c;
    end
    n_colors = max(color);
end
