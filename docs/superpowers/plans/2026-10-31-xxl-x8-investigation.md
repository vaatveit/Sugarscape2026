# xxl stage 3: what X8 measures — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find out what X8 measures and whether credit works, by tracing every loan in VI-1, without changing the rules.

**Architecture:** An opt-in `LoanTrace` on the model, called from `rules/credit.jl`, follows each chain of a loan and its rollovers and adds to fixed tallies; every 50 periods it also takes a census of the living. Each seed writes its tallies, its census and a 1-in-100 sample of loans beside the usual CSV. A report turns those into the design's four answers and its readings, and `julia/xxl_loan_trace.jl` is the command line, modelled on `xxl_extinction.jl`.

**Tech Stack:** Julia 1.13 (project `julia/`), stdlib `Distributed`, `Test`. No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md`

## Global Constraints

- Branch `xxl-x8-investigation`, cut from `main` at `b11e3b8`, in the main checkout at `C:\Projects\Sugarscape2026`, so results land in its `results-julia-xxl/` beside the reference runs. No merge, no push.
- No change to the rules, to `XXL_DEFAULTS`, or to X8's definition or threshold. Julia only.
- With the tracer off, nothing changes. With it on, the run's CSV doesn't change: the tracer draws no random numbers and alters no loan or agent.
- No existing test changes. Existing tests must pass as they are.
- Traced runs never pass `checkpoint`. A stopped seed restarts from period 0.
- Windows: t = 1–100, 101–500, 501–end. The report also gives 1–500, X8's own window.
- Age bands: 5 wide, named by lower edge (`"0"`, `"5"`, … `"95"`); age 100 and over goes in `"95"`.
- The census: every 50 periods from t = 50, following each agent for d + 1 periods (d the loan term, 10 with credit off).
- Reading lines, from the spec: age ratio within 0.9–1.1 on both sides; lender-only voids over 0.5 of voids; doomed loans over 0.25 of voids; a borrower's matched ratio above 1.1 for sugar or spice; borrowing agents' child share within 1.1× could-borrow agents'; with credit off, births and end population within 5%.
- Comments and docstrings match the surrounding code: terse, plain, 120 columns, LF endings.
- Commit lines end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commits follow the user's standing rule: only once the user has approved this plan's commit steps. That approval doesn't cover merging or pushing.
- Run every command with the Bash tool, from the repository root. Test one file with `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan"])'`.
- Once a long run starts, make no edit under `julia/src`: the source hash is in the fingerprint, and the run would refuse to resume.

## Review Focus

1. A party with several loans dying: each of its chains ends once, and a lender with two loans to one borrower gives two voids.
2. A loan made and voided in the same period: it counts once, as the scorecard counts it, in the same window.
3. A stop between writing a seed's files: a seed counts as done only with all of them, and an unfinished seed reruns from zero.
4. Nothing to divide by: an extinct seed, a run shorter than one census, a band with no comparison group, credit off. The report says `—`, never `NaN` or an error.
5. A chain that rolls over and then dies: voided, with its partial payments still counted as received.

Each has its test in Task 1, 2, 3 or 4.

---

### Task 1: The loan tracer

**Files:**
- Create: `julia/src/xxl/loan_trace_types.jl`, `julia/src/xxl/loan_trace.jl`
- Modify: `julia/src/Sugarscape.jl` (include the types after `agent.jl`, the rest after `xxl/scorecard_metrics.jl`), `julia/src/model.jl`, `julia/src/rules/credit.jl`, `julia/src/runner.jl`, `julia/src/xxl/scorecard_metrics.jl`
- Test: `julia/test/test_xxl_loan_trace.jl`

**Interfaces:**
- Produces:
  - `LoanTrace(term::Int; census_every::Int=CENSUS_EVERY, sample_every::Int=SAMPLE_EVERY)`, with `CENSUS_EVERY = 50`, `SAMPLE_EVERY = 100`. Holds an `IdDict{Loan,Chain}` of open chains, the period's pending voids, a `Dict` of tallies and the sampled rows.
  - `tally(tr::LoanTrace, window::Int, table::String, key1="", key2="") -> Float64`, 0 if absent.
  - `window_index(t::Int) -> Int`: 1 for t ≤ 100, 2 for t ≤ 500, else 3.
  - `age_band(age::Real) -> String`.
  - `trace_start!(tr, m, loan)`, `trace_repaid!(tr, m, loan)`, `trace_rolled!(tr, m, old, new, paid)`, `trace_void!(tr, m, loan)`, `trace_inherit!(tr, m, old, copies)`, `trace_period!(tr, m)`, `trace_finish!(tr, m)`.
  - `death_cause(m, a) -> Symbol`, one of `:killed`, `:old_age`, `:sugar`, `:spice`, in `scorecard_metrics.jl`; `scorecard_metrics!` calls it.
  - `Model` gains a last field `loan_trace::Union{Nothing,LoanTrace}`, `nothing` from the constructor.
  - `timed_seed` and `seed_job` gain the keyword `loan_trace=nothing`. `seed_job` passes it to `run_seed` only when set, like `checkpoint`. `timed_seed` throws `ArgumentError` when given both `loan_trace` and `checkpoint`.

**The tally tables.** A key is `(window, table, key1, key2)`, all counts weighted (see inheritance). An outcome is `repaid`, `voided_lender`, `voided_borrower` or `voided_both`.

| Table | key1 | key2 | Window by | Value |
|---|---|---|---|---|
| `started` | | | start | chains begun |
| `started_bands` | lender's band | borrower's band | start | chains begun |
| `party_kind` | `lender` / `borrower` | `past_fertile` / `fertile` | start | chains begun |
| `party_sex` | `lender` / `borrower` | `M` / `F` | start | chains begun |
| `ended` | outcome | | end | chains ended |
| `rolled` | | | event | rollovers |
| `void_cause` | party that died | cause | end | deaths; a `voided_both` gives one row per party |
| `void_age` | party that died | its band | end | as above |
| `void_elapsed` | outcome | periods since the chain began | end | chains ended |
| `doomed` | `neither` / `lender` / `borrower` / `both` | outcome | end | chains ended |
| `principal` | outcome | | end | first principal × weight |
| `received` | outcome | | end | sugar the lender got, all payments |
| `child` | outcome | `yes` / `no` | end | chains ended |
| `unfinished` | | | the run's last period | chains still open |

**When things happen,** from `step!`. During a step `m.t` is T; the scorecard labels that period T + 1, since `m.t` rises at the end of `step!`. So every window here is `window_index(m.t + 1)` inside a step, and `trace_period!`, called after `step!`, sees the label itself.

**Doomed.** A party of age `a` when the loan starts is certain to die before settlement when `a + d + 1 >= max_age`: `step!` ages then kills before `settle_loans!`, and the loan is settled d steps later.

**Which side died** is decided in `trace_period!`, not at the void: a borrower can starve in the sweep and its lender die of old age later in that period. A void goes in the pending list with its chain and the agents; at period end, `!borrower.alive && !lender.alive` is `voided_both`, otherwise the side that is dead. `m.killed` and each agent's age and sugar are still as they were, so `death_cause` holds then. Pending entries are cleared each period, so the trace keeps no dead agent past its period.

**A child during the chain** is read when the chain ends, against `length(borrower.children)` at its start. `kill!` empties that list, but `credit_on_deaths!` runs before `kill!`, so a void still sees it.

**Inheritance.** A chain's copies keep its number, its start and its first principal, each with weight `w / k`, and each adds to the tallies with that weight, so they add up to one chain. A copy's `lender` is the heir.

**Sampled rows,** every chain whose number is divisible by `sample_every`, at its end or at finish: `chain,t_start,t_end,outcome,rollovers,weight,lender_id,lender_age,lender_max_age,lender_sex,lender_sugar,borrower_id,borrower_age,borrower_max_age,borrower_sex,borrower_sugar,borrower_income,principal,due,received,child,doomed`. Sugar is as it stood after the loan was made. Unfinished chains have `outcome` `unfinished` and `t_end` empty; a copy gives its own row.

- [ ] **Step 0: Cut the branch and commit the design and this plan**

```bash
git checkout -b xxl-x8-investigation main
git add docs/superpowers/specs/2026-10-31-xxl-x8-investigation-design.md docs/superpowers/plans/2026-10-31-xxl-x8-investigation.md
git commit -m "docs: stage 3's X8 investigation: design and plan"
```

- [ ] **Step 1: Write the failing tests in `test_xxl_loan_trace.jl`**

Hand-built worlds use `tiny_model` and `put_agent` from `helpers.jl`, a hand-made loan via `add_loan!` and `trace_start!`, and `step!` followed by `trace_period!`. Each test, by `@testset` name:

- `"loan trace: a window and a band"`: `window_index` at 1, 100, 101, 500, 501 gives 1, 1, 2, 2, 3. `age_band` at 0, 4.9, 5, 99, 100, 120 gives `"0"`, `"0"`, `"5"`, `"95"`, `"95"`, `"95"`.
- `"loan trace: repaid"`: lender and fed borrower, `credit=(2, 0.0)`, `principal=5.0`, due 5.0. After the due step: `ended repaid` 1, `received repaid` 5.0, `principal repaid` 5.0, nothing open.
- `"loan trace: a lender dies"`: lender `max_age` one step away. `ended voided_lender` 1, `received` 0, `void_cause lender old_age` 1, `void_age lender` at its band 1.
- `"loan trace: a borrower starves"`: `void_cause borrower sugar` 1 and `ended voided_borrower` 1. With sugar kept and spice run out, in a spice world: `void_cause borrower spice` 1.
- `"loan trace: both die in one period"`: borrower starves in the sweep and lender reaches `max_age` that period. `ended voided_both` 1, one `void_cause` row for each party.
- `"loan trace: two loans from one lender"` (Review Focus 1): two loans between one pair; the lender dies. `ended voided_lender` 2.
- `"loan trace: made and voided in one period"` (Review Focus 2): a lender at its last period lends through `seek_credit!` in `step!`. `started` and `ended voided_lender` are both 1 in window 1.
- `"loan trace: rollovers"`: a poor borrower rolls over twice, then repays. `rolled` 2, `started` 1, `ended repaid` 1, `received` the partials plus the final payment, and the lender's sugar gained exactly `received`.
- `"loan trace: rolls over, then dies"` (Review Focus 5): `ended voided_borrower` 1, `received voided_borrower` the partial paid, above 0.
- `"loan trace: doomed at the start"`, with `credit=(5, 0.0)`: a lender with `age = 4`, `max_age = 10` has 4 + 5 + 1 = 10, so `doomed lender voided_lender` is 1. With `max_age = 11` the loan is repaid and `doomed neither repaid` is 1. This pins the d + 1 against `step!`.
- `"loan trace: inheritance"`: `inheritance=true`, a dying lender with 2 living children. Then both copies repaid: `ended repaid` ≈ 1, `started` 1, `received repaid` the whole due, and nothing is voided.
- `"loan trace: a child during the chain"`: a borrower with a child added between start and end gives `child repaid yes` 1; none gives `no`. A borrower who has a child and then dies gives `child voided_borrower yes` 1.
- `"loan trace: a sampled chain"`: with `sample_every=1`, one row per chain, its fields as above; with 100 and 3 chains, none.
- `"loan trace: the run is the same"`: VI-1 under `XXL_DEFAULTS`, cut to 30 periods with `with_steps`, through `timed_seed`, with and without `loan_trace`: `isequal` rows.
- `"loan trace: the counts are the scorecard's"`: the same VI-1, 120 periods, through `timed_seed` with `scorecard=true` and `loan_trace`. Summed over rows in each window, `loans_started`, `loans_repaid`, `loans_voided` and `loans_rolled` equal `started`, the sum of `ended` for repaid, the sum of the three void outcomes and `rolled`, exactly. Assert `loans_voided` above 0 so the test can't pass empty. And `started` = all ended + `unfinished` after `trace_finish!`.
- `"loan trace: not with a checkpoint"`: `timed_seed` with both throws `ArgumentError`.

- [ ] **Step 2: Run them to see them fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan"])'`
Expected: FAIL, `LoanTrace` not defined.

- [ ] **Step 3: Add the types, the field and `death_cause`**

`LoanTrace` and `Chain` go in `loan_trace_types.jl`, as `Model` must name them. In `Model(...)` the last constructor argument is `nothing`. `checkpoint.jl` needs no change: it saves plain fields by name. Move the cause chain from `scorecard_metrics!` into `death_cause`, order unchanged.

- [ ] **Step 4: Add the hooks to `rules/credit.jl`**

Each is one line, `m.loan_trace === nothing || trace_x!(m.loan_trace, m, ...)`, changing nothing else:

- `seek_credit!`: after `add_loan!`, `trace_start!`.
- `settle_loans!`: in the repaid branch `trace_repaid!`; after a rollover's `add_loan!`, `trace_rolled!(…, loan, new, paid)`.
- `credit_on_deaths!`: in the borrower branch `trace_void!`; in the lender branch, `trace_inherit!(…, loan, copies)` when the loan passed to heirs, else `trace_void!`. Collect the copies as they are pushed to `keep`.

- [ ] **Step 5: Implement `loan_trace.jl` and the runner keyword**

`timed_seed`: after building the model, `m.loan_trace = loan_trace`; after each `step!`, `trace_period!`; before returning, `trace_finish!`. Time them as metrics. Add the census in Task 2; for now `trace_period!` resolves pending voids only.

- [ ] **Step 6: Run the tests, then the whole suite**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan"])'`, then `julia --project=julia -e 'using Pkg; Pkg.test()'`
Expected: PASS, with no existing test changed.

- [ ] **Step 7: Commit**

```bash
git add julia/src/xxl/loan_trace_types.jl julia/src/xxl/loan_trace.jl julia/src/Sugarscape.jl julia/src/model.jl julia/src/rules/credit.jl julia/src/runner.jl julia/src/xxl/scorecard_metrics.jl julia/test/test_xxl_loan_trace.jl
git commit -m "julia xxl: an opt-in trace of every loan's life"
```

### Task 2: The census

**Files:**
- Modify: `julia/src/xxl/loan_trace.jl`, `julia/src/xxl/loan_trace_types.jl`
- Test: `julia/test/test_xxl_loan_trace.jl`

**Interfaces:**
- Consumes: `LoanTrace`, `trace_period!`, `age_band`, `window_index`, `death_cause` from Task 1.
- Produces:
  - `census_group(m, a) -> Vector{String}`: the state groups of a living agent, from `borrowing`, `lending`, `could_borrow`, `could_lend`, `other`.
  - `census_row(tr, window, group, band) -> NamedTuple{(:n, :children, :old_age, :sugar, :spice, :killed)}`, zeros if absent. `n` is agents; `children` is those with a child; the rest are deaths.

**The groups.** `borrowing`: `haskey(m.debts, a.id)`. `lending`: `haskey(m.lent, a.id)`. An agent that is both is in both. If neither: `could_borrow` when `shortfall(m, a) > 0 && a.last_income > 0`; else `could_lend` when `available_to_lend(m, a) > 0`; else `other`. Every agent is also in `all`, once.

**The cohort.** `trace_period!` takes a census when `m.t % census_every == 0 && m.t > 0`, with its window from `window_index(m.t)`. A cohort is followed for `term + 1` periods, ending at `m.t + term + 1`. Each `trace_period!` while a cohort is open: for `a` in `m.dead_this_step` with an entry, count its cause by `death_cause` and close the entry; for the entries still alive, note whether `length(a.children)` has risen. At the last period, close the rest as survivors. A child born in the period its parent dies isn't seen, in every group alike. A cohort still open when the run ends is dropped, so its counts never enter the tables. Within one `trace_period!`, follow the open cohort first and then take any new census, so an agent who died that period is in neither.

`census_every > term + 1` is required: `LoanTrace` throws `ArgumentError` otherwise, so cohorts never overlap and one list is enough.

- [ ] **Step 1: Write the failing tests**

- `"census: the groups"`: hand-built agents give `["borrowing"]`, `["lending"]`, `["borrowing", "lending"]`, `["could_borrow"]` (of childbearing age, short of sugar, income above 0), `["could_lend"]` and `["other"]` (short of sugar with income 0 is `other`).
- `"census: the follow-up"`, with `census_every=4`, `credit=(2, 0.0)` so d + 1 = 3, census at t = 4 and following t = 5, 6, 7: an agent reaching `max_age` at t = 7 counts in `old_age`, and one reaching it at t = 8 doesn't, whose `n` still counts. A child at t = 7 counts in `children`; one at t = 8 doesn't.
- `"census: an agent in two groups"`: a borrower-lender adds to `n` in `borrowing`, `lending` and `all`, once each.
- `"census: a cohort unfinished at the end"` (Review Focus 4): a run ending before the follow-up does has no census rows.
- `"census: a run shorter than one census"`: 3 periods gives none, without error.
- `"census: the run is the same"`: repeat Task 1's comparison at 60 periods, so a census falls inside: `isequal` rows with the tracer on and off.
- `"census: cohorts can't overlap"`: `LoanTrace(10; census_every=11)` throws `ArgumentError`, and `census_every=12` doesn't.

- [ ] **Step 2: Run them to see them fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan"])'`
Expected: FAIL, `census_group` not defined.

- [ ] **Step 3: Implement the census in `trace_period!`**

- [ ] **Step 4: Run the tests**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan"])'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add julia/src/xxl/loan_trace.jl julia/src/xxl/loan_trace_types.jl julia/test/test_xxl_loan_trace.jl
git commit -m "julia xxl: a census of the living, for fair comparisons"
```

### Task 3: Files and the report

**Files:**
- Create: `julia/src/xxl/loan_report.jl` (include after `xxl/extinction.jl`)
- Modify: `julia/src/Sugarscape.jl`
- Test: `julia/test/test_xxl_loan_report.jl`

**Interfaces:**
- Consumes: `LoanTrace` and its tallies and census from Tasks 1 and 2; `write_atomic`, `fmt`, `seed_text`, `mean_of`, `read_seed_csv` as they stand.
- Produces:
  - `write_trace_files(folder, k, tr)`: `seed<k>.tally.csv` (`window,table,key1,key2,value`), `seed<k>.census.csv` (`window,group,band,n,children,old_age,sugar,spice,killed`) and `seed<k>.loans.csv` (the sampled rows), each with `write_atomic`. Values print with `format_value`, so they read back exact.
  - `read_tally(path) -> Dict{NTuple{4,String},Float64}`; `read_census(path) -> Vector{NamedTuple}`.
  - `merge_tallies(list)`, `merge_census(list)`: sums over seeds.
  - `x8_share(t, windows) -> Float64`: voids ÷ (voids + repaid) over those windows, `NaN` if none ended.
  - `age_ratios(t, census, windows) -> (; borrower, lender)`.
  - `matched_ratios(census, windows) -> (; borrower::Dict{String,Float64}, lender::Dict{String,Float64}, excluded::Int)`.
  - `child_shares(census, windows) -> (; borrowing, could_borrow)`.
  - `trace_readings(s) -> Vector{String}`, `s` having `age` (from `age_ratios`), `lender_only` and `doomed` (shares of voids), `matched` (from `matched_ratios`) and `child` (from `child_shares`).
  - `credit_off_reading(base, off) -> Union{Nothing,String}`, each having `births` and `population`: the line when both of `off`'s are within 5% of `base`'s, else `nothing`.
  - `loan_summary(folder, indices, periods) -> NamedTuple`: all of these over the seeds finished, with windows `1:2`, `[1]`, `[2]`, `[3]`.
  - `loan_report(s; label, world, first_seed, seeds, periods, jobs, wall) -> String`.
  - `trace_matches_scorecard(tally_path, scorecard_csv) -> Bool`: `started`, `rolled`, repaid and voids in windows 1 and 2 equal the CSV's row sums over t = 1–100 and 101–500, exactly.

**The arithmetic.**

- **Age ratio,** in each window, then summed: `q[band]` is deaths ÷ `n` in census group `all`. Expected deaths on one side = Σ over `started_bands` of chains × `q` at that side's band, then × ended ÷ started in that window, since unfinished loans haven't had their chance to die. Observed on the borrower's side is `voided_borrower` + `voided_both`, and on the lender's `voided_lender` + `voided_both`. A band with no census has `q` 0.
- **Matched ratio,** by direct standardization, for each cause and for `all`: observed deaths in `borrowing` ÷ Σ over bands of `borrowing` `n` × the `could_borrow` death rate at that band. Likewise `lending` against `could_lend`. Bands with no comparison group are left out of both sides, and their agents add to `excluded`.
- **X8 in the report** is the mean over seeds of each seed's `x8_share`, as the scorecard takes it, so it can be compared with the scorecard.

**The report.** These lines, exact wording fixed:

```
# Loan trace: $label
- World: $world
- Seeds finished: $finished of $seeds ($(seed_text(first_seed, seeds)))
- Periods: $periods
- Loans started: $n
- X8, t = 1–500: $x8
- Run time: …
```

Then a section per question, each with a table by window (1–100, 101–500, 1–500, 501–end, those that exist), each stating its census cohorts' count; then `## Reading`, `trace_readings`'s lines; then one row per seed. These must be in the report: the outcome shares (Q1); causes and ages of the dead by side; the median periods elapsed at a void, by side; both ratios by side and cause, the excluded count, and the sentence "The groups aren't randomized, so the matched figures are evidence, not proof." (Q2); doomed share; the principal voided by side, the share of principal voided, what lenders received per unit lent, and what borrowers kept when a lender died, its principal less what they had paid (Q3); who borrows and lends; the share of chains with a child; the two child shares (Q4). Anything with nothing to divide by prints `—` (Review Focus 4). A report with fewer finished seeds than planned says so in bold, as the extinction report does.

**`trace_readings`** returns one line per row of the spec's table that fires, with its numbers, and always ends by naming the lines checked. Rows, with `>` and `<` as the spec has them: age ratio within 0.9–1.1 inclusive on both sides; `voided_lender` over 0.5 of voids, or doomed over 0.25 of voids; matched `borrower` sugar or spice above 1.1; child share `borrowing ≤ 1.1 × could_borrow`. Add the note when the borrower's age ratio is above 1.1 and its matched `all` is within 0.9–1.1: "the extra deaths come from who borrows, not from the loan." `NaN` fires nothing, and the line says what couldn't be read.

- [ ] **Step 1: Write the failing tests in `test_xxl_loan_report.jl`**

Use small tables built by hand, so each number is known:

```julia
# Window 1. 100 started, lender in band 60, borrower in band 20.
t = Dict(("1","started","","") => 100.0, ("1","started_bands","60","20") => 100.0,
         ("1","ended","repaid","") => 75.0, ("1","ended","voided_lender","") => 20.0,
         ("1","ended","voided_borrower","") => 5.0)
census = [(window="1", group="all", band="60", n=100.0, children=0.0, old_age=30.0, sugar=0.0, spice=0.0, killed=0.0),
          (window="1", group="all", band="20", n=200.0, children=0.0, old_age=0.0, sugar=10.0, spice=0.0, killed=0.0)]
```

- `"loan report: X8"`: `x8_share(t, [1]) == 0.25`. With nothing ended, `NaN`.
- `"loan report: the age ratio"`: lender `20 / 30 ≈ 0.667`; borrower `5 / 5 == 1`. With `started` and `started_bands` doubled to 200, expected halves in effect through ended ÷ started, so the ratios are unchanged: unfinished loans aren't charged.
- `"loan report: the matched ratio"`: `borrowing` band 20 `n=100, sugar=10`, `could_borrow` band 20 `n=200, sugar=10` gives `borrower["sugar"] == 2.0`. Adding `borrowing` band 25 `n=10, sugar=9` with no comparison leaves it 2.0 and `excluded == 10`.
- `"loan report: the child shares"`: `borrowing` 50 of 100 and `could_borrow` 40 of 100 give 0.5 and 0.4.
- `"loan report: the readings"`: each row at just inside and just outside its line (age ratio 0.9, 1.1, 0.89, 1.11; lender-only 0.5, 0.51; doomed 0.25, 0.26; matched 1.1, 1.11; child ratio 1.1, 1.11), and the note for age 1.2 with matched 1.0. Credit off: births and end population both at 4.9% below baseline fire; one at 5.1% doesn't.
- `"loan report: nothing to divide by"` (Review Focus 4): an empty tally and empty census give a report with `—` and no `NaN` in it, and `trace_readings` says what couldn't be read.
- `"loan report: files read back"`: a short traced VI-1, `write_trace_files`, then `read_tally` and `read_census` give what the trace held, exactly.
- `"loan report: the scorecard's counts"`: the Task 1 run with its scorecard columns written to a CSV: `trace_matches_scorecard` is true; change one `loans_voided` cell and it is false.
- `"loan report: one seed, and two"`: `merge_tallies` adds; the report's X8 with seeds at 0.2 and 0.3 is 0.25; `- Seeds finished: 1 of 2` with the bold line when a seed is missing.

- [ ] **Step 2: Run them to see them fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan_report"])'`
Expected: FAIL, `x8_share` not defined.

- [ ] **Step 3: Implement `loan_report.jl`**

- [ ] **Step 4: Run the tests**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan_report"])'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add julia/src/xxl/loan_report.jl julia/src/Sugarscape.jl julia/test/test_xxl_loan_report.jl
git commit -m "julia xxl: the loan trace's files and report"
```

### Task 4: The run and its command line

**Files:**
- Create: `julia/src/xxl/loan_run.jl` (include after `xxl/loan_report.jl`), `julia/xxl_loan_trace.jl`
- Modify: `julia/src/Sugarscape.jl`, `julia/README.md`
- Test: `julia/test/test_xxl_loan_run.jl`

**Interfaces:**
- Consumes: `seed_job`, `with_steps`, `write_seed_csv`, `write_timing_csv`, `write_machine_note`, `seed_done`, `check_extinction_folder`, `source_sha256`, `read_elapsed`, `write_atomic`, `timing_seconds`, as they stand; `write_trace_files`, `loan_summary`, `loan_report`, `credit_off_reading` from Task 3.
- Produces:
  - `TraceWorld(name::String, credit::Union{Nothing,Tuple{Int,Float64}}, inheritance::Bool)`, `name` one of `defaults`, `xl`, `book`. `trace_rules(w)` is `XXL_DEFAULTS` for `defaults`, else `nothing`. `trace_xl(w)` is true for `xl`.
  - `trace_experiment(w, periods; experiment=nothing) -> Experiment`: VI-1 (or `experiment`) with `with_steps` and `config` carrying `w.credit` and `w.inheritance`. Build it with `replace_config`.
  - `trace_config(w, exp) -> Config`: `to_xxl` for `defaults`, `to_xl` for `xl`, the config itself for `book`. Whatever it returns carries `w.credit` and `w.inheritance`.
  - `trace_fingerprint(exp, w, periods) -> String`: for `defaults` `xxl_fingerprint(exp, XXL_DEFAULTS)`, for `xl` `"julia\n" * exp.xl_fingerprint`, for `book` `"julia\n" * exp.fingerprint`, then `world=…\ncredit=…\ninheritance=…\ncode sha256=…\nperiods=…\n`.
  - `loan_name(label, first_seed, seeds, periods)`: `loans-<label>-s<first>-<seeds>-p<periods>`.
  - `trace_seed_done(folder, k, periods) -> Bool`: `seed_done` of the CSV and all three trace files present.
  - `loan_trace_seed!(exp, k, w, folder; write_files=write_trace_files) -> Float64`: runs in a worker. A `LoanTrace` with `first(config.credit)`, or 10 with credit off. Writes the trace files, the timing file, and the CSV last by temporary name and `mv`. Returns seconds.
  - `run_loan_trace(w; label, seeds, first_seed, periods, jobs, out=RESULTS_XXL, experiment=nothing, io=stdout) -> summary`. Resumes by skipping done seeds, deletes an unfinished seed's leftover files before rerunning it, refuses a folder with another fingerprint (`ArgumentError`), adds `elapsed.txt` across resumes, writes `<folder>.md`.
  - `rebuild_loan_report(w; label, seeds, first_seed, periods, out=RESULTS_XXL, io=stdout)`.
  - `loan_compare(out, base, others; periods) -> String`: one table, written to `<out>/loans-compare.md`.
  - `loan_trace_main(args) -> exit code`, with the flags `--world defaults|xl|book`, `--term D` (keeps r = 10), `--no-credit`, `--inheritance`, `--label`, `--seeds` (10), `--first-seed` (20), `--periods` (2000), `--jobs` (5), `--out`, `--report-only`, and `--compare BASE,A,B,…`.

**`loan_compare`.** `BASE` and the others are folder names under `--out`. The table has one row per folder, over the seeds and first `periods` periods they share with `BASE`: X8 over t = 1–500, the loans started, the age ratios, births (the change in `agents_ever`), the trough and the end population, from each CSV's rows up to `periods`. So the main run's seeds 20–24, cut to 500 periods, can stand as baseline for the probes. Where a folder has `credit=nothing`, add `credit_off_reading`'s line. Tally windows 3 and later are ignored when `periods` ≤ 500.

- [ ] **Step 1: Write the failing tests in `test_xxl_loan_run.jl`**

Use `TEST-tiny` and a short VI-1 as `test_xxl_extinction.jl` does.

- `"loan run: worlds"`: `trace_config(TraceWorld("defaults", (5, 10.0), false), exp).credit == (5, 10.0)`; the same for `xl` and `book`; `inheritance=true` carries through all three; `credit=nothing` gives `nothing`. `xxl === nothing` for `xl` and `book`, and the `book` config's width is 50.
- `"loan run: a run writes its files"`: 2 seeds, 12 periods. The folder holds the fingerprint, machine and elapsed files and, per seed, `.csv`, `.timing.csv`, `.tally.csv`, `.census.csv`, `.loans.csv`. The report says `- Seeds finished: 2 of 2`.
- `"loan run: a traced seed is the extinction run's"`: the same VI-1, seed and periods through `run_extinction` and `run_loan_trace`: their `seed<k>.csv` have equal bytes.
- `"loan run: a seed stopped part-way runs again"` (Review Focus 3): delete a finished seed's `.tally.csv`, or cut its CSV; a re-run reruns that seed alone (the other's `mtime` is unchanged) and ends with the same tally.
- `"loan run: a CSV is written last"`: `loan_trace_seed!` with a `write_files` that throws leaves no `seed<k>.csv`, and `trace_seed_done` is false.
- `"loan run: other settings are refused"`: a re-run under the same label with another term, world or periods throws `ArgumentError` before changing anything.
- `"loan run: the report can be rebuilt"`: delete the `.md`, `rebuild_loan_report` restores it, the same.
- `"loan run: no credit runs"` (Review Focus 4): `TraceWorld("defaults", nothing, false)`, 2 seeds, 60 periods: ends, X8 prints `—`, the census has rows.
- `"loan run: an extinct world"` (Review Focus 4): VI-1 with `max_age=(2, 2)`, 10 periods: ends with no `NaN` in the report.
- `"loan run: the comparison"`: a base and a no-credit folder, cut to the shared seeds and periods, give a row each with the right `end population`, read from the CSV by hand.
- `"loan run: the command line"`: `loan_trace_main` returns 2 for `--seeds 0`, `--jobs 0`, `--periods 3`, `--first-seed -1`, `--nope`, `--world x`, `--term 0`, `--term 5 --no-credit`, and `--report-only` with no folder.
- `"loan run: a successful main"`: a real end-to-end `loan_trace_main` on a tiny world with `--out` a temp folder, returning 0, with `--label` defaulting to the world's name.

- [ ] **Step 2: Run them to see them fail**

Run: `julia --project=julia -e 'using Pkg; Pkg.test(test_args=["loan_run"])'`
Expected: FAIL, `TraceWorld` not defined.

- [ ] **Step 3: Implement `loan_run.jl`, the script and the README section**

Follow `run_extinction`'s shape, without the stop file or checkpoints: `addprocs`, `remotecall_eval`, `WorkerPool`, `asyncmap` over the seeds to do, one progress line per seed as `extinction_progress` prints it. Add a section to `julia/README.md` beside the extinction test: the commands, what a stop costs (a stopped seed reruns from zero), and that it adds nothing to an ordinary run. `julia/xxl_loan_trace.jl` follows `julia/xxl_extinction.jl`, with its usage in the header comment.

- [ ] **Step 4: Run the tests, then all suites**

Run: `julia --project=julia -e 'using Pkg; Pkg.test()'`; from `julia/`, `../.venv/Scripts/python -m pytest -q`; from the root, `.venv/Scripts/python -m pytest -q`.
Expected: all pass. Before this branch: Julia 45,853, bridge 30, root 412 passed with 169 deselected. Julia's count rises, and the others stay.

- [ ] **Step 5: Short smoke run**

Run: `julia --project=julia julia/xxl_loan_trace.jl --label smoke --seeds 2 --periods 60 --jobs 2 --out "$TMP/loan-smoke"`
Expected: exit 0, and a report with `- Seeds finished: 2 of 2`, a positive `- Loans started:` and a census table.

- [ ] **Step 6: Commit**

```bash
git add julia/src/xxl/loan_run.jl julia/xxl_loan_trace.jl julia/src/Sugarscape.jl julia/README.md julia/test/test_xxl_loan_run.jl
git commit -m "julia xxl: the loan trace's run and command line"
```

### Task 5: The runs, the findings

Run this after the whole-branch review, so a defect found in review can't waste the runs. The controller runs it, not a subagent.

**Files:** Modify `docs/xxl.md`. Results go in `results-julia-xxl/` (git-ignored).

**Interfaces:**
- Consumes: `julia/xxl_loan_trace.jl`, `trace_matches_scorecard` from Tasks 3 and 4.

- [ ] **Step 1: The gate, on the final commit**

Run: `julia --project=julia julia/xxl_loan_trace.jl --label gate --seeds 1 --first-seed 20 --periods 500 --jobs 1`

Then compare the first 502 lines of `results-julia-xxl/loans-gate-s20-1-p500/seed20.csv` with those of `results-julia-xxl/extinction-defaults-s20-60-p2000/seed20.csv` by `cmp`, and run `Sugarscape.trace_matches_scorecard` on its tally and `results-julia-xxl/scorecard-defaults-x2sight-s20-20/VI-1/seed20.csv`.
Expected: identical bytes, and `true`. **A failure stops here. No long run starts.** Compare the X8 of the gate's report with seed 20's in the scorecard CSV, and read the first census table. Look at its figures: is anything impossible?

- [ ] **Step 2: The main run, in the background, with the machine kept awake and memory watched**

Run: `julia --project=julia julia/xxl_loan_trace.jl --label defaults --seeds 10 --first-seed 20 --periods 2000 --jobs 5`

A watcher as in stage 2: stop this run's Julia tree only, on free memory under 1 GB for two polls in a row, or commit headroom under 0.5 GB. Leave other sessions' jobs alone. If it stops, the same command reruns the unfinished seeds, with fewer workers if the shortage was real. If the same seed fails twice, stop and report.

- [ ] **Step 3: Check the main run**

For k in 20–29: `cmp` `seed<k>.csv` with the extinction run's, whole. `trace_matches_scorecard` on each tally and scorecard CSV. Read the report: 10 seeds, and do the readings follow from its tables?
Expected: identical bytes and `true` for all ten. **A failure stops here:** the findings can't be trusted, so report it.

- [ ] **Step 4: The probes, one at a time**

```bash
julia --project=julia julia/xxl_loan_trace.jl --label term5 --term 5 --seeds 5 --first-seed 20 --periods 500 --jobs 5
julia --project=julia julia/xxl_loan_trace.jl --label term20 --term 20 --seeds 5 --first-seed 20 --periods 500 --jobs 5
julia --project=julia julia/xxl_loan_trace.jl --label inherit --inheritance --seeds 5 --first-seed 20 --periods 500 --jobs 5
julia --project=julia julia/xxl_loan_trace.jl --label nocredit --no-credit --seeds 5 --first-seed 20 --periods 500 --jobs 5
julia --project=julia julia/xxl_loan_trace.jl --world xl --label xl --seeds 5 --first-seed 20 --periods 500 --jobs 5
julia --project=julia julia/xxl_loan_trace.jl --world book --label book --seeds 20 --first-seed 20 --periods 500 --jobs 5
```

Then, from `results-julia-xxl/`'s folder names:

```bash
julia --project=julia julia/xxl_loan_trace.jl --periods 500 --compare loans-defaults-s20-10-p2000,loans-term5-s20-5-p500,loans-term20-s20-5-p500,loans-inherit-s20-5-p500,loans-nocredit-s20-5-p500,loans-xl-s20-5-p500,loans-book-s20-20-p500
```

- [ ] **Step 5: Write the findings into `docs/xxl.md`**

A new section after "Stage 2: the chance of extinction", "Stage 3: what X8 measures": X8 and the 0.2's origin; the four answers with their numbers; the probes, stating the spec's confounds; the design's written guess and whether it held; which reading rows fired; the limits (one map, not randomized, the term probes change who borrows); the real run time including any stops; a recommendation, labelled as one. No change to X8 or the rules. Update `docs/xxl.md`'s scorecard line about X8 only if a fact there proved wrong.

- [ ] **Step 6: Commit, then put the decision to the user**

```bash
git add docs/xxl.md
git commit -m "docs: stage 3, what X8 measures"
```

Hand over the findings, the ledger's rulings and deferred minors, and the one question: what to change. What changes is the user's decision, under a new spec.
