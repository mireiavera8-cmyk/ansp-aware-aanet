function n_colors = spectrum_colors_if_added(picked_lat, picked_lon, cand_lat, cand_lon, D_min_km)
% SPECTRUM_COLORS_IF_ADDED  Channels needed if candidate (cand_lat,cand_lon)
%   joins the already-picked stations, with co-channel conflict below D_min_km.
    if isempty(picked_lat)
        n_colors = 1;
        return;
    end
    all_lat = [picked_lat; cand_lat];
    all_lon = [picked_lon; cand_lon];
    n = numel(all_lat);
    adj = false(n,n);
    for i = 1:n
        d = haversine_km(all_lat(i), all_lon(i), all_lat, all_lon);
        adj(i,:) = d < D_min_km;
    end
    adj(1:n+1:end) = false;
    n_colors = greedy_graph_color(adj);
end
