# Sugarscape xxl, stage 5c: smaller trade steps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Rule 15 (a trade step a set share of today's unit), readings in goods moved, and the report's goods-based bars and ranking, ready to screen arms S (step 0.1) and SM (step 0.1 with Rule 14) against today.

**Architecture:** One `XxlRules` field scales both goods of a unit in `trade_unit!`, used by both price rules. The trade observer adds per-period sugar moved by pair type and a per-agent sugar-moved column to the snapshot. The report reads volume bars in goods, ranks traders by goods moved when the snapshot has it, and reads stage 5's and 5b's folders as now.

**Tech Stack:** Julia (`julia/`, module `Sugarscape`), `Test`.

**Spec:** `docs/superpowers/specs/2026-11-05-xxl-trade-step-design.md` (approved by the user). Read it first.

## Global Constraints

- Branch `xxl-trade-step` (worktree `.claude/worktrees/xxl-trade-step`), from `xxl-trade-price` 604e60b. Merging and pushing are the user's calls.
- With the step at 1, every run's CSV stays byte-identical and fingerprints unchanged: `julia/test/test_xxl_same_run.jl` digests and `julia/test/fixtures/xxl-v1/*.csv` must pass unchanged.
- Only the step's size changes in `bargain!`: both price rules, the welfare and no-crossing tests, trading once with each neighbour in random order stay as they are.
- Every volume bar reads goods moved, never exchanges counted (**the user's**). Traders in the matched ratio are ranked by sugar moved (**the user's**).
- `XXL_DEFAULTS` and `XXL_V1` don't change. Rule 13 stays off.
- No study run (`xxl_trade_study.jl`, `xxl_extinction.jl`, `xxl_scorecard.jl`) without the user's go-ahead; the suite and scratch dry runs are fine. Never write into `C:\Projects\Sugarscape2026\results-julia-xxl`.
- Suite before every commit to `julia/src`, in the background. Files LF. Docs in `docs/xxl.md`'s plain style.

## Review Focus

1. **A step so small that a meeting is very long** (an agent with large holdings and a wide gap): the meeting still ends (the no-crossing test must fail), and run time stays reasonable. Test in Task 2 (a hand-made pair counts its steps and ends).
2. **A stage-5 or 5b folder used as a baseline** in a report whose arm folders have the new columns: the report reads it, ranks its traders by exchanges and says so, and the bars that need goods by pair or goods per agent come from the extra baseline run. Test in Task 4.
3. **`--set trade_step=0.1` together with `trade_rounding = "down"`** (a VAR-inttrade experiment): refused, with a clear message. Test in Task 1.
4. **A seed where an agent in the snapshot moved no sugar**: ranks at the bottom of its cell, ties broken by id as now. Test in Task 4.
5. **Rule 15 with Rule 14**: every step of a meeting trades at the meeting's price, at a tenth of the unit. Test in Task 2.

---

### Task 1: Rule 15 settings

**Files:** `julia/src/xxl/types.jl`, `julia/src/config.jl`, `julia/src/xxl/transform.jl`, `docs/xxl.md` (a "Rule 15: the trade step" section after Rule 14, the settings row, refusals, fingerprint text); test `julia/test/test_xxl_trade_step_switch.jl` (new).

**Interfaces:** Produces `XxlRules.trade_step::Float64 = 1.0`, after `trade_price`; `xxl_on(cfg, :trade_step)` true when `cfg.xxl.trade_step != 1.0`.

- [ ] **Step 1: Write the failing tests:** `XXL_DEFAULTS.trade_step == 1.0` and its `rules_line`/fingerprint unchanged; `to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; trade_step=0.1)).xxl.trade_step == 0.1`; `endswith(rules_line(replace_rules(XXL_DEFAULTS; trade_step=0.1)), "disease_lengths=(9, 10) trade_step=0.1")`, and with `trade_price="meeting"` too the line ends `trade_price="meeting" trade_step=0.1`; refused (`ArgumentError`): `trade_step=0.0`, `-0.1`, `1.5`, `NaN`, `Inf`, and `0.1` on a VI-1 config with `trade_rounding="down"`, and on a config without trade reaching `Config` directly; II-4 resets it to 1.0 and keeps the defaults' fingerprint; `rule_setting("trade_step=0.1") == (:trade_step => 0.1)`.
- [ ] **Step 2: Run them to see them fail.** `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["trade_step_switch"])'`. Expected: no field `trade_step`.
- [ ] **Step 3: Implement** as the Interfaces say, beside Rules 13 and 14.
- [ ] **Step 4: New tests, then the suite.** Expected: pass; digests unchanged.
- [ ] **Step 5: Commit** `julia xxl: rule 15 settings, the trade step (1 by default)`.

### Task 2: The step in `trade_unit!`

**Files:** `julia/src/rules/trade.jl`; test `julia/test/test_xxl_trade_step.jl` (new).

**Interfaces:** Consumes Task 1's field. In `trade_unit!` (~l.49), when the step isn't 1 both `sugar` and `spice` are multiplied by it, after the unit-size choice; with the step at 1 the code does today's operations exactly (branch, don't multiply by 1.0 — or show the digests unchanged either way). `bargain!` reads the step once per call and passes it.

- [ ] **Step 1: Write the failing tests** on two hand-made agents (copy the setup of `julia/test/test_xxl_meeting_price.jl`): with step 0.1 each logged exchange moves a tenth of the book's unit at its price (`e.sugar == 0.1` when p > 1, `e.spice == 0.1` when p < 1); the meeting takes more steps than with step 1 and moves at least as much sugar in all; it ends (count < 10,000); with Rule 14 on as well every step has the meeting's starting price; a 12-period VI-1 run with step 1 gives the same `seed20.csv` bytes as `XXL_DEFAULTS`; 12-period runs with step 0.1, with and without Rule 14, run without error.
- [ ] **Step 2: Run them to see them fail.** Expected: exchanges move whole units.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: New tests, then the suite.** Expected: pass; digests unchanged.
- [ ] **Step 5: Commit** `julia xxl: rule 15, a trade step a share of the book's unit`.

### Task 3: Goods moved in the trade readings

**Files:** `julia/src/xxl/trade_readings.jl`; test `julia/test/test_xxl_trade_readings.jl` (add).

**Interfaces:** Produces:
- per-period columns appended at the end of `TRADE_COLUMNS`: `sugar_moved`, `sugar_hh`, `sugar_hs`, `sugar_ss` (sugar moved in the period's exchanges, in all and by pair type with recovering counted as healthy, as `exchanges_hh/hs/ss` are), `spice_moved`;
- a column appended at the end of `TRADE_AGENT_COLUMNS`: `sugar_moved_window`, the sugar an agent moved (bought or sold) in the window's exchanges;
- `STAGE5B_TRADE_COLUMNS` and `STAGE5B_AGENT_COLUMNS` (today's lists before this task) exported to the report, so it can tell folder formats apart.

- [ ] **Step 1: Write the failing tests:** on a hand-filled trade log, the sugar columns equal hand sums (two hh exchanges of 0.1 and 0.3, one hs of 1.0: `sugar_hh == 0.4`, `sugar_hs == 1.0`, `sugar_moved == 1.4`); on a short VI-1 run, `sugar_moved` equals the seed CSV's `sugar_traded` each period and `sugar_hh + sugar_hs + sugar_ss == sugar_moved`; a snapshot agent's `sugar_moved_window` equals the sum of `e.sugar` over its window exchanges; an agent with no exchanges has 0; the observer still changes nothing in a run.
- [ ] **Step 2: Run them to see them fail.** Expected: no column `sugar_moved`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Readings tests, then the suite.** Expected: pass.
- [ ] **Step 5: Commit** `julia xxl: trade readings count sugar moved, by pair and per agent`.

### Task 4: The report reads goods

**Files:** `julia/src/xxl/trade_report.jl`; test `julia/test/test_xxl_trade_report.jl` (add).

**Interfaces:** Consumes Task 3's columns and lists; Task 1's fingerprint text. Produces:
- the header checks accept three trade-column sets (stage 5's, 5b's, current) and two snapshot sets (without and with `sugar_moved_window`), missing columns NaN; anything else refused;
- `matched_ratio` ranks each cell by `sugar_moved_window` when the snapshot has it (ties by id), otherwise by `exchanges` as now, and the report says which ranking each run used;
- the no-disease bar reads sugar moved per head, Σ `sugar_traded` ÷ Σ population over t = 301–500 per seed then the mean over seeds (as trades per head is read now), against ×2 today's;
- the sick-agents bar reads (Σ `sugar_hs` + 2·Σ `sugar_ss`) ÷ Σ sick over t = 301–500, against ×0.5 today's; a run without the columns reads it as missing, and the arm can't pass on a missing bar;
- readings rows: sugar moved per head by pair (hh/hs/ss), spice moved per head, exchanges per head (shown, deciding nothing), sugar per meeting (Σ `sugar_moved` ÷ Σ `meetings`), and a note that X6 is weighted by exchanges;
- the arms table names Rule 15 with Rule 14 and Rule 13 (`step 0.1`, `meeting price; step 0.1`);
- the screening base may mix folders of different formats (VI-1 from the new baseline run, no-disease and IV-A3 from stage 5's Part 1).
- [ ] **Step 1: Write the failing tests** with hand-written folders: a screening report with a base whose VI-1 folder has the new columns and whose no-disease and IV-A3 folders are stage 5's, and arms with the new columns and `trade_step=0.1`: the no-disease and sick bars read goods (hand values), the matched ratio ranks by `sugar_moved_window` (a fixture where ranking by exchanges and by sugar give different ratios, asserting the sugar one), the arms table names the step; a stage-5 VI-1 base reads the sick bar as missing; a snapshot agent with no sugar moved ranks last in its cell; a trade file with any other column set is refused.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Report tests, then the suite.** Expected: pass.
- [ ] **Step 5: Commit** `julia xxl: the trade report reads goods moved and ranks traders by them`.

### After the tasks (controller)

- Final whole-branch review; a scratch dry run (4 periods, 1 seed) of the baseline run and both arms; then **ask the user** before any run.
- On the user's go-ahead: the baseline run `xxl_trade_study.jl --label p1b-today` (VI-1, seeds 80–99, 500 periods), its `seed<k>.csv` checked byte-identical with `trade-p1-today-VI-1-s80-20-p500`'s; arms S (`--set trade_step=0.1`) and SM (`--set trade_step=0.1 --set trade_price=meeting`) each in VI-1, the no-disease world (`--set founder_diseases=0` too) and IV-A3 (300 periods), every fingerprint checked at launch; then the report's screening mode with `--base today=trade-p1b-today-VI-1-s80-20-p500,trade-p1-nodisease-VI-1-s80-20-p500,trade-p1-today-IV-A3-s80-20-p300`, `--arms S=…,SM=…`, `--off trade-p1-off-VI-1-s80-20-p500`, `--xl scorecard-xl-s80-20/VI-1`, label `screen-step`. Apply the spec's results table by hand.
- Findings in `docs/xxl.md` after "Stage 5b", reviewed, committed with the user's approval.
