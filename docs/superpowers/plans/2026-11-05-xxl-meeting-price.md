# Sugarscape xxl, stage 5b: the meeting's price — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Rule 14 (a meeting's price is set once, at the geometric mean of the two starting MRSs, for every unit), readings that show its effect, and the report's support for it, ready to screen one arm against stage 5's baseline.

**Architecture:** One `XxlRules` field read in `bargain!`; the price and the buyer are hoisted out of the unit loop when it's on, and every test on a unit stays as the book has it. The trade observer counts meetings from runs of consecutive exchanges between the same pair, which needs no change to the simulation. The report reads the new columns when present and the stage-5 folders without them.

**Tech Stack:** Julia (`julia/`, module `Sugarscape`), `Test`.

**Spec:** `docs/superpowers/specs/2026-11-05-xxl-meeting-price-design.md` (approved by the user). Read it first.

## Global Constraints

- Branch `xxl-trade-price` (worktree `.claude/worktrees/xxl-trade-price`), from `xxl-trade` bf4aa65. Merging and pushing are the user's calls.
- With Rule 14 off, every run's CSV stays byte-identical and fingerprints unchanged: `julia/test/test_xxl_same_run.jl` digests and `julia/test/fixtures/xxl-v1/*.csv` must pass unchanged.
- Only the price changes in `bargain!`: unit sizes (p > 1: 1 sugar for p spice; p < 1: 1/p sugar for 1 spice; whole units with `trade_rounding = "down"`), the positive-holdings test, the no-crossing test (`mrs(hi) >= mrs(lo)`), both welfares strictly rising, and trading once with each neighbour in random order stay as they are.
- `XXL_DEFAULTS` and `XXL_V1` don't change. Rule 13 stays off and isn't combined with Rule 14 in any arm.
- No study run (`xxl_trade_study.jl`, `xxl_extinction.jl`, `xxl_scorecard.jl`) without the user's go-ahead. The test suite and scratch dry runs are fine.
- Suite: `julia --project=julia -e 'using Pkg; Pkg.test()'` (about 12 min), in the background, before every commit that touches `julia/src`. Files LF.
- Docs in the plain style of `docs/xxl.md`; the user's decisions and my calls marked as the spec marks them.

## Review Focus

1. **A meeting whose first unit fails** (the starting price leaves one side no better off, e.g. MRSs nearly equal): no exchange is logged and no meeting is counted. Test in Task 2 and Task 3.
2. **Rule 14 with `trade_rounding = "down"`** (VAR-inttrade experiments under xxl): whole units at the meeting's price, never a zero-unit exchange. Test in Task 2.
3. **Rule 14 and Rule 13 both set:** runs without error (no arm uses it, but a person may set both). Test in Task 2 (a 12-period run).
4. **A stage-5 baseline folder** (trade files without the new columns, a fingerprint without Rule 14, made by older code): the report reads it, shows the new readings as missing for it, and names its rule as the book's. Test in Task 4.
5. **A period with a single meeting or none:** the price spread across meetings is NaN, not 0 or an error. Test in Task 3.

---

### Task 1: Rule 14 settings

**Files:**
- Modify: `julia/src/xxl/types.jl` (field, docstring), `julia/src/config.jl` (validation beside Rule 13's), `julia/src/xxl/transform.jl` (reset without trade, `xxl_on`)
- Modify: `docs/xxl.md` (a "Rule 14: the meeting's price" section after Rule 13, the settings-table row, refused combinations, fingerprint text)
- Test: `julia/test/test_xxl_meeting_price_switch.jl` (new)

**Interfaces:**
- Produces: `XxlRules.trade_price::Union{Nothing,String} = nothing`, after `trade_guard`; allowed values `nothing` and `"meeting"`.
- Produces: `xxl_on(cfg, :trade_price)` true when `cfg.xxl.trade_price !== nothing`.

- [ ] **Step 1: Write the failing tests:**
  - `XXL_DEFAULTS.trade_price === nothing`; `rules_line(XXL_DEFAULTS)` and `xxl_fingerprint(vi1, XXL_DEFAULTS)` unchanged (no `trade_price`).
  - `to_xxl(vi1.config, replace_rules(XXL_DEFAULTS; trade_price="meeting")).xxl.trade_price == "meeting"` and `xxl_on(cfg, :trade_price)`.
  - `endswith(rules_line(replace_rules(XXL_DEFAULTS; trade_price="meeting")), "disease_lengths=(9, 10) trade_price=\"meeting\"")`.
  - refused (`ArgumentError` from `to_xxl` on VI-1): `trade_price="ask"`; and on a config without trade reaching `Config` directly (pattern: the Rule 13 test in `test_xxl_trade_move_switch.jl`).
  - II-4 (no trade): `to_xxl` resets it to `nothing`, and its fingerprint equals the one under `XXL_DEFAULTS`.
  - `rule_setting("trade_price=meeting") == (:trade_price => "meeting")`, `rule_setting("trade_price=nothing") == (:trade_price => nothing)`.
- [ ] **Step 2: Run them to see them fail.** `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["meeting_price_switch"])'`. Expected: FAIL, no field `trade_price`.
- [ ] **Step 3: Implement** as the Interfaces say; docs as listed.
- [ ] **Step 4: Run the new tests, then the suite in the background.** Expected: pass; digests unchanged.
- [ ] **Step 5: Commit** `julia xxl: rule 14 settings, the meeting's price (off by default)`.

### Task 2: The meeting's price in `bargain!`

**Files:**
- Modify: `julia/src/rules/trade.jl` (`bargain!` and its docstring)
- Test: `julia/test/test_xxl_meeting_price.jl` (new)

**Interfaces:**
- Consumes: Task 1's field.
- Produces: with `m.config.xxl.trade_price == "meeting"`, `bargain!(m, a, b)` computes `ma, mb` once at the start (no trade if either isn't `valid_mrs` or they're equal), `price = sqrt(ma * mb)`, and `hi, lo` (the higher-MRS agent buys sugar) once; then repeats the book's unit at that price, accepting each unit only under the book's tests, until one fails. Off: the loop as today, the same operations.

- [ ] **Step 1: Write the failing tests** with two hand-made agents and a small model (pattern: the `bargain!` tests in `julia/test/test_xxl_trade_price.jl`):
  - with the rule on, every logged exchange of the meeting has the same price, equal to `sqrt(mrs(a) * mrs(b))` taken before the call;
  - the meeting stops at the first unit that would not raise both welfares: after it, one more unit at that price would fail `welfare_rises` for one of them;
  - on the same pair the book's rule (rule off) logs different prices and a different number of units;
  - a pair with nearly equal MRSs, whose first unit fails at the meeting's price, logs nothing;
  - with `trade_rounding = "down"`, every unit moves whole amounts at least 1;
  - a 12-period VI-1 run under `XXL_DEFAULTS` with Rule 14 off gives the same `seed20.csv` bytes as plain `XXL_DEFAULTS` (pattern: the "same bytes" test in `test_xxl_trade_move_switch.jl`); one with Rule 14 on, and one with Rule 13 and Rule 14 both on, run without error.
- [ ] **Step 2: Run them to see them fail.** Expected: the meeting's prices differ unit to unit.
- [ ] **Step 3: Implement** as the Interfaces say. Keep the rule-off path's floating-point operations exactly as they are.
- [ ] **Step 4: Run the new tests, then the suite in the background.** Expected: pass; digests unchanged.
- [ ] **Step 5: Commit** `julia xxl: rule 14, a meeting trades every unit at its starting price`.

### Task 3: Meetings in the trade readings

**Files:**
- Modify: `julia/src/xxl/trade_readings.jl`
- Test: `julia/test/test_xxl_trade_readings.jl` (add)

**Interfaces:**
- Produces: two per-period columns appended at the end of `TRADE_COLUMNS`: `meetings` (the period's number of meetings) and `meeting_price_sd` (the population sd of log price over the period's meetings, each meeting's price taken from its first exchange; NaN with fewer than 2 meetings).
- A meeting is a maximal run of consecutive `m.trade_log` entries between the same two agents (unordered, by id). This holds because `bargain!` runs a pair's whole meeting before the next pair's (*my call*: it needs no change to the simulation).

- [ ] **Step 1: Write the failing tests:**
  - on a hand-filled trade log (three exchanges a–b, two c–d, one a–b again later), `meetings == 3` and `meeting_price_sd` equals the sd of the three first prices by hand;
  - one meeting or none gives `meeting_price_sd` NaN;
  - on a short VI-1 run with Rule 14 on, the sum of exchanges equals the `exchanges` column, `meetings <= exchanges`, and every meeting's exchanges share one price; with it off, meetings still count (prices vary within one);
  - the observer still changes nothing in the run (the existing sameness test passes with the new columns).
- [ ] **Step 2: Run them to see them fail.** Expected: no column `meetings`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the readings tests, then the suite in the background.** Expected: pass.
- [ ] **Step 5: Commit** `julia xxl: trade readings count meetings and their price spread`.

### Task 4: The report reads Rule 14 and stage 5's folders

**Files:**
- Modify: `julia/src/xxl/trade_report.jl`
- Test: `julia/test/test_xxl_trade_report.jl` (add)

**Interfaces:**
- Consumes: Task 3's columns; the fingerprint line `trade_price="meeting"` from Task 1.
- Produces:
  - the header check (`th == TRADE_COLUMNS`, ~l.101) also accepts a trade file whose columns are exactly stage 5's (today's `TRADE_COLUMNS` without the two new ones), reading the missing columns as NaN; anything else is refused as now;
  - `rule13_of` becomes a reader of every trade rule in the fingerprint (Rule 13's three fields and `trade_price`), and the arms table's rule text names Rule 14 when it's set (`meeting price`), Rule 13 when it's set, and "the book's" when neither;
  - two readings rows: "Units per meeting" (Σ exchanges ÷ Σ meetings over t = 301–500) and "Price spread across meetings" (mean of `meeting_price_sd` over t = 301–500, NaN periods left out), "—" for a run without the columns;
  - the report already ignores the code checksum when comparing a baseline with an arm; keep it that way and test it.
- [ ] **Step 1: Write the failing tests** with hand-written folders (pattern: the folder helpers at the top of `test_xxl_trade_report.jl`):
  - a screening report with a baseline folder in stage 5's column format and an older code checksum, and an arm folder with the new columns and `trade_price="meeting"`: it runs, the arms table reads "the book's" and "meeting price", the new readings show "—" for today and figures for the arm;
  - a trade file with any other column set is refused (`ArgumentError`);
  - Units per meeting and the price spread match hand computations on the arm folder.
- [ ] **Step 2: Run them to see them fail.** Expected: the stage-5 folder is refused.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the report tests, then the suite in the background.** Expected: pass.
- [ ] **Step 5: Commit** `julia xxl: the trade report names rule 14 and reads stage 5's folders`.

### After the tasks (controller, not a subagent task)

- Final whole-branch review, then a scratch dry run of the three study commands at 4 periods, 1 seed (`--set trade_price=meeting`), then **ask the user** before screening.
- Screening, on the user's go-ahead: `xxl_trade_study.jl --label arm-M --set trade_price=meeting` in VI-1, `--label arm-M-nodisease` with `--set founder_diseases=0`, and IV-A3 at 300 periods, seeds 80–99, `--jobs 5`, `--out` the main `results-julia-xxl`; then `xxl_trade_report.jl` screening mode with `--base today=trade-p1-today-VI-1-s80-20-p500,trade-p1-nodisease-VI-1-s80-20-p500,trade-p1-today-IV-A3-s80-20-p300`, `--arms M=…`, `--off trade-p1-off-VI-1-s80-20-p500`, `--xl scorecard-xl-s80-20/VI-1`, `--label screen-meeting`.
- Findings in `docs/xxl.md` after "Stage 5: trade", reviewed, committed with the user's approval.
