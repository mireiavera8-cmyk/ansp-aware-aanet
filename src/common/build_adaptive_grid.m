function grid_points = build_adaptive_grid(tagged_data, COL, config)
% BUILD_ADAPTIVE_GRID  Demand grid for the MCLP: base cells of
%   config.grid_base_deg, subdivided to config.grid_fine_deg wherever more
%   than config.grid_subdiv_threshold unique aircraft were observed.
%   Each point carries weight = unique aircraft in the cell.
    lat = tagged_data(:, COL.LAT); lon = tagged_data(:, COL.LON); ac_id = tagged_data(:, COL.ID);
    base = config.grid_base_deg; fine = config.grid_fine_deg; thresh = config.grid_subdiv_threshold;
    cell_lat = floor(lat / base); cell_lon = floor(lon / base);
    [base_cells, ~, cell_idx] = unique([cell_lat, cell_lon], 'rows');
    n_base = size(base_cells,1);
    grid_points = struct('lat', {}, 'lon', {}, 'weight', {});
    for c = 1:n_base
        mask = cell_idx == c;
        count = numel(unique(ac_id(mask)));
        if count == 0, continue; end
        la0 = base_cells(c,1) * base; lo0 = base_cells(c,2) * base;
        if count > thresh
            for dlat = [0, fine]
                for dlon = [0, fine]
                    sub_mask = mask & lat >= la0+dlat & lat < la0+dlat+fine & lon >= lo0+dlon & lon < lo0+dlon+fine;
                    sub_count = numel(unique(ac_id(sub_mask)));
                    if sub_count > 0
                        entry.lat = la0+dlat+fine/2; entry.lon = lo0+dlon+fine/2; entry.weight = sub_count;
                        grid_points(end+1) = entry; %#ok<AGROW>
                    end
                end
            end
        else
            entry.lat = la0+base/2; entry.lon = lo0+base/2; entry.weight = count;
            grid_points(end+1) = entry; %#ok<AGROW>
        end
    end
end
