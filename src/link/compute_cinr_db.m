function cinr_db = compute_cinr_db(ac_lat, ac_lon, d_serving_km, dme_beacons, lb)
% COMPUTE_CINR_DB  Carrier-to-interference-plus-noise ratio in dB.
%   C   = EIRP_gs + G_rx - FSPL(d_serving)
%   I_b = EIRP_dme - OOB_rejection + G_rx - FSPL(d_beacon)   per beacon
%   N   = thermal noise in the channel bandwidth
%   Interference is summed in linear power. Beacon distance is floored at
%   20 km: directly overhead, the transponder antenna's vertical null makes
%   the flat model invalid.
    c_dbm = lb.eirp_dbm + lb.g_rx_dbi - fspl_db(max(d_serving_km, 0.1), lb.freq_mhz);

    km_per_deg = 111.0;
    i_lin = zeros(numel(ac_lat), 1);
    for b = 1:size(dme_beacons,1)
        d_b = sqrt(((ac_lat - dme_beacons(b,1))*km_per_deg).^2 + ...
                   ((ac_lon - dme_beacons(b,2))*km_per_deg.*cosd(ac_lat)).^2);
        d_b = max(d_b, 20);
        i_dbm = lb.dme_eirp_dbm - lb.dme_oob_db + lb.g_rx_dbi - fspl_db(d_b, lb.freq_mhz);
        i_lin = i_lin + 10.^(i_dbm/10);
    end

    n_lin = 10^(lb.noise_dbm/10);
    cinr_db = c_dbm - 10*log10(i_lin + n_lin);
end
