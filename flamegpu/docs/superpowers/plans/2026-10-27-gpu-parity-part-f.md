# Every Rule on the GPU, Part F: Everything Together — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run every Sugarscape experiment on the GPU, at regular size and on a sample at xl, and score it against
Python, and Julia where Python has no xl results. Write the speed tables that set the GPU against both. Part D's four
deferred minors are fixed first.

**Architecture:**
- **Tools first, then runs.** Task 2 extends the run and report tools. `bridge.gpu_run` gains several ids at once and
  `--resume`. `bridge.agreement_report` gains `--xl`, a Julia reference, and Julia's timings in the speed table.
- **Agreement and timing are separate passes:**
  - **Regular size.** Agreement runs on `build\` (seatbelts on) at `--jobs 4`, as every part has. Then seed 0 of
    every experiment runs alone on `build-fast\` (`--jobs 1`) for the speed table. Python's and Julia's timings were
    taken one job at a time too.
  - **xl.** Each run fills the GPU, so the xl sample runs once, on `build-fast\` at `--jobs 1`, for both agreement and
    timing.
- **Results outlive the worktree.** Every run writes into the main checkout's result folders, given by `--out`.

**Tech Stack:** FLAME GPU 2 v2.0.0-rc.5 (C++/CUDA 13.4), Python 3.14 bridge and pytest, the Julia agreement rule
(`julia/bridge/agreement.py`, loaded by path).

**Spec:** `flamegpu/docs/superpowers/specs/2026-10-25-gpu-full-parity-design.md`: Part F of "The work, in parts", and
Goals 3–5, Constraints ("Saved GPU results become stale") and sections 7–8. Part D's plan and its validation write-up
(`docs/validation/chapter5-part-d.md`) list the deferred minors.

## Scope decisions (the user's, 2026-10-27)

- **Part E is skipped.** The user's words: "I am not interested in the Schelling and Ring World models. Skip tests on
  these." VI-4 to VI-9, TEST-schelling and TEST-ring are neither built nor run nor scored. Reports list them as
  skipped by decision. This leaves the 135 registered experiments whose config is a `Config`.
- **xl is a sample, not the full registry.** The full registry was estimated at 12–50 GPU hours, and the user chose
  a sample of about 3–8.
  - **Against Python**, which has xl results for exactly these: II-4, II-4-gini, II-6, II-7, II-8, IV-A3, VI-1.
  - **Against Julia,** one or two per rule family:

    | Family | Experiments |
    |---|---|
    | sex S | III-1 |
    | inheritance I | III-7 |
    | culture K | III-8 |
    | combat | III-9, III-11 |
    | trade T | IV-3, IV-6/trade/v6 |
    | sex with trade | VI-3 |
    | credit L | IV-A5 |
    | disease E | V-2 |

    Julia took 2.7 hours for these.

## Global Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, telemetry off.
- **Builds:** `scripts\build.cmd` (`build\`) and `scripts\build.cmd build-fast OFF`. After each build, grep the log for
  `#2001`: 0 hits, or the build is wrong.
- **The suite** is `.venv\Scripts\python -m pytest tests -q`. From a worktree, use the main checkout's
  `C:\Projects\Sugarscape2026\flamegpu\.venv`.
- **The GPU to itself.** Timing passes and the xl sample need it, with no game or other GPU program running.
  - A run that shared the GPU is noted in the write-up, and its timings are left out of the speed tables.
  - Long runs go in the background; `--resume` continues a stopped one.
- **Reference results** live in the main checkout, not the worktree:
  - `C:\Projects\Sugarscape2026\results`: Python regular, all 135 current;
  - `...\results-xl`: Python xl, the 7 above, current;
  - `...\results-julia-xl`: Julia xl, all current.

  Every report command passes them with `--python` and `--julia`.
- **GPU results** go to the main checkout's `flamegpu\results-gpu`, `flamegpu\results-gpu-fast` and
  `flamegpu\results-gpu-xl`, via `--out`. They are git-ignored derived data. The stale folders there now (Chapter II
  from Phase 1, combat from Part B, xl Chapter II) are replaced. Approving this plan approves that.
- **`GPU_FINGERPRINT` becomes `gpu-parity\n`** (Task 2). The spec's constraint: "Saved GPU results become stale... and
  Chapter II is rerun in Part F". Every result made before Part F then reads stale, so `--resume` can't keep one.
- **No change to model outputs.** Task 1 changes refusals and tests only. The goldens and every agreement test still
  pass.
- **Context7** before any FLAME GPU code (Task 1 touches `model.cu` only to pass the fee).
- **Existing tests this plan changes:**
  - `test_bridge.py::test_run_tiny_experiment` asserts `gpu-parity`;
  - `test_disease.py::_bits` docstring.

  No behavioural assertion is weakened. Approving this plan approves them.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The fast build gives the same results.** Results from `build-fast\` (seatbelts off) must equal `build\`'s byte
   for byte, or the xl sample and the timing pass measure a different program. Pinned by
   `test_fast_build_same_output` (Task 2).
2. **Resuming a stopped run.** `--resume` must skip only experiments whose folder is current *and* complete: the
   fingerprint matches and every registered seed is there. A half-written folder reruns. Pinned by
   `test_resume_skips_only_complete` (Task 2).
3. **The right reference and fingerprints at xl.** Each side's fingerprint and folder must be checked for the xl
   version:
   - a Julia reference matches `"julia\n" + fingerprint(id, xl)`;
   - a stale side is listed, never scored silently.

   Pinned by `test_xl_julia_reference` and `test_julia_stale_listed` (Task 2).
4. **Speed with a side missing.** A missing Julia or Python timing gives NaN and no ratio, not a crash or a false 0.
   Pinned by `test_speed_table_julia_column` (Task 2).
5. **The skipped models.** A chapter prefix that includes VI-4 to VI-9 runs the rest and names those as skipped by
   decision. Pinned by `test_gpu_run_names_skipped_models` (Task 2).

---

### Task 1: Part D's deferred minors

**Files:**
- Modify: `src/main.cu` (the refusals), `src/model.cu` (`disease_properties`)
- Test: `tests/test_cli.py`, `tests/test_disease.py`

**Interfaces:**
- **Produces, in `main` after `validate`:** refusals with exit 2 and these messages:
  - `--disease-list needs disease_list > 0`;
  - `--dump-diseases needs disease_list > 0`;
  - `--loan-capacity needs credit`.
- **Produces:** `disease_properties` sets `disease_fee` to `cfg.disease() ? cfg.disease_fee : 0.0`, as Python's
  `Agent.disease_fee` is 0 without disease.
  - No output changes: run.cfg refuses a non-finite fee, so `fee · 0` is already 0. There is no failing test (ruling
    F1).

- [ ] **Step 1: Write the failing tests.**
  - **`test_cli.py::test_option_needs_its_rule[disease-list|dump-diseases|loan-capacity]`:**
    - write_cfg's defaults (no disease, no credit), steps 1, with the option and a file in tmp_path;
    - exit 2, and `_error` contains the message above.
  - **`test_disease.py::test_disease_limits_match_python`:**
    - one agent at (2,2) on `CAPACITY`, vision 1, metabolism 1, sugar 40, all-0 immune string of 64 bits;
    - `disease_list = 64`, `disease_length = 1,63`, `immune_length = 64`;
    - `--disease-list`: entry i is `format(i, "06b")` for i < 63, and entry 63 is `"1" * 63`. Every string is
      distinct, so every id is canonical.
    - the agent carries `"63|5"`;
    - after 3 steps, `compare_dumps(gpu, run_python(...)) == []`, and the agent still carries 63: a 63-bit disease
      against an all-0 immune string isn't cleared in 3 periods.
- [ ] **Step 2: Run them.**
  - Expected: `test_option_needs_its_rule` FAILS on all three (exit 0).
  - `test_disease_limits_match_python` is expected to PASS: it pins the 64-bit paths the reviewer emulated. If it
    fails, use superpowers:systematic-debugging.
- [ ] **Step 3: Implement** the refusals and the fee, and fix `_bits`' docstring: the disease columns are
  `TEXT_COLUMNS`, so the helper only turns `None` into `""`.
- [ ] **Step 4: Rebuild both builds, then run the two files, then the suite.** Expected: all pass.
- [ ] **Step 5: Commit** `flamegpu: Part D's minors - options need their rule, the fee only with disease, the limits pinned`.

### Task 2: The run and report tools for Part F

**Files:**
- Modify: `bridge/gpu_run.py`, `bridge/agreement_report.py`, `README.md` (usage lines)
- Test: `tests/test_bridge.py`, `tests/test_agreement_report.py`

**Interfaces:**
- **Produces, `gpu_run`:**
  - `GPU_FINGERPRINT = "gpu-parity\n"`.
  - `main` takes `ids` (one or more ids or prefixes; `nargs="+"`) and `--resume`.
  - `--resume` skips an id when `gpu_current(exp_id, out, xl)` is true.
  - `gpu_current(exp_id: str, gpu_dir: Path, xl: bool = False) -> bool` moves here from `gpu_report`, gaining `xl`.
    `gpu_report` imports it.
  - The skip message names its reason. Ids whose config isn't a `Config` print `skipped by decision (Schelling and
    Ring World, plan 2026-10-27-gpu-parity-part-f): ...`.
  - With `--xl`, those ids are dropped before `experiment_config`, so a prefix like `VI` doesn't stop the whole run.
- **Produces, `agreement_report`:**
  - `build_report(args, gpu_dir, ref_dir, *, xl=False, reference="python", julia_dir=None, timing_dir=None) -> Report`.
    - The reference is `"python"` or `"julia"`. Its staleness check is `results_current(id, ref_dir, xl)` for Python,
      and fingerprint.txt equal to `"julia\n" + fingerprint(id, xl)` for Julia.
    - The GPU's staleness check is `gpu_fingerprint(id, xl)`.
    - `timing_dir` (default `gpu_dir`) is where the GPU's `timing.csv` is read.
    - `julia_dir` adds Julia's timings to the speed rows.
  - `Speed` gains `julia_step_ms: float = math.nan` and a `julia_ratio` property (GPU / Julia step).
  - The report's title and value labels name the reference ("GPU against Julia"). The speed table keeps its columns
    and appends `Julia step ms | GPU / Julia step`.
  - The command line gains `--xl`, `--reference {python,julia}` (with `--reference julia`, `--python` is not read and
    `--julia` names the reference folder), `--julia DIR` and `--timing DIR`.

- [ ] **Step 1: Write the failing tests.**
  - **`test_bridge.py`:**
    - `test_run_tiny_experiment`: the fingerprint starts with `gpu-parity`.
    - **`test_resume_skips_only_complete`:**
      - `run_experiment_gpu("TEST-tiny", out_dir=tmp)`, then `main(["TEST-tiny", "--resume", "--out", tmp])`, leaves
        `seed0.csv`'s modification time unchanged;
      - after deleting `seed1.csv`, the same call rewrites both seeds;
      - after writing a wrong fingerprint.txt, it reruns too.
    - **`test_gpu_run_names_skipped_models`:**
      - `main(["VI", "--seeds", "0", "--out", tmp])` (0 seeds: the selection runs, no model does) makes folders for
        VI-1, VI-2 and VI-3 only;
      - its stdout (capsys) contains `skipped by decision` and `VI-4`;
      - the same with `--xl` raises no SystemExit.
    - **`test_fast_build_same_output`:**
      - skipped without `FAST_EXE`;
      - VI-1's registry config (`test_spice._registry`), 10 steps, run with `--out`, `--dump-agents` and `--dump-at 10`
        on both builds;
      - the metrics CSVs are byte-identical, and so are the dumps without the `id` column (`test_sex._files`'s rule).
  - **`test_agreement_report.py`:**
    - **`test_xl_julia_reference`:**
      - TEST-tiny's seeds in a `jl` folder whose fingerprint.txt is `"julia\n" + fingerprint(EXP)`, and the same
        seeds in `gpu`;
      - `build_report([EXP], gpu, jl, reference="julia")` has no flags and `stale == []` (the GPU fingerprint written
        as `gpu_fingerprint(EXP)`);
      - the written report's first line contains `Julia`.
    - **`test_julia_stale_listed`:** the same with fingerprint.txt `"julia\nold\n"`, and `stale == [EXP]`.
    - **`test_speed_table_julia_column`:**
      - Python timing stepping 10 s, GPU 1 s, Julia 2 s (10 periods);
      - `julia_step_ms == 200.0` and `julia_ratio == 0.5`;
      - with no Julia folder, `julia_step_ms` is NaN and the row reads `| nan | nan |` at its end.
    - **`test_timing_dir_overrides`:** GPU timings read from a third folder when `timing_dir` is given.
    - **`test_xl_fingerprints`:** with `xl=True`, a Python folder whose fingerprint.txt is `fingerprint(EXP)` (the
      regular one) is listed stale. The GPU side follows the same rule.
- [ ] **Step 2: Run them.** Expected: FAIL (`gpu-phase3`; no `--resume`; unknown keyword arguments).
  `test_fast_build_same_output` may PASS at once: it pins a property, as Part D's lender test did.
- [ ] **Step 3: Implement** to the interfaces. Add the two new `gpu_run` forms and the report's new options to the
  README's usage.
- [ ] **Step 4: Run the two files, then the suite.** Expected: all pass.
- [ ] **Step 5: Commit** `flamegpu: Part F's tools - several ids and --resume, xl and Julia in the agreement report`.

### Task 3: Every experiment at regular size

**Files:**
- Create: `docs/validation/agreement-part-f.md`, `docs/validation/targets-part-f.md`
- No source changes. A flag that needs a fix goes back to the owning code with a failing test first, under
  superpowers:systematic-debugging.

- [ ] **Step 1: The agreement runs**, on `build\`, in the background:
  `.venv\Scripts\python -m bridge.gpu_run TEST-tiny II III IV V VI VAR --jobs 4 --resume --out C:\Projects\Sugarscape2026\flamegpu\results-gpu`.
  - Expected: 135 experiments run, the six skipped models are named, and every run exits 0.
  - Ledger the wall time, and any interruption with where `--resume` picked up.
- [ ] **Step 2: Agreement against Python:**
  `.venv\Scripts\python -m bridge.agreement_report TEST-tiny II III IV V VI VAR --gpu C:\Projects\Sugarscape2026\flamegpu\results-gpu --python C:\Projects\Sugarscape2026\results --out docs/validation/agreement-part-f.md`.
  - Expected: 0 flagged, 0 stale, and only the six skipped models not run.
  - Parts A–D found 0 flags in 7,090 windows. With every p corrected together a flag is possible. Each one gets
    superpowers:systematic-debugging, then a fix or an explanation with its evidence: more seeds a side, or the
    semantics harness for differences 1–3.
- [ ] **Step 3: Book targets.**
  - Run `bridge.gpu_report --chapter X` for II, III, IV, V and VI, with `--gpu` and `--python` as above.
  - Copy each `REPORT.md` into `docs/validation/targets-part-f.md`, one section per chapter. VI's section notes VI-4
    to VI-9 as skipped by decision.
  - Expected: every status change is explained with its seed-level p, from 20 seeds a side where p < 0.05 (Part D's
    method for VI-1's Gini).
- [ ] **Step 4: The timing pass**, with the GPU to itself, on `build-fast\`, in the background:
  `.venv\Scripts\python -m bridge.gpu_run TEST-tiny II III IV V VI VAR --seeds 1 --jobs 1 --resume --exe build-fast\bin\Release\sugarscape_gpu.exe --out C:\Projects\Sugarscape2026\flamegpu\results-gpu-fast`.
  - Expected: 135 runs, exit 0.
  - Then rerun Step 2's report with `--timing C:\Projects\Sugarscape2026\flamegpu\results-gpu-fast` and
    `--julia C:\Projects\Sugarscape2026\results-julia`. Its speed table is the regular-size table.
- [ ] **Step 5: Commit** `flamegpu: Part F - every experiment at regular size against Python`.

### Task 4: The xl sample

**Files:**
- Create: `docs/validation/agreement-part-f-xl-python.md`, `docs/validation/agreement-part-f-xl-julia.md`

- [ ] **Step 1: Probe and project.**
  - For each of the 17 sample ids, run seed 0 for 5 periods on `build-fast\` with `--timing`, as Part D's xl smoke
    runs did (`config_to_cfg(experiment_config(id, xl=True), steps=5, seed=0)`).
  - Project `seeds × steps × ms per period` per id and in all, and ledger the projection.
  - **If the projection exceeds 8 hours, stop and ask the user** which ids to drop: this is their time budget.
- [ ] **Step 2: Run the sample**, with the GPU to itself, on `build-fast\`, in the background:
  `.venv\Scripts\python -m bridge.gpu_run <the 17 ids> --xl --jobs 1 --resume --exe build-fast\bin\Release\sugarscape_gpu.exe --out C:\Projects\Sugarscape2026\flamegpu\results-gpu-xl`.
  Expected: every run exits 0. Ledger the wall time against the projection.
- [ ] **Step 3: Agreement.**
  - **Against Python:** `bridge.agreement_report <the 7> --xl --gpu ...\results-gpu-xl --python C:\Projects\Sugarscape2026\results-xl --julia C:\Projects\Sugarscape2026\results-julia-xl --out docs/validation/agreement-part-f-xl-python.md`.
  - **Against Julia:** `bridge.agreement_report <the 10> --xl --reference julia --gpu ...\results-gpu-xl --julia C:\Projects\Sugarscape2026\results-julia-xl --out docs/validation/agreement-part-f-xl-julia.md`.
  - Expected: 0 flagged and 0 stale in each. Flags are handled as in Task 3.
  - Julia's own agreement with Python, where both have xl results, is in the Julia project's reports. The write-up
    cites it, so a GPU-against-Julia result reads in that light.
- [ ] **Step 4: Commit** `flamegpu: Part F - the xl sample against Python and Julia`.

### Task 5: The write-up

**Files:**
- Create: `docs/validation/part-f.md`
- Modify: `README.md`, `docs/superpowers/specs/2026-10-25-gpu-full-parity-design.md`

- [ ] **Step 1: Write `docs/validation/part-f.md`:**
  - what ran, the conditions (builds, jobs, whether the GPU was shared) and the wall times;
  - the agreement verdicts at regular size and at xl, and every flag and status change explained;
  - the book targets per chapter, both sides;
  - **the speed tables:**
    - regular size, all 135: GPU ms (fast build, alone), Python ms, Julia ms and both ratios, plus the waves per
      period from the timing JSON;
    - xl, the sample: the same columns.

    A short reading of where the GPU wins and where it loses, and why: a few hundred agents can't fill the GPU at
    regular size, and the waves add launches.
  - The Schelling and Ring World models are noted as skipped by decision.
- [ ] **Step 2: Update the README:**
  - "Results" becomes Part F's: the agreement totals, the book-target table per chapter and the two speed tables in
    short, linking `part-f.md`. The Phase 1 Chapter II table and the scaling benchmark stay as history.
  - "How the GPU version differs": difference 3 also names the diseases movement scores with. The status lines say
    the Schelling and Ring World models are skipped by decision.
- [ ] **Step 3: Note in the spec** under "The work, in parts", at E: "Skipped by the user's decision (2026-10-27):
  'I am not interested in the Schelling and Ring World models.'"
- [ ] **Step 4: Run the suite.** Expected: all pass.
- [ ] **Step 5: Commit** `flamegpu: Part F write-up - agreement, book targets and speed, regular and xl`.

## Rulings this plan makes

- **F1:** the fee passed as 0 without disease has no failing test. It mirrors Python, and run.cfg's refusal of a
  non-finite fee already makes `fee · 0` zero. Cost if wrong: none.
- **F2:** xl agreement runs on `build-fast\`, once, rather than twice as `xl_validate` did (seatbelts for agreement,
  fast for timing). `test_fast_build_same_output` pins that the outputs are the same. Cost if wrong: an xl sample
  measured on a program that differs from the tested one, which that test exists to catch.
- **F3:** the regular-size speed table comes from one seed per experiment, alone on the fast build, since Python's and
  Julia's timings were taken at `--jobs 1`. Cost if wrong: one seed's noise in a development timing; the spec's
  controlled timing run is the user's, later.
