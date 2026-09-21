function config = setup_config()
% SETUP_CONFIG  Single source of every parameter used by the pipeline.
%   Values marked "modelling choice" have no published calibration for a
%   deployed LDACS network; they are disclosed in the thesis and swept in M7c.
%   Rationale per parameter: docs/design_considerations.md.

    root = fileparts(fileparts(mfilename('fullpath')));
    config.root = root;

    % ── DATA AND OUTPUT PATHS ─────────────────────────────────────────────
    config.csv_path        = fullfile(root, 'data', 'opensky_data_extended.csv');   % OpenSky pull (not in git)
    config.ansp_upper_path = fullfile(root, 'data', 'ansp_upper_490_1.json');       % AIRAC 490 upper airspace
    config.ansp_lower_path = fullfile(root, 'data', 'ansp_lower_490_1.json');       % AIRAC 490 lower airspace
    config.terrain_data_path     = fullfile(root, 'data', 'terrain_elevation.csv');     % Copernicus GLO-90 on the M3 grid
    config.terrain_data_hex_path = fullfile(root, 'data', 'terrain_elevation_hex.csv'); % same, hex lattice + beacon sites
    config.output_data     = fullfile(root, 'results');
    config.output_figures  = fullfile(root, 'results', 'figures');
    config.m8_validation_data = fullfile(root, 'results', 'validation', 'tagged_data.mat');

    % ── DESIGN HOUR AND CORE BOX (where a station may be sited) ───────────
    config.t_start   = 1684137600;              % 2023-05-15 08:00 UTC
    config.t_end     = config.t_start + 3600;
    config.lat_min   = 47.0;  config.lat_max = 53.0;
    config.lon_min   = -1.0;  config.lon_max = 18.0;
    config.alt_min_m = 7600;                    % ~FL249, above the real FL245 MUAC/UK upper-airspace floor
    config.alt_max_m = 16000;                   % ~FL525, sanity ceiling against baroaltitude glitches
    config.corridor_positions = [51.5, 0.1; 50.0, 8.6; 48.2, 16.4];   % London, Frankfurt, Vienna (display only)

    % Extended box = OpenSky query extent: core box grown by the 370 km
    % radio-horizon reach on every side. Acquisition only; analysis is core-box.
    config.ext_margin_km = 370;
    config.data_lat_min  = 43.67;  config.data_lat_max = 56.33;
    config.data_lon_min  = -6.18;  config.data_lon_max = 23.18;

    % ── M1 / M2 / M2b ─────────────────────────────────────────────────────
    config.min_points_per_aircraft = 10;   % ~10 s at the measured ~1 Hz cadence
    config.border_hysteresis_n     = 3;    % consecutive pings before a crossing is confirmed
    config.muac_min_path_km        = 100;  % minimum in-corridor path for the crossings/km comparison

    % ── M3: SITING ────────────────────────────────────────────────────────
    config.gs_radius_km          = 150;    % LDACS cell radius (RFC 9372 / DLR)
    config.grid_base_deg         = 1.0;    % demand grid base cell
    config.grid_fine_deg         = 0.5;    % subdivided cell
    config.grid_subdiv_threshold = 50;     % unique aircraft above which a cell is subdivided (median cell load)
    config.n_max_sweep           = 20;     % greedy runs N = 1..20
    config.pareto_alpha_values   = [0 0.1 0.25 0.5 1 2 4 8];
    config.pareto_eval_N         = 12;     % must equal the matched-N comparison count
    config.hotspot_weight_alpha  = 1.0;    % crossing events -> demand weight (modelling choice)
    config.terrain_cost_weight   = 1.0;    % gain / (1 + w * difficulty)  (modelling choice)
    config.dme_cost_weight       = 1.0;    % DME proximity share of difficulty (modelling choice)
    config.water_match_max_deg   = 0.4;    % nearest-sample tolerance for the lattice/beacon water check
    config.p_robust_tolerances   = [0.10, 0.20];   % Snyder & Daskin (2005) p-robust band: primary, sensitivity

    % Soft coverage edge: P = 1 inside R/10^(F/20), 0 beyond R*10^(F/20).
    % Two documented L-band two-ray fade depths, carried as two scenarios.
    config.fade_margin_db_lo = 2.6;        % exceeded 5% of the time (optimistic)
    config.fade_margin_db_hi = 5.5;        % exceeded 1% of the time (conservative, headline)

    % Co-channel reuse from free-space C/I, over the documented LDACS decode range.
    config.ci_required_db_min = 3.2;       % Epple et al., DME-LDACS1 en-route
    config.ci_required_db_max = 6.0;       % Sajatovic / Graeupl, LDACS1 spec
    config.spectrum_mhz   = 15;            % initial LDACS allocation
    config.channel_bw_mhz = 0.5;

    % DME/VOR beacon register (major-airport sites). Shared by M2c and the
    % siting cost so both consumers use the same coordinates.
    config.dme_beacons = [
        51.48,  -0.45;   % LON
        48.72,   2.38;   % ORY
        50.03,   8.57;   % FRA
        48.35,  11.79;   % MUC
        48.11,  16.57;   % VIE
        50.90,   4.48;   % BRU
        52.31,   4.77;   % AMS
        49.01,   2.55;   % CDG
        51.148, -0.190;  % LGW
        52.166, 20.967;  % WAW (outside the corridor box)
    ];
    config.dme_beacon_names = {'LON','ORY','FRA','MUC','VIE','BRU','AMS','CDG','LGW','WAW'};

    % ── M4 / M5: HANDOVER COST AND STATION FAILURE ────────────────────────
    config.ci_fade_margin_db_list  = [2.6, 5.5];      % both bands; by_margin(2) is the headline
    config.assignment_hysteresis_n = 3;               % same mechanism as border_hysteresis_n
    config.pmipv6_handover_s       = [1.0, 2.4, 3.0]; % illustrative time exposure only (RFC 9372 -> PMIPv6)

    % ── M7: PHYSICAL LINK ─────────────────────────────────────────────────
    config.m7_model        = 'linkbudget';   % 'linkbudget' | 'index' (legacy dimensionless model)
    config.ldacs_freq_mhz  = 1000;           % L-band centre; FSPL varies 1.6 dB over 960-1164 MHz
    config.gs_eirp_dbm     = 46;             % ground-station EIRP, ~40 W (modelling choice, swept)
    config.ac_antenna_gain_dbi  = 0;         % omnidirectional blade antenna
    config.rx_noise_figure_db   = 5;         % avionics-grade receiver
    config.dme_eirp_dbm         = 60;        % DME transponder, ~1 kW peak
    config.dme_oob_rejection_db = 50;        % DME out-of-band emission + receiver filtering (modelling choice, swept)
    config.acm_64qam_margin_db  = 12;        % extra CINR for 64QAM r0.68 over QPSK r0.45 (modelling choice, swept)
    config.gs_mast_height_m     = 25;        % for the radio-horizon check
    config.m7_apply_radio_horizon = true;    % hard line-of-sight gate
    config.nbr_radius_km  = 100;             % A2A neighbourhood radius
    config.r_a_km         = 330;             % LDACS A2A range (Marks et al. 2023)
    config.tdma_k_values  = [1 4 10 25 Inf]; % legacy TDMA coordination sweep

    % Losses between free space and a real receiver, subtracted from the
    % carrier. m7_apply_link_margins = false reproduces the pure free-space budget.
    config.m7_apply_link_margins = true;
    config.m7_apply_fade_margin  = true;     % applies fade_margin_db_lo / hi
    config.m7_impl_loss_db       = 2.0;      % OFDM implementation loss (modelling choice)
    config.m7_airframe_loss_db   = 3.0;      % airframe shadowing + polarisation (modelling choice)
    config.m7_atmos_gamma_db_per_km = 0.0067;   % ITU-R P.676 oxygen absorption, ~1 GHz
    config.m7_atmos_equiv_height_km = 6.0;
    config.m7_atmos_max_db          = 3.0;      % cap near the horizon

    % ── M8 / M9: MATCHED-N SWEEP ──────────────────────────────────────────
    config.m8_N_list = 4:20;    % step of 1 is required by M9's first-difference test
    config.m8_m5_N   = 12;      % the one N at which every topology, including Optimized, exists
end
