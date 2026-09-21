# Results

Committed checkpoints, so every module after M1 and every figure can be rebuilt without the raw CSVs. File names follow `<module>_<topology>_N<stations>.mat`; `_F26` marks the optimistic 2.6 dB fade margin, everything else is the conservative 5.5 dB headline.

| File | Produced by | Holds |
|---|---|---|
| `tagged_data.mat` | M1 | ANSP-tagged state vectors of the design hour (`tagged_data`, `ansp_names`, `COL`) |
| `border_crossings.mat`, `border_hotspots.mat`, `muac_control_analysis.mat` | M2, M2b | confirmed crossings, the 18 pinch-points, MUAC control group |
| `dme_hotspot_correlation.mat` | M2c | beacon proximity vs pinch-point crossings |
| `topology_study*.mat` | M3 family | candidates, selected order, coverage curves for each siting strategy (`.conservative` / `.optimistic` where two bands exist) |
| `m3_optimal_search.mat`, `m3_optimal_search_Nsweep.mat`, `m3_optimal_selection_rules.mat`, `m3_placement_robustness.mat` | `src/search/` | GRASP pool and winner, station-count sweep, selection-rule and restart-robustness checks |
| `m4_*.mat` | M4 | handover share per topology (`by_margin(m).pct_inter`) |
| `m5_*.mat` | M5 | leave-one-out failure exposure per station |
| `m6b_interconnection.mat`, `m6c_*.mat` | M6b, M6c | interconnection policy curve, minimax backup chain |
| `signal_quality_*.mat`, `horizon_effect_*.mat`, `m7b_throughput_tradeoff.mat`, `m7c_sensitivity.mat`, `m7d_failure_link_*.mat` | M7 family | clean / FEC / relay / lost split, throughput band, sensitivity sweeps, post-failure link quality |
| `m8_topology_sweep.mat`, `m9_singleton_analysis.mat` | M8, M9 | matched-N sweep and the single-provider-station mechanism |
| `validation/` | `validation/` scripts | the same M1, M2, M4, M5 outputs on the out-of-sample hour, plus `temporal_robustness_comparison.mat` |
| `figures/` | `make_figures.m` | the figures used in the thesis (only these are tracked in git) |
