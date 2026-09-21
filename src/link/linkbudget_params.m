function lb = linkbudget_params(config)
% LINKBUDGET_PARAMS  Collect the M7 link-budget constants from config.
%   The conservative (higher) C/I threshold is used, so no link is called
%   decodable that the pessimistic reading would call lost. Loss terms
%   default to zero (pure free-space budget) when absent from config.
    lb.freq_mhz   = config.ldacs_freq_mhz;
    lb.eirp_dbm   = config.gs_eirp_dbm;
    lb.g_rx_dbi   = config.ac_antenna_gain_dbi;
    lb.nf_db      = config.rx_noise_figure_db;
    lb.bw_hz      = config.channel_bw_mhz * 1e6;
    lb.noise_dbm  = -174 + 10*log10(lb.bw_hz) + lb.nf_db;

    lb.dme_eirp_dbm = config.dme_eirp_dbm;
    lb.dme_oob_db   = config.dme_oob_rejection_db;

    lb.ci_required_db = config.ci_required_db_max;
    lb.ci_64qam_db    = lb.ci_required_db + config.acm_64qam_margin_db;

    lb.gs_mast_height_m = getfielddef(config, 'gs_mast_height_m', 25);

    lb.apply_margins    = getfielddef(config, 'm7_apply_link_margins', false);
    lb.apply_fade       = getfielddef(config, 'm7_apply_fade_margin',  false);
    lb.impl_loss_db     = getfielddef(config, 'm7_impl_loss_db',        0);
    lb.airframe_loss_db = getfielddef(config, 'm7_airframe_loss_db',    0);
    lb.atmos_gamma      = getfielddef(config, 'm7_atmos_gamma_db_per_km', 0);
    lb.atmos_h_km       = getfielddef(config, 'm7_atmos_equiv_height_km', 0);
    lb.atmos_max_db     = getfielddef(config, 'm7_atmos_max_db',         0);
end
