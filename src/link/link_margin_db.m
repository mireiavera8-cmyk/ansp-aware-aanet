function m = link_margin_db(d_km, alt_m, lb, fade_margin_db)
% LINK_MARGIN_DB  Losses between free space and a real receiver, in dB, to
%   subtract from the carrier: fade margin (config.fade_margin_db_lo/hi),
%   implementation loss, airframe/polarisation loss, and ITU-R P.676
%   slant-path oxygen absorption from the real elevation angle (4/3-earth).
%   Returns zeros when lb.apply_margins is false.
    if ~lb.apply_margins
        m = zeros(size(d_km));
        return;
    end

    m = zeros(size(d_km));
    if lb.apply_fade
        m = m + fade_margin_db;
    end
    m = m + lb.impl_loss_db + lb.airframe_loss_db;

    if lb.atmos_gamma > 0 && lb.atmos_h_km > 0
        re_eff_km = (4/3) * 6371;
        h_km = max(alt_m, 0) / 1000;
        d = max(d_km, 1);
        rise_km = h_km - (d.^2) / (2 * re_eff_km);     % height above the station's tangent plane, less earth bulge
        elev_rad = atan2(rise_km, d);
        sin_el = max(sin(elev_rad), sin(deg2rad(0.5)));
        atmos = lb.atmos_gamma * lb.atmos_h_km ./ sin_el;
        m = m + min(atmos, lb.atmos_max_db);
    end
end
