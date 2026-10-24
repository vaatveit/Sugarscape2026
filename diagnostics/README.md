# Diagnostics

The probe scripts behind the diagnostic tables in the chapter records (docs/replication/) and the README. None of them
changes the model: they patch it from outside, or count what it does. Until 2026-10-23 they lived in a session
scratchpad; this folder makes the tables regenerable from the repository.

## Running them

From the repository root, with the package installed (`pip install -e .`):

```bash
python diagnostics/probe_lowland.py
```

- **Run from the repo root.** A few scripts read saved runs under `results/`, which `python -m experiments.run <id>` or
  `python -m replication.report` writes.
- **Book pages:** [invert_iii4.py](invert_iii4.py), [invert_iii5.py](invert_iii5.py) and [lag_fit.py](lag_fit.py)
  digitize Figs III-4 and III-5 from page images, and [count_frames.py](count_frames.py) counts agents in animation
  plates. The page images are not in the repository (the book is copyrighted): render the chapter PDFs with
  [render.py](render.py) and set `BOOK_PAGES` to the output folder ([_paths.py](_paths.py)).
- **Arguments:** most scripts take none; the docstrings give any usage, and the index below lists the arguments behind
  each saved output.
- **Run time:** most take 1–15 minutes on 8 worker processes.

## Defaults epochs and pinning

The model's defaults changed twice on 2026-10-22: founders' ages (13:16) and the fertility threshold (15:30). Each
script calls `pin(<epoch>)` from [_pin.py](_pin.py) at import, restoring the two defaults it was written under:

| Epoch | Written | Founders | Fertility threshold |
|---|---|---|---|
| A | before 10-22 13:16 | age 0 | 1.0 (p.55) |
| B | 10-22 13:16–15:30 | ages U[0, max age) | 1.0 |
| C | from 10-22 15:30 | ages U[0, max age) | 0.83 (the current default) |

A setting a script passes explicitly still wins, and the `VAR-` experiments keep their own threshold. Only these two
settings are pinned: a script also runs against today's code. For an exact historical run, check out the commit listed
in the index (`git worktree add ../ss-old <commit>`), copy the script and `_pin.py` there, and run it.

**Verified (2026-10-23):** rerun on today's code, these reproduce their saved outputs exactly:
[probe_lowland.py](probe_lowland.py) and [probe_iii5_cap.py](probe_iii5_cap.py) (epoch C),
[probe_births.py](probe_births.py) (B), and [probe_mason.py](probe_mason.py) and [probe_repro.py](probe_repro.py) (A).
Three epoch-A scripts ([probe_ch4.py](probe_ch4.py), [probe_ch6.py](probe_ch6.py), [probe_mason.py](probe_mason.py))
replace `sex.is_fertile`, which gained a `threshold` argument on 10-22; their replacements now accept it. Scripts from
10-21 ran before later fixes (the disease rule order, sugar-only fertility, two-good credit), so on today's code their
numbers can differ from the records'.

## Added 2026-10-23

| Script | Purpose |
|---|---|
| [frequencies.py](frequencies.py) | The book's single-run population figures as frequencies over 30 seeds (III-3, III-4, III-5, VI-2, VI-3); `30 8 c1c3fit` for the registered variant. Output: [frequencies_c1c3fit.txt](output/frequencies_c1c3fit.txt) |
| [candidates.py](candidates.py) | The README's candidate departures C1–C3 from rule S, and C1+C3 at the fitted threshold (C1+C3fit), scored with the replication targets. Output: [candidates_fit.txt](output/candidates_fit.txt) |
| [fit_c1c3.py](fit_c1c3.py) | Fits C1+C3's fertility threshold to III-1's steady population alone (frozen at 0.74; registered as VAR-c1c3fit), and the same with Ascape's lost gift (0.67) or movement (0.81). Output: [fit_c1c3.txt](output/fit_c1c3.txt) |
| [probe_falls.py](probe_falls.py) | Why VAR-c1c3fit's III-5 falls stop short of extinction: births, starvations and coming-of-age wealth through each fall, with Ascape's lost gift, Ascape's movement, fresh metabolism, or the food-limit settings (lowland, must-move, slower growback); `fit` mode fits each to III-1. Outputs: [probe_falls.txt](output/probe_falls.txt), [probe_falls_food.txt](output/probe_falls_food.txt) |
| [check_capacity.py](check_capacity.py) | Fig II-5's carrying capacities under the food-limit settings. Output: [check_capacity.txt](output/check_capacity.txt) |
| [score_variant.py](score_variant.py) | A registered rule-S variant's settings scored on other experiments (VAR-c1c3fit on VI-1). Output: [score_variant_vi1.txt](output/score_variant_vi1.txt) |
| [candidates2.py](candidates2.py) | Candidates C4–C7: rule-by-rule sweeps, growback first, every disease to each neighbor, two-good credit income. Output: [candidates2.txt](output/candidates2.txt) |
| [check_map.py](check_map.py) | The capacity map against Fig II-1, site by site, from a page render at scale 8. Output: [check_map.txt](output/check_map.txt) |
| [mason_compare.py](mason_compare.py) | MASON's own Sugarscape on our Chapter III targets; build and run it with [mason/](mason/README.md) |
| [ascape_compare.py](ascape_compare.py) | Ascape's Sugarscape sex model on our Chapter III targets, on its landscape and the book's map; build and run it with [ascape/](ascape/README.md). Output: [ascape_compare.txt](output/ascape_compare.txt) |
| [downey_waves.py](downey_waves.py) | II-6 under Think Complexity's settings (vision 1–16, must move, its agents, its generated map), one at a time; `kymo` draws agents per diagonal over time. Outputs: [downey_waves.txt](output/downey_waves.txt), [downey_waves.png](output/downey_waves.png) |
| [mesa_trade.py](mesa_trade.py) | Chapter IV (IV-3, Fig IV-6) with Mesa G1MT's trading partners within vision and diamond movement. Output: [mesa_trade.txt](output/mesa_trade.txt) |
| [sugarscapecw_compare.py](sugarscapecw_compare.py) | SugarscapeCW (Watts, NetLogo) on our Chapter III targets; build and run it with [sugarscapecw/](sugarscapecw/README.md). Output: [sugarscapecw_compare.txt](output/sugarscapecw_compare.txt) |
| [nkremerh_compare.py](nkremerh_compare.py) | nkremerh/sugarscape (Python) on our Chapter III targets, on its landscape and the book's map; run it with [nkremerh/](nkremerh/README.md). Output: [nkremerh_compare.txt](output/nkremerh_compare.txt) |
| [ablation_summary.py](ablation_summary.py) | Scores the two outside models' ablation runs (stacking and wrap in SugarscapeCW; own site, birth harvest and childbearing ages in nkremerh). Outputs: [sugarscapecw_ablate.txt](output/sugarscapecw_ablate.txt), [nkremerh_ablate.txt](output/nkremerh_ablate.txt) |
| [probe_integer_gift.py](probe_integer_gift.py) | Rule S at p.55's threshold with SugarscapeCW's integer gifts (each parent gives int(endowment / 2)), on III-1, III-3, III-4 and III-5. Output: [probe_integer_gift.txt](output/probe_integer_gift.txt) |
| [default_candidate.py](default_candidate.py) | Integer gifts as the default: every experiment the fertility threshold touches, rerun under p.55's threshold with exact and integer gifts, all targets scored beside the saved default runs, with totals and status changes. Output: [default_candidate.txt](output/default_candidate.txt) |
| [score_intgift.py](score_intgift.py) | Integer gifts (VAR-intgift) with C1 and C3 at p.55's threshold on every population figure, beside the saved VAR-book, VAR-intgift, VAR-c1c3fit and default runs. Output: [score_intgift.txt](output/score_intgift.txt) |

## Index

The commit is the last one before the script was written. Saved outputs are in [output/](output/).

| Script | Epoch | Written against | Purpose | Saved output |
|---|---|---|---|---|
| [render.py](render.py) | — | `efc56d3` (10-21 12:14) | Render every page of each chapter PDF in a folder to grayscale PNGs (pages/<tag>/pNNN.png), for digitizing figures. Usage: render.py <pdf folder> <out folder> <scale>. Needs pypdfium2; the book PDFs are not in the repository. |  |
| [snapshots.py](snapshots.py) | A | `b3b7809` (10-21 15:05) | Render agent positions over the capacity map at chosen times, one PNG per experiment. |  |
| [snapshots3.py](snapshots3.py) | A | `a77110b` (10-21 16:25) | Chapter III snapshot panels: agents over the capacity map, colored like the book's animations. |  |
| [diag_flows.py](diag_flows.py) | A | `915ce8b` (10-21 16:44) | Flow accounting for a sex run: births, deaths by cause, harvest, fertility bottleneck. |  |
| [diag_variants.py](diag_variants.py) | A | `915ce8b` (10-21 16:45) | Population trajectories under hypothesis variants (diagnostic only; no project files touched). |  |
| [diag_variants2.py](diag_variants2.py) | A | `915ce8b` (10-21 16:54) | Sensitivity of the S equilibrium to small unstated details (diagnostic only). |  |
| [diag_torus.py](diag_torus.py) | A | `915ce8b` (10-21 17:00) | Does the torus wrap contaminate the x+y centroid and anti-diagonal side metrics? (diagnostic only) |  |
| [probe_population.py](probe_population.py) | A | `65ab1fc` (10-21 17:34) | Probe the Chapter III population gap: founder ages, founder thresholds, child's recorded endowment. |  |
| [snapshots4.py](snapshots4.py) | A | `2bbeaba` (10-21 18:23) | Chapter IV snapshots: agents on the sugar+spice map (IV-1-like), trade edges (IV-4), credit (IV-5). |  |
| [diag_deaths.py](diag_deaths.py) | A | `6bd286e` (10-21 18:33) | Why do agents die after t=50 in the IV-3 configuration? Cause, holdings, and whether the lacking good was visible from the agent's final position. |  |
| [diag_hysteresis.py](diag_hysteresis.py) | A | `6bd286e` (10-21 18:33) | Does the long-run population depend on the starting population? (NEO config, vision 1-5). |  |
| [diag_iv14.py](diag_iv14.py) | A | `6bd286e` (10-21 18:33) | IV-14 die-off: births, deaths by cause, and which fertility test binds. |  |
| [probe_ch4.py](probe_ch4.py) | A | `6bd286e` (10-21 18:43) | Verify the reviewer's claims: (1) Ch IV 'carrying capacity' scales with starting population; (2) sensitivity of IV-14 / IV-18 survival to the both-goods fertility test. |  |
| [probe_disease.py](probe_disease.py) | A | `a8654b3` (10-21 22:18) | Probe Chapter V readings: H0 current (immune -> disease dropped; clear same period); H1 carriers (diseases stay in the agent's list; only non-immune ones count, cost, and learn; any carried disease can be passed on); H2 current but cleared on the next period's check. |  |
| [snapshots5.py](snapshots5.py) | A | `a8654b3` (10-21 22:19) | Chapter V snapshots: sick red, well blue (Animations V-1, V-2); infection edges this period (V-3). |  |
| [review_order_probe.py](review_order_probe.py) | A | `a88339c` (10-21 22:24) | Reviewer probe: does the order of E within a turn explain V-2? H0 = branch as is: immune_response, then transmit. TF = design spec s.2.4 order: transmit, then immune response for self. |  |
| [review_persist_probe.py](review_persist_probe.py) | A | `a88339c` (10-21 22:26) | Reviewer probe: reading P = contracted diseases stay in the agent's set for life; each period every unmatched one gets one flip; 'active' (fee, transmission, sick) = currently unmatched; an immune agent does not contract (nothing added); transmission offers a random ACTIVE disease. P : initial gift goes through the same contraction check (immune ones not added). Pall : initial gift of 10 is added whole (p.147 'given copies of'), matched ones simply inert. H0 : branch as is. |  |
| [review_h3_fee_probe.py](review_h3_fee_probe.py) | A | `a88339c` (10-21 22:29) | Reviewer probe: learning speed vs host death. H0f0 : branch as is, disease_fee = 0 (no deaths from illness). H3f1 : one immune bit per agent per cycle (fn 16), on a random active infection, fee 1. H3f0 : same, fee 0. H3TFf0 : H3, spec order (transmit, then respond), fee 0. |  |
| [review_relay_probe.py](review_relay_probe.py) | A | `a88339c` (10-21 22:31) | Reviewer probe: one-turn relay. A given disease is appended whether or not the receiver is immune; the receiver's next immune response removes matched ones (and flips unmatched ones); transmission comes BEFORE the immune response (spec s.2.4) and picks among everything carried, so an immune agent can pass a disease on once before dropping it. Fee counts active (unmatched) diseases only. RELAYa : an agent transmits whenever it carries anything. RELAYb : an agent transmits only when at least one carried disease is active. |  |
| [review_contact_probe.py](review_contact_probe.py) | A | `a88339c` (10-21 22:33) | Reviewer probe: is contact density the bottleneck? Branch semantics (drop on match), spec order (transmit, then respond) so a d-bit disease gets d offers, and a larger contact set for E only: MOORE : the 8 surrounding sites. VISION : every agent visible along the four lattice directions within the agent's vision. VN : von Neumann (control, spec order). |  |
| [crop.py](crop.py) | — | `5fad93b` (10-22 10:41) | Crop one PDF page to a PNG. Usage: crop.py <pdf> <page> <scale> <out.png> <x0,y0,x1,y1 as fractions>. Needs pypdfium2. |  |
| [visual6.py](visual6.py) | A | `2759e22` (10-22 11:03) | Chapter VI visual check: VI-1 boards, VI-2/VI-3 curves, Schelling boards, Ring World space-time. |  |
| [probe_ch6.py](probe_ch6.py) | A | `2759e22` (10-22 11:06) | Probe the indecomposability gap (VI-2/VI-3). |  |
| [diag_credit6.py](diag_credit6.py) | A | `2759e22` (10-22 11:08) | Why so few loans in VI-1? Count credit seekers and why they fail. |  |
| [probe_repro.py](probe_repro.py) | A | `4117cec` (10-22 11:31) | Probe readings of the sex rule against every reproduction figure (III-1, III-3, III-4, III-5, VI-2, VI-3). | [probe_repro.log](output/probe_repro.log) |
| [diag_window.py](diag_window.py) | A | `4117cec` (10-22 11:35) | III-1, t=0..100: births and deaths by cause, and who starves (age, generation, metabolism, sugar at birth). |  |
| [probe_mason.py](probe_mason.py) | A | `4117cec` (10-22 11:47) | Probe readings suggested by MASON's code and the book's p.65 wording. | [probe_mason.log](output/probe_mason.log) |
| [calibrate.py](calibrate.py) | A | `17bea03` (10-22 12:01) | Fit one reproduction setting to Fig III-1's steady population (≈500), and nothing else. | [calib_coarse.log](output/calib_coarse.log) (`fertility_threshold 0.5,0.6,0.7,0.8,0.9,1.0; then child_share 0.3,0.35,0.4,0.45,0.5`) |
| [probe_ages.py](probe_ages.py) | A | `b430dff` (10-22 13:00) | Founders' starting ages: age 0 (current) vs U[0, max_age) (Animation III-1 frame 1, Fig III-1's start, VI-2's early births, Ascape), each with the book's fertility test (1.0) and the calibrated 0.83. | [probe_ages.log](output/probe_ages.log) |
| [diag_ages.py](diag_ages.py) | A | `b430dff` (10-22 13:09) | III-1 with uniform founder ages and threshold 0.83: births, deaths by cause, and why fertile-age agents don't breed. |  |
| [probe_births.py](probe_births.py) | B | `af5692b` (10-22 14:11) | Decompose III-1's birth rate under the current defaults (spread founder ages, book rule S). | [probe_births.log](output/probe_births.log) |
| [probe_early.py](probe_early.py) | B | `af5692b` (10-22 14:12) | III-1's first 40 periods: births, deaths, fertile stock, and income by metabolism. |  |
| [probe_contact.py](probe_contact.py) | B | `af5692b` (10-22 14:14) | Diagnostic only: how far III-1's births are limited by contact vs wealth. |  |
| [probe_budget.py](probe_budget.py) | B | `af5692b` (10-22 14:16) | III-1 sugar budget in windows: harvest, metabolism, gifts to children, wealth lost at death. |  |
| [probe_cost.py](probe_cost.py) | B | `70caf2b` (10-22 14:33) | Diagnostics only (nothing here is a candidate rule). |  |
| [probe_founders.py](probe_founders.py) | B | `70caf2b` (10-22 14:36) | Diagnostic: a wealth margin for founders only. Founders (ids < initial population) must hold theta_f * endowment to be fertile; everyone born in the run keeps threshold theta_c (1.0 = book). |  |
| [probe_late.py](probe_late.py) | B | `70caf2b` (10-22 14:38) | Diagnostic: is the late III-1 population birth-limited or food-limited? Threshold theta for all (cost = book's half endowment, compounding as in the book via Config.fertility_threshold). |  |
| [count_frames.py](count_frames.py) | — | `70caf2b` (10-22 14:41) | Count agents (dark blobs) in each panel of a 3x2 animation plate. Args: png, threshold, min_size. |  |
| [probe_animrun.py](probe_animrun.py) | B | `70caf2b` (10-22 14:42) | Compare our III-1 trajectories with the animation run (Anim III-2/III-3 frames: 384, 172, 325, 876, 669, 1019 agents; frame 2 confined to the two peaks). |  |
| [probe_wealth2.py](probe_wealth2.py) | B | `f603881` (10-22 14:54) | Absolute wealth in Animation II-3's run vs ours: histograms in the book's bins, mean, max. |  |
| [probe_lifespan.py](probe_lifespan.py) | B | `f603881` (10-22 14:55) | Does maximum age evolve downward in III-1? Mean max age of the living, mean age at death, births, and the 70-79 / 0-9 age-bin ratio (book Animation III-1: 0.68-1.0; U[60,100] predicts 0.625). Diagnostic 'fresh': children draw max age from U[60,100] instead of inheriting it. |  |
| [probe_female.py](probe_female.py) | B | `f603881` (10-22 14:58) | Late III-1: women's lifetime births and the wealth cycle; and net income vs density for evolved agents. |  |
| [probe_waste.py](probe_waste.py) | B | `7e0d763` (10-22 15:11) | Where does regrowth go unharvested? N evolved agents (m=1, vision 5-6, immortal, rich), t=100-300. |  |
| [probe_moves.py](probe_moves.py) | B | `7e0d763` (10-22 15:12) | Movement variants (diagnostic): harvest per evolved agent at fixed N, Fig II-5 m2 points, II-4, III-1. book = nearest of the richest visible sites, own site at distance 0 (current model) anydist = a random one of the richest visible sites, ignoring distance (spreads agents) mustmove= own site excluded unless nothing else is visible |  |
| [probe_nbrs.py](probe_nbrs.py) | B | `772e750` (10-22 15:20) | Mean post-move neighbors (book's network statistic) over time in II-4's run (Animation II-5: 0.9 in all six frames, sd 0.8-0.9), for movement variants (see probe_moves.py). |  |
| [probe_mm.py](probe_mm.py) | B | `772e750` (10-22 15:21) | Must-move vs book movement: II-1 share still moving at t=80-100; III-1 neighbors, partner contact, level. |  |
| [probe_kin.py](probe_kin.py) | B | `772e750` (10-22 15:22) | Who stands next to a fertile agent at its mating turn (III-1, t=300-1000), against the population mix. |  |
| [diff_tables.py](diff_tables.py) | — | `1fa5b85` (10-22 16:19) | Row-by-row diff of a record's results table against a new report: changed status or observed value. |  |
| [probe_iii3.py](probe_iii3.py) | C | `ca250bc` (10-22 16:31) | III-3 (fertility ends 10 years earlier): trajectory, floor, period, late level and women's lifetime births, under founder ages spread/zero and threshold 0.83/1.0. | [iii3_a.txt](output/iii3_a.txt) |
| [probe_iii3_genes.py](probe_iii3_genes.py) | C | `ca250bc` (10-22 16:34) | III-3 at theta 0.83: late level against the genotypes that the founding bottleneck leaves (max age, vision). |  |
| [probe_iii3_mountains.py](probe_iii3_mountains.py) | C | `ca250bc` (10-22 16:35) | III-3: does the society keep both mountains? Floor, period and level split by mountains held, plus the founding crash and when a mountain empties. | [iii3_mtn.txt](output/iii3_mtn.txt) |
| [probe_iii3_cycle.py](probe_iii3_cycle.py) | C | `ca250bc` (10-22 16:39) | III-3 cycle shape: peak-to-peak intervals, peak/trough levels, early transient, by founder ages (theta 0.83). |  |
| [probe_iii3_allee.py](probe_iii3_allee.py) | C | `ca250bc` (10-22 16:41) | III-3: per-mountain birth rate against the mountain's head count (Allee effect?), t=50-1000, both founder settings. Also: does anyone ever re-found an emptied mountain? |  |
| [probe_iii3_founding.py](probe_iii3_founding.py) | C | `ca250bc` (10-22 16:42) | III-3 founding transient: births, old-age deaths and starvation per period, t=0-50 and 50-200, by founder ages. |  |
| [probe_iii4.py](probe_iii4.py) | C | `0464936` (10-22 16:58) | III-4 (endowments 10-40): births, old-age deaths, starvation, metabolism, harvest vs burn, fertile share, by 20-period window. |  |
| [invert_iii4.py](invert_iii4.py) | C | `0464936` (10-22 17:05) | Demographic inversion: given a population curve N(t), the births it implies if every death is from old age (max age uniform on 60..100; founders at ages U[0, max age)). Where births would be negative, the shortfall is the minimum starvation (a lower bound: starved agents' later old-age deaths are still counted). |  |
| [probe_iii4_turns.py](probe_iii4_turns.py) | C | `0464936` (10-22 17:07) | III-4: what each mating turn of a wealth-fertile agent meets, along the first cycles (default config). Counted at the turn (after the agent's own move): neighbors, fertile opposite-sex neighbors, and pairs blocked for want of an empty site; births per turn. Also the age structure (share under fertility age). |  |
| [probe_iii4_variants.py](probe_iii4_variants.py) | C | `0464936` (10-22 17:07) | Diagnostic only: which change gives III-4 the book's swings (first peak 1551@75, trough 346@148, later peaks ~1550 / troughs 400-650, period ~134)? Reports the first peak/trough, late range, period, starvation share and the births-per-period range (20-period means) after t=300. | [iii4_var.txt](output/iii4_var.txt) |
| [probe_iii4_cohorts.py](probe_iii4_cohorts.py) | C | `0464936` (10-22 17:09) | III-4 memory channel: for each birth cohort (20-period windows), the share of its members who reach fertility age holding their threshold, their wealth/threshold then, childhood net income, and lifetime children. |  |
| [probe_ceiling.py](probe_ceiling.py) | C | `0464936` (10-22 17:10) | Net income per agent vs N for evolved agents (metabolism 1, vision 1-6 and 5-6, immortal, rich), t=50-200, and the share with negative net income; total regrowth ceiling for reference. |  |
| [lag_fit.py](lag_fit.py) | C | `4a92124` (10-22 17:19) | How far back must births 'look'? For each lag tau, fit births(t) as a smooth function of N(t - tau) (binned means) and report the share of variance explained, for the book's implied births (t=300-2400) and ours. |  |
| [probe_iii4_knock.py](probe_iii4_knock.py) | C | `4a92124` (10-22 17:22) | Perturbation: run III-4 to t=600 (evolved, settled), cull at random to K agents, and watch the rebound. Births per period by population 20 periods earlier, compared with the book's response curve; and whether a sustained cycle follows. Variants via argv (Config overrides, or '_global' for free contact). |  |
| [probe_iii4_seeds.py](probe_iii4_seeds.py) | C | `4a92124` (10-22 17:24) | Unmodified III-4 over many seeds: how many find the large cycle? Late range, peaks/troughs, period. |  |
| [probe_iii4_basin.py](probe_iii4_basin.py) | C | `4a92124` (10-22 17:32) | Basin of III-4's large cycle: cull the settled society (t=600) at random to K agents and see which runs lock into a sustained large cycle (range > 600 over the last 300 periods of 1,500 after the cull). Also characterize locked runs: peaks, troughs and peak spacing over that window, plus mean max age, vision, endowment. | [iii4_basin.txt](output/iii4_basin.txt); [iii4_basin_g.txt](output/iii4_basin_g.txt) (`400 10 global`) |
| [invert_iii5.py](invert_iii5.py) | C | `a3285cf` (10-22 17:42) | Fig III-5: digitize, invert (old-age deaths only), and compare births-vs-lagged-N with our III-5 runs. |  |
| [probe_iii5.py](probe_iii5.py) | C | `a3285cf` (10-22 17:43) | III-5: births through each fall (peak -> trough): first and second half, mothers' ages, fertile-age women, the share holding their threshold, and their net income. Also the births in the 60 periods before each trough. | [iii5_falls.txt](output/iii5_falls.txt) |
| [probe_iii5_knock.py](probe_iii5_knock.py) | C | `a3285cf` (10-22 17:45) | III-5 kick: settle to t=600, cull at random to K, follow AFTER periods. Extinctions, trough depths, and the rebound's first peak and trough. argv: K, seeds, 'global' for free contact. | [iii5_knock.txt](output/iii5_knock.txt) |
| [probe_iii5_cap.py](probe_iii5_cap.py) | C | `a3285cf` (10-22 17:48) | Diagnostic only: III-5 (and III-4) with every birth blocked while the population exceeds CAP. Does a birth shut-off at high density alone give the book's near-zero troughs and extinction? | [iii5_cap.txt](output/iii5_cap.txt) (`III-5 1000,1200`) |
| [probe_block.py](probe_block.py) | C | `45ba229` (10-22 17:58) | Diagnostic only: candidate readings that might block births at peak density, on III-5 and III-4. once = own fertility tested once at the start of the agent's turn (p.56: "each fertile agent executes S"; the loop checks the neighbor), then a child with every fertile opposite-sex neighbor that has room m12 = founders' metabolism 1-2 (proxy for metabolism variation surviving into the cycles) Reports extinctions, troughs, late range, mean metabolism late, multiple births per birth-turn. | [block_iii5.txt](output/block_iii5.txt) |
| [probe_lowland.py](probe_lowland.py) | C | `45ba229` (10-22 18:04) | Diagnostic only (not a reading of the book): lower the high-density ceiling while leaving the peaks alone, by zeroing every capacity-1 site. Does a steeper income-density curve alone give the book's III-5 extinction, III-4 swings, III-3 floor, and what does it do to III-1's level? | [lowland.txt](output/lowland.txt) |
| [probe_inherit_fert.py](probe_inherit_fert.py) | C | `45ba229` (10-22 18:07) | Diagnostic: p.56's "genetic makeup (metabolism, vision, maximum age, and so forth)" read to include fertility ages. A child takes its fertility onset from a random parent and its fertility end from its same-sex parent (fresh draws are our current call). Effect on III-1, III-3, III-4, III-5, and the spread of fertility ages late. | [inherit_fert.txt](output/inherit_fert.txt) |
