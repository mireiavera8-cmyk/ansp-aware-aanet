# Design Considerations

Technical assumptions made in each module, why they were made, and what evidence (literature or empirical check against the actual dataset) backs them. This file exists so a thesis reviewer doesn't have
to reverse-engineer a config value from a one-line code comment.

Each module gets its own section, added as assumptions are reviewed. Not every parameter needs an entry — only ones where the "why" isn't obvious from the code, or where the value could plausibly be challenged.

---

## M1 — Data pipeline (`m1_data_pipeline.m`, `setup_config.m`)

### Altitude floor (`config.alt_min_m = 7600m`, ~FL249)

**What it's for.** M1 tags every ADS-B point with an ANSP using 2D
point-in-polygon matching against two GeoJSON layers (`upper`/`lower`,
AIRAC 490). Stage 3 tries the `upper` layer first, falling back to
`lower`. That design is only valid if every point reaching Stage 3 is
actually in upper airspace — otherwise a point that's really under a
national lower ANSP could get matched against a geographically
overlapping upper-layer polygon (e.g. MUAC's footprint sits directly over
the Netherlands/Belgium/Luxembourg/NW-Germany, where the real lower
ANSPs are LVNL, skeyes and DFS). `alt_min_m` is the filter meant to
guarantee that.

**Why FL249 and not some other number.** The raw AIRAC GeoJSON carries
`min_fl`/`max_fl` per polygon, and it's tempting to read those as the
real upper/lower jurisdiction boundary. They aren't — those fields come
from EUROCONTROL's ACE cost-benchmarking methodology (see
`m1_data_pipeline.m` Stage 3 header), and for MUAC, DFS and NATS
specifically they say `min_fl = 295`, which is wrong. Checked against
Eurocontrol's own public documentation instead:

- MUAC's actual delegated floor (Belgium, Luxembourg, Netherlands,
  NW-Germany) is **FL245**.
- The UK's upper/lower airspace split is also **FL245**.
- France's FIR/UIR split is FL195 — below FL249, so not a concern here.

So the two-layer *geometry* design is sound (MUAC only appears in the
upper-layer file, LVNL/skeyes/DFS only in the lower-layer file — that's a
correct mirror of real ANSP delegation, not a coincidence), and FL249
sits on the correct side of the real FL245 boundary. The margin is thin
though — about 4 FL (~120m/400ft) — which matters given the pipeline's
own sanity-ceiling filter documents serious baroaltitude glitches
elsewhere in this dataset (values up to FL1263 seen in raw OpenSky data).

**Empirical check (2026-08-30).** Rather than guess whether that 4 FL
margin is a real risk, streamed the actual corridor CSV
(`data/opensky_data_extended.csv`) through the same bbox + time-window
+ airborne-only filters M1 applies, and binned the altitude of the
1,445,185 in-scope rows:

| Band | Points | % of in-scope |
|---|---|---|
| FL230–245 (below the real MUAC/UK floor) | 0 | 0.00% |
| FL245–249 (real floor to current `alt_min_m`) | 0 | 0.00% |
| FL249–254 (current floor, thin margin) | 18,712 | 1.29% |
| FL254–260 | 18,931 | 1.31% |
| FL260–270 | 34,553 | 2.39% |
| FL270–295 (up to the GeoJSON's, misleading, MUAC/DFS/NATS `min_fl`) | 111,017 | 7.68% |
| FL295+ | 1,261,972 | 87.32% |

**Reading it:** zero points fall between FL230 and FL249 in this
corridor/hour — there's a clean gap between the real boundary and the
filter, so no traffic is being wrongly admitted from below the true
FL245 line in this dataset. Traffic picks up immediately above the
filter (regional/short-haul aircraft cruising FL250–290), so raising the
floor further would only discard genuine upper-airspace traffic without
buying any measurable safety margin — there's nothing in that "buffer
zone" to correct for.

**Conclusion:** keep `alt_min_m = 7600`. The value is deliberate, not
arbitrary, and is now documented as such in `setup_config.m`. If the
corridor or time window ever changes, re-run this check — the 0%-below,
FL245-anchored result is a property of *this* sample, not a guarantee
that holds for every dataset slice.

---

### Trajectory continuity filter (`config.min_points_per_aircraft = 10`)

**What it's for.** Drops any `icao24` with fewer than 10 ADS-B pings in
the filtered dataset, on the assumption that very short tracks are noise
(a single ping clipping the edge of the bounding box) rather than real
corridor presence worth analyzing.

**The assumption worth checking.** A point-count threshold is only
equivalent to a *duration* threshold if ping cadence is roughly uniform
across aircraft. OpenSky ADS-B coverage is crowdsourced, so cadence can
in principle vary a lot with local receiver density — if it did, this
filter would silently favor aircraft that happened to fly through
receiver-dense areas over aircraft that didn't, independent of how long
either was actually in the corridor.

**Empirical check (2026-08-30).** Grouped the same filtered rows by
aircraft (1,209 unique `icao24` in the validation run) and computed
per-aircraft ping cadence and dwell span:

- **Kept aircraft (≥10 pings, n=1,143):** cadence is ~1.00s at p10,
  median, *and* p90 — 1,122 of 1,143 (98%) report at essentially 1Hz.
  Only 3 aircraft show cadence over 10s. So in this dataset the
  cadence-variability risk doesn't materialize — 10 points is
  effectively ~10 seconds of dwell time for nearly everyone kept.
- **Dropped aircraft (<10 pings, n=66):** median dwell span is **0
  seconds** — these are overwhelmingly single-instant appearances at the
  edge of the bounding box, exactly what this filter is meant to catch.
- **Known limitation, not fixed:** 17 of 1,209 aircraft (1.4%) are
  present for a long time (up to ~50 minutes) but still log fewer than
  10 pings — most plausibly intermittent reception rather than brief
  corridor presence. These get discarded by the current filter even
  though they represent real, sustained traffic. The population is small
  enough that it wasn't judged worth a special-case fix, but it's a real
  gap and should be named as a limitation rather than left implicit.

**Conclusion:** keep `min_points_per_aircraft = 10`. It's functioning as
a "drop momentary bbox-edge clips" filter, which is what it was meant to
be, and the count-vs-duration concern is empirically moot for this
corridor's coverage density. Re-check if the corridor is ever moved
somewhere with sparser ADS-B coverage (e.g. lower altitudes, or regions
with fewer volunteer receivers) — the 1Hz uniformity is a property of
upper airspace over Western Europe, not a guarantee.

---

## M2 — Border-crossing exposure (`m2_ansp_border_crossings.m`)

### Hysteresis threshold (`config.border_hysteresis_n = 3`)

**What it's for.** A confirmed ANSP border crossing requires the new
ANSP label to hold for 3 consecutive pings, to avoid counting GPS/polygon-
edge jitter (a label flickering back and forth on one noisy ping) as a
real crossing.

**Empirical check (2026-08-30).** Decomposed each aircraft's raw ANSP-tag
sequence into runs and split them into two kinds: runs that **revert**
(aircraft returns to the ANSP it came from) vs runs that **progress** (a
genuine ongoing transition to a new ANSP). If n=3 is doing its job, short
reverted runs (noise) should sit well below it and progressing runs
should sit well above it.

| | Original | Validation |
|---|---|---|
| Reverted runs, length ≤3 pings | 11.1% | 2.7% |
| Progressing runs, minimum length | 18 pings | 8 pings |

**Reading it — a mild surprise.** The single-ping "flicker" the code
comment describes as the threshold's reason for existing turns out to be
rare here: most "reverted" episodes are multi-minute excursions near a
border (real flight-path behavior), not noise — raw vs. hysteresis-
confirmed crossing counts differ by only ~2-3% in both datasets. So n=3
isn't doing heavy lifting against the failure mode it was written to
guard against. What it IS doing safely: every genuine progressing
crossing in both datasets is at least 8 pings long — 2.5x+ the
threshold — so n=3 never comes close to rejecting a real crossing, in
either dataset. Conclusion: keep the value, but it's cheap, safe
insurance against a failure mode that's mostly theoretical in this data,
not evidence-backed calibration against an observed jitter problem.
Script: a one-off check (not shipped).

---

## M3 — Topology placement (`m3_topology_study.m` family)

### New variant: resilient, same-ANSP-backup placement (`m3f_resilient_topology.m`)

M6 patched exactly one station (the single riskiest one M5 found) with a
manual same-ANSP backup, after the fact. M3f asks what happens if EVERY
border hotspot is required to have a same-ANSP backup from the start, as
a placement objective — not a one-off repair. Metric: for hotspot h and
ANSP o, track the best and second-best dual-anchor score any selected
station of o achieves there; score(h) = the best (ANSP, backup pair)
across all ANSPs. This is provably non-decreasing in N (unlike a naive
"whichever ANSP currently has the best station" definition, which can
flip identity as N grows and isn't) — verified in the actual run, not
just on paper: the resilience curve came out 0, 0, ..., 6.0%, ...,
23.7% at N=1..20, strictly non-decreasing throughout.

**Result — genuinely mixed, not a clean win.** At N=12, M3f's own
placement scores far better than M3b's on the resilience metric itself
(6.0% vs 0.2% — unsurprising, M3f is optimizing for exactly this). The
real question is the M5 payoff:

| | ANSP-aware (M3b) | Resilient (M3f) |
|---|---|---|
| Total forced-inter-ANSP ticks (F=5.5dB) | 743,985 | 618,285 (−17%) |
| Top-1 station's share of that risk | 14.2% | 16.3% (+2.1pp) |

Designing for backup coverage DOES reduce total blast radius by ~17% —
a real, worthwhile effect. But it does NOT fix concentration: the worst
single station is still about as large a share of a (now smaller) total
risk. Worth reporting as-is: resilience-by-design helps on one axis and
not the other, which is itself a legitimate finding for a thesis about
tradeoffs, not a result to round up into "resilient wins."

### Idea 2: how close is greedy to optimal? (a one-off check, not shipped)

No Optimization Toolbox is installed (no `linprog`), so an LP-relaxation
bound wasn't available. Used exact brute force for N=1–3 (297 candidates
→ C(297,3) ≈ 4.3M combinations, still tractable; N=4 jumps to ~317M,
not) plus a swap-based local search on greedy's own N=4–20 solutions.

| N | Greedy | Best found | Gap |
|---|---|---|---|
| 1 | 19.12% | 19.12% (exact) | 0.00pp |
| 2 | 33.67% | 35.09% (exact) | 1.42pp |
| 3 | 45.07% | 47.34% (exact) | 2.27pp |
| 4–20 | 55–94% | local-search improved | 0.8–3.3pp (always found *some* improvement) |

**Conclusion.** Greedy is not exactly optimal — local search found a
small improving swap at every single N tested — but the gap stays in the
1–3 percentage-point range throughout, both where it's provably exact
(N≤3) and where it's only a weaker local-search lower bound (N≥4). That's
small relative to the tens-of-percentage-point differences this project
reports BETWEEN topology strategies (naive/aware/hex/resilient), so the
greedy-search-order artifact concern is not a material threat to the
qualitative rankings this thesis argues from — but it is a real, quoted
gap, not zero, worth stating plainly rather than claiming greedy is exact.

---

### Terrain-aware siting (M3, M3b, M3e, M3f)

**What it's for.** Every placement module treated candidate sites as
equally buildable — a ridge in the Alps counted the same as a field in
the Netherlands. Real siting cost isn't uniform.

**Data — real, not synthesised.** `data/terrain_elevation.csv`, one
row per M3 candidate site (315, after adding the 18 hotspot-centroid
sites M3b/M3e/M3f also use as candidates): elevation from the
**Copernicus DEM 2021 release GLO-90** (ESA, 90m resolution, free
licence), fetched via the Open-Meteo elevation API and confirmed against that API's own documentation, not assumed. Ruggedness (std-dev of elevation across the site plus 4 neighbours ~5.5km away) is included
separately from raw elevation, since a high plateau is easy to build on
and a steep slope at the same elevation isn't — elevation alone can't
tell them apart. Fetched with an index-addressed, retry-on-rate-limit
script after an earlier naive version silently misaligned data on a
429 error (one-off export scripts, not shipped).

**Three design iterations, kept honest rather than silently overwritten:**

1. **Cost-effectiveness discount, standalone module.** First attempt: a
   new module (M3g) scoring candidates by `raw_gain / (1 + w·difficulty)`,   competing against naive/aware/etc. as its own strategy. Rejected —   terrain should shape how EVERY strategy sites its own network, not be   one more strategy in the lineup.
2. **Strict difficulty-first ordering.** Terrain became the primary sort key, coverage reduced to a binary "does this site help at all" gate.
   Provably monotonic, clean to reason about — but with 315 candidates
   there is nearly always SOME still-useful easy site, so it never
   touched a difficulty>0 site through N=20 and sacrificed ~67 percentage
   points of coverage by N=20 relative to the plain placement. Rejected
   as too extreme to represent a real deployment.
3. **Soft cost-effectiveness discount, inside each strategy's own
   objective (current).** M3, M3b, M3e, and M3f each keep their own
   selection criterion (coverage sum, hotspot dual-anchor, minimax
   residual risk, same-ANSP backup) but score candidates by
   `raw_gain / (1 + w·difficulty_norm)` instead of raw gain — a difficult
   site still wins if its value clearly justifies the cost. Reported
   coverage/risk/resilience metrics are always computed from the RAW
   (unpenalised) achieved values — only the SELECTION order is
   terrain-weighted, so every number stays comparable to before terrain
   was introduced.

**Difficulty score** (same disclosure standard as `hotspot_weight_alpha`
elsewhere in this project — NOT literature-derived, no engineering-cost
dataset for LDACS ground-station siting exists to calibrate against, an
explicit modelling choice flagged for sensitivity analysis):
`difficulty_raw = elevation_m/1000 + ruggedness_std_m/100`, normalised to
[0,1] by its own max. `config.terrain_cost_weight = 1.0`, shared across
all four modules.

**Result.** Terrain difficulty of selected sites stayed at or below the
pool median for M3/M3b/M3f (0.05–0.06 vs. 0.07 median) — these
sum-optimising objectives have enough flexibility to substitute an
easier site of similar value most of the time. M3e (minimax) selected
sites averaging ABOVE the pool median (0.095) — it chases whichever
single hotspot is worst-covered, and sometimes no easier site reaches
it, so it pays the terrain cost when there's no alternative. That
asymmetry is a real, sensible structural difference between a sum
objective and a bottleneck objective, not noise. Coverage cost of
terrain-awareness was modest: M3 conservative at N=12 went from 84.73%
(terrain-blind) to 84.12% (terrain-aware) — a small, defensible price
for realism, not the near-total collapse the rejected strict version
produced.

### Two more baselines: does the vulnerability survive other siting philosophies?

**Why these two.** A comparison is only as convincing as its baselines.
Naive (coverage-greedy) and Hex (uniform geometry) are both real, but a
sceptic could argue the finding is an artifact of MCLP-style greedy
specifically. Two more, philosophically distinct approaches:

**M3g — existing-infrastructure co-location** (`m3g_colocation_topology.m`).
Cost/practicality leads, not coverage or ANSP-awareness: sites fixed at
real DME/VOR beacon coordinates (`config.dme_beacons`, single source of
truth also used by M2c). 9 of the 10 known beacons fall inside this
corridor (WAW/Warsaw's longitude is far outside it) — a real, reported
limitation of this philosophy: **pure infrastructure reuse cannot even
reach this project's N=12 headline comparison point**, capping at N=9.
A real planner facing "need 12, only 9 known reusable sites" hits exactly
this wall.

**M3h — traffic-weighted cellular density** (`m3h_weighted_hex_topology.m`).
Isolates ONE variable against M3c: identical hex geometry, identical
ANSP-blind candidate filtering — only the deployment SEQUENCE changes,
from pure geometric distance-from-centroid to descending real local
traffic weight (real "cell-splitting" cellular practice). Tests whether
giving the textbook method real demand data, while keeping it
geometrically rigid and ANSP-blind, fixes anything.

**Result (N=12, F=5.5dB, inter-ANSP handover rate):**

| Topology | pct_inter | Relative reduction vs. Optimized |
|---|---|---|
| Hex (uniform) | 62.5% | 28.2% |
| Hex (traffic-weighted, M3h) | 60.4% | 25.7% |
| Co-location (M3g, N=9 only) | 55.3% | 18.8% (different N, not directly comparable) |
| Naive | 53.5% | 16.1% |
| ANSP-aware | 53.5% | 16.1% |
| **Optimized** | **44.9%** | — |

**The sharp finding this was built to surface:** weighted-hex (60.4%) is
only 2.1pp better than uniform hex (62.5%) despite using real traffic
data to sequence deployment — while naive/aware (53.5%) are 7-9pp better
than EITHER hex variant, using the same coverage-only logic weighted-hex
also uses. Real demand-awareness, on its own, barely moves the needle;
ANSP-awareness does. This is direct evidence the vulnerability this
thesis studies is specifically about administrative blindness, not
general traffic-blindness — a materially sharper claim than "beats a
data-blind strawman," and it survives a baseline built explicitly to
attack that objection.

**Co-location's result is a genuine, honestly-caveated curiosity, not a
validated mechanism.** At 55.3% it's more competitive than either hex
variant despite having zero traffic- or ANSP-awareness — plausibly
because major hub airports happen to sit in different ANSPs' territory
by simple geographic accident, not by any siting logic. Worth reporting
as an interesting small-N (9 points) observation; not evidence that
infrastructure-reuse is secretly ANSP-aware.

### Is "naive beats aware at N=12" a real effect, or one arbitrary greedy path?

**The problem.** M3/M3b's greedy is fully deterministic — the same input
always produces the exact same topology. Comparing naive vs. ANSP-aware
therefore always meant comparing two frozen, one-off point estimates,
forever, no matter how many times the pipeline reruns — not evidence
that either LOGIC is more consistent than the other.

**Method — GRASP as a robustness probe** (Feo & Resende, 1995, "Greedy
Randomized Adaptive Search Procedures"; `validate_placement_robustness.m`):
at each greedy step, instead of always taking the single
best-scoring candidate, sample uniformly from a Restricted Candidate List
(RCL) of candidates within `RCL_ALPHA=0.15` of the best marginal gain
that step. `RCL_ALPHA=0` recovers the exact deterministic greedy —
sanity-checked against the real saved topology before trusting any
restart. Every restart is seeded (reproducible, not unseeded
randomness). Swept across N=5,8,10,12,15,18,20 in one pass per restart
(prefix-valid, same property as every other MCLP here), 30 restarts each
for naive and aware.

**Result, refreshed after the feasibility constraints below were added**
(the first run predates water exclusion/DME cost/live spectrum budget —
superseded, not just an earlier draft to ignore):

| N | Naive mean±std | Aware mean±std | Naive win rate |
|---|---|---|---|
| 5 | 68.6%±13.0% | 73.5%±16.2% | 50% |
| 8 | 68.2%±10.0% | 68.0%±9.1% | 43% |
| 10 | 62.7%±6.8% | 62.9%±7.5% | 53% |
| **12** | **58.3%±5.4%** | **57.6%±6.3%** | **40%** |
| 15 | 52.0%±5.6% | 52.9%±5.0% | 57% |
| 18 | 48.4%±4.6% | 49.8%±5.3% | 63% |
| 20 | 46.2%±4.3% | 49.4%±5.5% | 73% |

**This is a real finding in its own right, not just a numerical
footnote: the robustness conclusion was itself sensitive to whether
realistic siting constraints were included.** Before feasibility
constraints, naive held a fairly consistent edge (60-73% win rate at
most N). After adding water exclusion, DME siting cost, and the live
spectrum-budget gate, the picture at low-to-mid N is genuinely close to
a coin flip — and at N=12 specifically, the exact station count used as
the headline comparison throughout this project, the win rate flipped
below 50%: ANSP-aware now wins the MAJORITY of restarts (60%), and the
deterministic point estimate is an exact tie (53.5% vs 53.5%). Naive's
edge only becomes reliable again at higher N (>=15). Report the N=12
"naive wins" framing used earlier in this project as superseded — the
honest statement is "roughly tied at N=12, naive pulls ahead only at
higher station counts."

### Full feasibility coverage: water exclusion, DME interference, live spectrum budget

**What was missing.** Terrain was the first feasibility factor added, but
an audit turned up three more: (1) ~10% of every candidate pool (33 of
315 sites) sat in the North Sea/English Channel — `filter_valid_
candidates` only checks ANSP-territory validity (administrative), never
physical buildability, and FIRs commonly extend over sea; (2) the DME/VOR
beacon list already used for the M2c correlation study was never used
for siting cost — a candidate near a major beacon cost the same as one
far from it; (3) the co-channel spectrum budget (30 channels) was only
ever checked AFTER a topology finished — a diagnostic, not a constraint
the greedy could actually respect while building the topology.

**Fixes, all inside M3/M3b/M3e/M3f's existing greedy loops — no new modules:**
- **Water exclusion (hard):** `exclude_water_sites` drops candidates with
  `elevation_m == 0` exactly — the Copernicus DEM's water-fill signature,
  confirmed by geography (every such site clusters exactly where the
  North Sea/Channel is) — right after `filter_valid_candidates`.
  Negative-elevation land (Dutch polders below sea level) is kept.
- **DME proximity (soft):** `load_difficulty` now also computes each
  candidate's DME score with the exact same 1/d formula and beacon list
  as `m2c_dme_hotspot_correlation.m` (both now read `config.dme_beacons`
  — single source of truth, can't drift apart) and adds it to the same
  composite difficulty score terrain uses.
- **Spectrum budget (hard, live):** every greedy step now checks, for
  each still-unpicked candidate, whether adding it would push the
  co-channel conflict graph of the CURRENTLY-selected set past 30
  colours (same `greedy_graph_color` already used for the post-hoc
  diagnostic, just evaluated incrementally). A candidate that would
  break budget is infeasible that step, not merely flagged afterward.
  In practice this never actually binds for this corridor at N<=20
  (D_min ~370-450km is generous relative to the corridor's size) — same
  finding as M7's radio-horizon check: a real constraint, honestly
  enforced, that happens not to change these particular numbers.

Validated: all four modules re-run cleanly with all three fixes active
(a one-off run, not shipped), consistent water-exclusion counts
across files sharing a candidate pool (31 removed from M3's 297-site
grid-only pool, 33 from M3b/M3e/M3f's 315-site grid+hotspot-centroid pool).

### The "Optimized" topology — a p-robust search, not a hand-picked blend

**The question.** Given naive and ANSP-aware are each one deterministic
greedy path, and the GRASP work showed neither dominates the other
across restarts, is there a genuinely BETTER topology available under
every feasibility constraint above — not a guessed blend, but something
actually found and verified?

**Method — GRASP as an optimizer, not just a robustness check**
(`search_optimized_topology.m`): 80 randomized-construction trials (40
naive-style, 40 aware-style; same RCL mechanism as
`validate_placement_robustness.m`), all built under every feasibility
constraint above, each evaluated through the REAL M4/M5 metrics (not a
synthetic proxy like M3b's own dual-anchor escort score). The winner is
chosen by a **p-robust** criterion (Snyder & Daskin, 2005, Transportation
Science — already cited for M3f):
```
minimise   pct_inter (M4)                         — signal-stability floor
subject to coverage (M3) >= max(naive, aware) deterministic coverage at N
           top1_share (M5) <= (1+p) x best top1_share found in the search
```
Chosen over Snyder & Daskin's alternative weighted expected-failure-cost
model because that one needs a real facility failure probability
(MTBF-type data) this project doesn't have — M5's own header already
refuses to fabricate that ("NOT a reliability model... No failure
probabilities... implied"). p-robust needs no such data, only a
disclosed tolerance: `config.p_robust_tolerances = [0.10, 0.20]`,
matching this project's two-bound convention for undetermined modelling
parameters (fade margin, C/I).

**Result (N=12, F=5.5dB):** only 20 of 80 restarts even met the coverage
floor — most random exploration is worse than the deterministic greedy,
as expected. Both p=0.10 and p=0.20 converged on the SAME winner (itself
a small robustness signal — the answer doesn't hinge on which disclosed
tolerance is used):

| Topology | pct_inter | top1_share (M5) |
|---|---|---|
| Naive | 53.5% | 10.9% (at N=20) |
| ANSP-aware | 53.5% | 14.2% |
| Hex | 62.5% (at N=20) | 12.6% |
| **Optimized** | **44.9%** | **14.2%** |

Optimized beats every deterministic baseline on the primary objective —
8.6pp better than naive/aware, 17.6pp better than hex — while meeting
the coverage floor and the failure-robustness tolerance by construction.
Its failure concentration is mid-pack, not best-in-class (naive's is
lower, at a different N) — reported plainly, not smoothed over: winning
decisively on the metric defined as most important is not the same
claim as winning on every axis.

**The nuance worth keeping for the write-up:** the winning construction
came from the ANSP-AWARE search space, even though aware's own
*deterministic* path (53.5%) was tied with naive, not ahead of it. The
lesson isn't "ANSP-awareness is a bad idea" — it's that a single
deterministic greedy commitment to that logic happened to land somewhere
mediocre, and once randomized exploration was allowed to escape that one
path, the same underlying logic produced the best network found across
the entire 80-restart search.

**Temporal robustness check — corrected (`validate_temporal_robustness_optimized.m`
+ `validate_temporal_robustness.m`).** The
search above was run entirely against the original design hour. Tested
against the independent validation hour (2023-05-18):

| Topology | Original hour | Validation hour | Delta |
|---|---|---|---|
| Naive | 53.5% | 60.4% | +6.9pp |
| ANSP-aware | 53.5% | 52.1% | -1.4pp |
| Hex | 62.5% | 63.0% | +0.4pp |
| **Optimized** | **44.9%** | **50.7%** | **+5.7pp** |

**Correction, stated plainly:** an earlier version of this check used a
naive/aware validation-hour baseline computed BEFORE the water/DME/
spectrum feasibility constraints existed, and wrongly concluded
Optimized's edge over naive "collapses to a tie" out-of-sample. Refreshed
against the fully feasibility-constrained topologies, that's wrong in
the opposite direction: **Optimized vs. naive widens from 8.6pp to
9.7pp** on the validation hour — the advantage doesn't shrink, it grows.
**Optimized vs. ANSP-aware genuinely does narrow**, from 8.6pp to 1.4pp —
aware nearly closes the gap out-of-sample, though Optimized still edges
ahead on both hours tested. The honest claim: Optimized is robustly
better than naive (confirmed on independent data, if anything more
strongly), and modestly but consistently better than ANSP-aware (a
real edge on both hours, just a much smaller one out-of-sample than the
design hour suggested). (M5 top1_share shifts for Optimized, +1.9pp, are
unremarkable — in line with the small shifts naive/aware/hex also show,
the general effect of ~10% less traffic that hour.)

Wired into M4/M5/M7 as a fourth strategy
(`results/m3_optimal_search.mat`, loaded — not recomputed — by `main.m`,
since the search itself is an expensive, standalone, seeded-for-
reproducibility deliverable, not something to re-run on every pipeline
pass).

---

## Cross-cutting — Temporal robustness (out-of-sample validation)

**The question this answers.** Everything from M1 through M6 was built and
tuned on ONE hour of traffic: 2023-05-15, 08:00–09:00 UTC. The thesis's
core question is which topology configuration (naive traffic-only,
ANSP-aware, literature hex-grid) is the best deployment choice given its
tradeoffs across coverage, handover cost, and failure blast radius. A real
deployment is physical and fixed — it isn't re-optimized every hour — so
before trusting that conclusion it's worth checking whether it's a
property of the topologies, or an artifact of the one hour they were
judged on.

**Method.** `data/opensky_data_validation.csv` provides a second,
independent hour: 2023-05-18, 17:00–18:00 UTC — three days later, evening
instead of morning, never seen by any part of the pipeline. Deliberately
NOT done: re-running M3's greedy MCLP optimizer on this second hour. That
would fit a *different* topology to the new traffic and answer a
different question ("does the method still win after being refit")
instead of the deployment question ("is the topology we'd actually build
still good under traffic it wasn't designed for"). Instead: M1/M2/M2b run
fresh on the validation hour (purely descriptive, no topology involved),
and M4/M5 re-evaluate the ORIGINAL topologies — unchanged — against the
validation hour's traffic. Implementation:
`validate_temporal_robustness.m` (full run, also saves the comparison
summary) and `validate_temporal_robustness_visualize.m` (redraws the figure
from that saved summary without reprocessing the 926MB CSV
again). Figure: `results/figures/temporal_robustness_check.png`.

**Results — M1/M2/M2b rows unaffected by any M3-family change (purely
descriptive); M4/M5 rows refreshed against the final feasibility-
constrained topologies (`validate_temporal_robustness.m`) —
an earlier draft of this table used pre-water/DME/spectrum numbers and is
superseded, not just an earlier pass to ignore.**

| Check | Original | Validation | Consistent? |
|---|---|---|---|
| Aircraft crossing ≥1 ANSP border | 54.2% | 58.3% | Yes — both majority |
| MUAC-touching aircraft, ≥3 crossings | 6.2% | 12.6% | Yes — MUAC still higher than non-MUAC in both (non-MUAC flat at 1.8%) |
| Median crossing-rate ratio (non-MUAC/MUAC) | 0.61 | 0.76 | Yes — both <1, i.e. MUAC-touching traffic crosses MORE per km in both samples |
| M4, same N=12: naive vs. aware | tied (53.5% both) | aware 52.1% < naive 60.4% | **No — the design-hour tie resolves in aware's favour out-of-sample**, not a reversal of a real ranking (there wasn't one to reverse) |
| M4, matched-coverage (naive N20/aware N12/hex N20) ranking | naive 45.6% < aware 53.5% < hex 69.3% | naive 47.9% < aware 52.1% < hex 71.0% | Yes — identical order |
| M5, top-1 station failure share, ranking | naive 10.9% < hex 12.6% < aware 14.2% | naive 10.5% < hex 12.0% < aware 13.1% | Yes — identical order, all three shift by less than 1.5pp |

**Conclusion.** The matched-coverage ranking (Comparison A) and the M5
concentration ranking both hold exactly on the independent hour — real,
confirmed structural properties of the topologies, not one-hour
coincidences. The N=12 control comparison (B) is more interesting than
"consistent or not": naive and aware are a genuine dead tie on the
design hour, and that tie resolves clearly in ANSP-aware's favour on
the validation hour (an 8.3pp gap) — not a reversal, since there was no
ranking on the original hour to reverse, but real evidence that aware
is the safer bet at matched station count once tested out-of-sample.
The counterintuitive M2b finding (MUAC unification does NOT reduce
crossing rate)
independently replicates too, which strengthens rather than undercuts
that already-surprising result.

**Caveat, stated plainly.** Two hours, both from May 2023, is evidence
against the "one lucky hour" concern — it is not a full seasonal or
diurnal robustness study. If asked "did you check other conditions,"
this is the honest answer: one clean out-of-sample replication, same
qualitative pattern on two of three checks and a clarified (not
contradicted) result on the third, not an exhaustive sweep across
seasons/times-of-day/days-of-week.

---

