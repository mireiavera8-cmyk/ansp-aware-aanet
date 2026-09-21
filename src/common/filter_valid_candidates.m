function candidates = filter_valid_candidates(grid_points, ansp_polys)
% FILTER_VALID_CANDIDATES  Keep grid points that fall inside an ANSP polygon
%   (upper layer first, lower layer as fallback) and tag each with its ANSP.
    n_pts = numel(grid_points);
    lat = [grid_points.lat]'; lon = [grid_points.lon]';
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

    valid = find(ansp_idx > 0);
    candidates = struct('lat', {}, 'lon', {}, 'weight', {}, 'ansp_name', {});
    for i = 1:numel(valid)
        gi = valid(i);
        candidates(i).lat = grid_points(gi).lat;
        candidates(i).lon = grid_points(gi).lon;
        candidates(i).weight = grid_points(gi).weight;
        candidates(i).ansp_name = ansp_polys(ansp_idx(gi)).name;
    end
end
