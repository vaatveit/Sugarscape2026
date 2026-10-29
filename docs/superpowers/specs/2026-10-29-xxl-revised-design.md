# Sugarscape xxl, revised — Design (scorecard and stage 1)

Date: 2026-10-29. Revises [the xxl design](2026-10-28-xxl-design.md), whose rules and results are in
[docs/xxl.md](../../xxl.md). Julia only, as before.

## Intent

The first xxl rules were built to show what the bigger world does to the book's model. **The goal is now a
well-functioning simulation** (user decision, 2026-10-29), defined two ways:

1. **The population rarely goes extinct.**
2. **Each aspect of society works as intended:** sex, culture, trade, credit and disease.

The rules change **for xxl only** (user decision). The book rules, xl, the Python side and every non-xxl result stay
exactly as they are.

The work goes in stages, each with its own spec (my call, following the recommendation the user accepted):

| Stage | Covers | Spec |
|---|---|---|
| 0 | The scorecard: how "well-functioning" is measured | this one |
| 1 | Survival: founding and the travel-cost trap | this one |
| 2 | Contact and demography: meeting, mating, births | later |
| 3 | Economy: trade and credit | later |
| 4 | Disease | later |

The order matters: each stage needs the one before it. Disease can't be tuned in a population that is nearly
extinct, and trade and mating can't work while agents rarely meet.

### Why: what the first runs showed

Each finding below is from `docs/xxl.md` or from traces run on 2026-10-29 (3 seeds, reproducing the recorded runs
exactly). The scripts were throwaway; their results are quoted here.

- **VI-1 (society) nearly dies out.** Under xxl, 20,000 founders fall to 739–1,034 by t ≈ 85 (5 seeds), against
  2,885–3,779 under xl. By t = 50, 67% of founders have starved under xxl against 49% under xl; old age takes 28–39%
  in both.
  - Founders with a metabolism of 5, sugar or spice, are 44–54% of the starved. The highest capacity on either map
    is 4, so they can never feed themselves.
  - Founders with no land feeding both goods within 20 sites of their start all die under xxl (0% alive at t = 50),
    and are about a third of the starved.
  - Births by t = 100 are 2,400–2,700 under xxl, against 6,500–8,100 under xl. At t = 25 an agent has 0.22–0.24
    neighbours on average, against 0.55: mates are rarely in reach (stage 2).
- **A travel-cost trap kills agents who were breaking even** (II-4, `docs/xxl.md`, "Who dies in the second
  die-off"). An agent harvests at most its site's capacity, so one whose metabolism equals its land's capacity must
  step to a full site each period to eat. The travel cost turns its zero margin negative, and it starves when its
  savings run out: about 6,000 agents per seed at c = 0.1 or 0.2.
- **The xl map sets sugar against spice** (correlation −0.57; no site has both at 4). Founders of IV-A3 survive
  mostly where both are within reach, and the generated map raises IV-A3's population by 49% (`docs/xxl.md`, "Why
  the map matters").
- **The rest of society is weak too** (stages 2–4): disease dies out in every VI-1 seed by t = 65–94, while under xl
  it still circulates at t = 500; trade is 0.3 per agent per period against 0.7–2.0 under xl. Credit, sex and
  culture recover once the population does.

**Goals**
- A scorecard: a script that runs a fixed set of experiments over many seeds and reports, per aspect, whether the
  simulation is well-functioning, against stated thresholds. It reports every aspect from the start, so the baseline
  for later stages is known; only the survival checks gate stage 1.
- Stage 1's rule changes, each a switch with a book setting, so that the survival checks pass.
- A tuning protocol for stage 1, and its results in `docs/xxl.md`.

**Non-goals**
- Stages 2–4. The scorecard measures them; their rule changes come in later specs.
- Matching xl or the book. xl appears in the scorecard only as a reference level for experiments without births.
- Proving emergence, or explaining each result in the depth `docs/xxl.md` did.
- Python, the viewer, FLAME GPU.

**Anti-goals**
- **No change to the book rules, xl, or any non-xxl result** (user decision: xxl only). Every existing test passes
  unchanged, and `results-julia/` and `results-julia-xl/` stay current.
- **No hand-placed stabilisers** such as topping up a dying population with immigrants. They would pass the
  extinction check while hiding the failures the scorecard exists to catch. If one is ever needed it gets its own
  switch, its own spec, and a label saying what it hides (my call).
- **No tuning to a seed.** Thresholds are judged over 20 seeds or more, and the chosen settings are confirmed on
  seeds not used to choose them.
- **No silent loss of the first xxl rules.** They stay runnable as a named rule set, so the scorecard has a baseline
  and `docs/xxl.md`'s results can be reproduced.

## The scorecard

### What it runs

`julia --project=julia julia/xxl_scorecard.jl [--rules NAME] [--seeds N] [--first-seed K] [--jobs J]` runs these
under one xxl rule set (by default the current defaults) and prints a pass/fail table:

| Experiment | Periods | Why it is on the scorecard |
|---|---|---|
| II-4 | 500 | Sugar only, no births: survival of a fixed population on one good |
| IV-A3 | 300 | Sugar, spice and trade, no births: survival on two goods |
| VI-1 | 500 | Sex, culture, trade, credit and disease at once: the extinction test, and every aspect of society |

- **Seeds:** 20 by default (`--seeds`), starting at seed index 0 (`--first-seed`). The confirmation run of a stage
  uses 20 further seeds (indices 20–39) that were not used to choose the settings.
- **Output:** a table on stdout and a markdown file, `results-julia-xxl/scorecard-<rules>.md`, with each check's
  value (mean and range over seeds), its threshold and pass/fail. The per-seed CSVs go under
  `results-julia-xxl/scorecard-<rules>/<experiment>/` as the runner writes them, so a scorecard can be re-scored
  without re-running.
- **Reference levels:** the checks that compare with xl use the xl run of the same experiment and seeds, which the
  scorecard runs too (once per seed set; xl is fast).
- **Run time:** VI-1 dominates (about 8 minutes per seed under the first xxl rules, on one job). The builder states
  the scorecard's wall time with `--jobs` set to the machine's cores.

### The checks

Every threshold is *my call* and provisional: the user may move any of them, and later stages may refine their own.
"Seeds" means the scorecard's seeds; "end" means the mean over the last 100 periods.

**Survival (gates stage 1):**

| Check | Experiment | Passes when | First xxl rules (for scale) |
|---|---|---|---|
| S1 No extinction | VI-1 | No seed reaches population 0 | 0 of 5 extinct |
| S2 No near-extinction | VI-1 | Every seed's minimum population ≥ 10% of the founders | 3.7–5.2% (xl: 14–19%) |
| S3 Recovery | VI-1 | End population ≥ 50% of xl's, mean over seeds | 69% |
| S4 Survivors, one good | II-4 | End population ≥ 90% of xl's, mean over seeds | 59% |
| S5 Survivors, two goods | IV-A3 | End population ≥ 90% of xl's, mean over seeds | 59% |

S4 and S5 compare with xl because an experiment without births has no extinction to avoid. Its population can only
fall, and xl's movement, free and as far as the agent sees, is the level reached when no agent dies of a model
artifact.

**Society (reported from the start; gating in stages 2–4):**

| Check | Passes when | Aspect |
|---|---|---|
| X1 Births keep up | Over the last 200 periods of VI-1, births ÷ deaths is within 0.9–1.1 (mean over seeds) | Sex |
| X2 Mates in reach | At VI-1's trough, ≥ 50% of fertile agents have a fertile agent of the other sex within the interaction radius | Sex |
| X3 Both cultures live | In ≥ 80% of VI-1 seeds both tribes hold ≥ 5% of the population at t = 200 | Culture |
| X4 Culture moves | Tag flips per agent per period > 0 throughout VI-1 (culture transmission is happening) | Culture |
| X5 Agents trade | At VI-1's end, ≥ 50% of agents traded in the last 10 periods | Trade |
| X6 Prices agree | VI-1's end price sd ≤ xl's end price sd × 1.5 | Trade |
| X7 Credit persists | Loans outstanding > 0 in every period after t = 100, in every VI-1 seed | Credit |
| X8 Loans are repaid | Over VI-1, ≤ 20% of loans end voided by the borrower's or lender's death | Credit |
| X9 Disease is endemic | At least one disease still circulates at t = 500 in ≥ 90% of VI-1 seeds | Disease |
| X10 Disease is bounded | At VI-1's end, the share sick is within 1–20% | Disease |

### New metrics

The scorecard needs a few values the runner doesn't record yet. They are a separate, opt-in group of columns that only
the scorecard turns on (*my call*), so ordinary `--xxl` runs, their CSV headers and every existing CSV stay as they
are. Each period:

- **Deaths by cause:** sugar starvation, spice starvation, old age, killed in combat. Starvation by both goods counts
  as sugar.
- **Births.**
- **Fertile agents, and those with a fertile agent of the other sex within the interaction radius** (X2).
- **Tag flips** (X4).
- **Agents who traded this period** (X5; the scorecard counts distinct traders over 10 periods from a per-agent
  record the builder chooses).
- **Loans started, repaid, and voided by a death** (X8).

`population`, `trades`, `price_sd`, `n_loans`, `n_blue`/`n_red`, `diseases_circulating` and `fraction_sick` already
exist.

### The first xxl rules as a baseline

The current `XXL_DEFAULTS` stay in the code under the name `XXL_V1` (*my call*), and the scorecard can run them
(`--rules v1`). Its first output is the baseline scorecard for `XXL_V1`, committed to `docs/xxl.md`.

## Stage 1: survival

### Changes

Four new `XxlRules` switches, each with a book setting that changes nothing, and one changed default. Under the book
settings xxl still reduces exactly to xl, as the reduction test checks today. The "candidate" column is what the
tuning tries; the tuning decides which become the new defaults (below).

| Field | Book setting | Candidate | What it does |
|---|---|---|---|
| `max_metabolism` | `nothing` | 4 | Caps the sugar and spice metabolism drawn for a new agent |
| `founder_placement` | `"random"` | `"viable"` | Places founders on land that feeds them |
| `free_step` | 0.0 | 1.5 | Travel cost is charged only for distance beyond this |
| `founder_ages` | `"book"` | chosen by the tuning (`"book"` or `"young"`) | Starting ages of founders |
| `landscape` (exists) | `"xl"` | `"generated"` | The generated map becomes the default |

1. **`max_metabolism`.** A new random agent's sugar metabolism is drawn from (lo, min(hi, M)), and with spice its
   spice metabolism likewise; M = 4 is the highest capacity on both maps. This applies wherever the experiment draws
   a metabolism: founders and rule R's replacements. Children inherit their parents' metabolisms (rule S), so the
   cap holds for them without a change. Same number of draws, narrower range. Why: a metabolism of 5 can never be
   fed from one site, and those founders are about half of VI-1's starved.
2. **`founder_placement = "viable"`.** A founder (and a rule-R replacement) goes to a uniformly random empty site
   among those whose sugar capacity ≥ its sugar metabolism and, with spice, whose spice capacity ≥ its spice
   metabolism. Its traits are therefore drawn before its site, an xxl-only change of draw order. If no such site is
   empty, it goes to a uniformly random empty site, and the run counts how often that happened. Tribal blocks
   (III-9's `initial_blocks`) apply the rule within each block. Births are untouched: a child is born next to its
   parents, as in the book. Why: founders with no viable land in reach starve before they can find it, at speed 1–6.
3. **`free_step = 1.5`.** A move whose *target* is within `free_step` of the agent costs nothing; a move toward a
   farther target costs exactly as it does now (*my call*). So a step to any of the 8 Moore neighbours (d ≤ √2) is
   free, while a trip to a site 2 or more away pays `travel_cost` per site moved, each period, as today. The agent's
   valuation agrees with what it pays: wherever the xxl rules charge c·d for a candidate at distance d (rule 2's net
   value and its starve-on-the-way cutoff, memory's ranking, combat's valuation), that term is 0 when
   d ≤ `free_step`. Why: it removes the travel-cost trap, since an agent stepping to a full neighbour no longer runs
   a deficit, and it keeps long trips costly for every speed. (Discounting each period's step instead would make
   every move of a speed-1 agent free.)
4. **`founder_ages`.** `"book"` keeps the experiment's own founder ages (VI-1: uniform over the lifespan, so 26–39%
   of founders die of old age by t = 50). `"young"` draws each founder's age uniformly from 0 to its fertility start,
   so founders start before or at the start of their fertile years. It only matters for experiments with aging. The
   tuning decides whether stage 1 needs it; if not, it stays `"book"` and the switch remains for stage 2.
5. **`landscape = "generated"` by default.** It already exists. The map pair is the committed one (correlation of
   sugar and spice −0.12). Making the generator control that correlation is not stage 1.

`travel_cost` keeps its meaning; its default is re-chosen by the tuning (0.1 now).

### Tuning protocol

1. **Baseline.** Score `XXL_V1` (20 seeds). Commit the scorecard.
2. **One at a time.** Score `XXL_V1` plus each change alone: `max_metabolism`, `founder_placement`, `free_step`,
   `landscape`, and `founder_ages = "young"`. This says what each fixes.
3. **Together.** Score all five together, with `travel_cost` ∈ {0.05, 0.1, 0.2} and `founder_ages` ∈
   {`"book"`, `"young"`}: six settings.
4. **Trim.** If a single change from step 2 passes S1–S5, it is the candidate. Otherwise, from the best passing
   setting of step 3, drop each change in turn (leave one out), keep any drop that still passes, and repeat until no
   change can be dropped. This finds a smallest passing set without scoring every combination.
5. **Choose** the passing setting with the fewest changes from `XXL_V1`. The switches and the landscape count as
   changes; `travel_cost` does not, and ties go to the higher `travel_cost`, which keeps distance mattering. Switches
   not chosen stay at their book settings. Confirm the choice on seeds 20–39; if it fails there, confirm the next
   passing setting, and if none confirms, report to the user (*my call* throughout).
6. **Record.** The chosen values become `XXL_DEFAULTS`, and `docs/xxl.md` gets the scorecards from steps 1–5, a
   short account of what each change did, and the confirmation.

**If nothing passes,** stage 1 reports which checks fail and by how much, and the user decides between moving a
threshold and carrying the failure into stage 2. The likely case is S2: VI-1's trough also depends on births, which
are contact-limited (stage 2).

## Constraints

- **Julia only;** the book rules, xl, Python and their results don't change (above).
- **Book settings reduce exactly.** The reduction test covers the new switches: with every switch at its book
  setting, xxl is the xl run.
- **Gated draws.** A new draw, or a reordered one, happens only when its switch is on, as now.
- **The 16 `XXL-…` experiments stay on `XXL_V1`** (*my call*). Each is defined from `XXL_V1` instead of
  `XXL_DEFAULTS`, so its rules, fingerprint and committed results are unchanged, and `docs/xxl.md`'s Results
  section, its analyses included, stays valid as the record of the first rules. The revised rules are measured by
  the scorecard, whose results go in a new section of `docs/xxl.md`. `--xxl` on any registered experiment runs the
  new defaults.
- **Existing tests unchanged, with one exception** (user decision, 2026-10-29): the xxl tests that pin the old
  defaults (for example the default rules line and `--xxl` fingerprint in `test_xxl_runner.jl`, and the default map
  in `test_xxl_config.jl`) are repointed at `XXL_V1`, keeping their assertions exactly. New tests, in new files,
  cover the new defaults. No other existing test changes, and none is weakened.

## Left to the builder

- How the scorecard script is structured, and whether it reuses `run_experiment` or calls the runner.
- How "traded in the last 10 periods" is counted, and how loans voided by death are recorded, within the meanings
  above.
- How the viable-site draw is made efficient (a list of empty viable sites per metabolism pair, or rejection
  sampling), as long as it is uniform over the eligible empty sites.
- Test design: each switch's book setting, its effect in a small world, and the reduction test.

## Calls I made

- The stage split and its order.
- Every scorecard threshold, the choice of II-4, IV-A3 and VI-1, 20 seeds, and the confirmation on seeds 20–39.
- Comparing II-4 and IV-A3 with xl (S4, S5), since without births there is no extinction to avoid.
- The four new switches and their defaults, in particular M = 4, the 1.5 free step, and leaving births where they
  are.
- Keeping the first rules as `XXL_V1`.
- Making the generated map the default, without controlling its sugar–spice correlation yet.
- The tie-break when choosing a stage-1 setting: fewest changes, then the higher travel cost; the leave-one-out trim;
  and what happens when confirmation fails.
- `free_step` waives the cost of a move whose target is within 1.5, and the valuation agrees, instead of
  discounting each period's step.
- The scorecard's new metrics as an opt-in column group, so ordinary `--xxl` output doesn't change.
- The 16 `XXL-…` experiments stay on `XXL_V1`, and `docs/xxl.md`'s existing results stay as its record.
