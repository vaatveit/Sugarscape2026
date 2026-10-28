# Every rule on the GPU: Chapters III to VI — Design

Date: 2026-10-25. Builds on the [Phase 1 design](2026-10-23-phase1-chapter2-gpu-design.md), the
[xl design](2026-10-24-xl-gpu-design.md), [device replacement](2026-10-25-gpu-replacement-metrics-design.md) and
[Python's order on the GPU](2026-10-25-gpu-sequential-semantics-design.md).

## Intent

The user's words: "the whole point of this effort is to build a gpu version that is equivalent to the python
version: all the same functionality. therefore the gpu version needs to be complete. then we'll time the two
versions and compare." The user skipped the design questions, so every choice below not quoted from the user is
*my call*.

Today the GPU runs Chapter II only. `bridge.config_cfg` refuses every other `Config` field, and the two Chapter
VI models aren't `Config` runs at all. So 117 of the 143 registered experiments can't run: all of Chapters III to
VI, the 59 variants, and two of the three test experiments.

**The problem every later rule shares.** In Python each agent takes its whole turn before the next agent starts:
move, eat, then mate, pass on culture, trade, lend and infect, using its neighbours as they stand at that moment.
An agent earlier in the order has already moved and acted; one later in the order is still where it started.
The GPU has matched that order so far only for movement (deferred acceptance) and for neighbour counts. Every
later rule is a pairwise exchange that changes the partners' state, so the order matters to all of them.

**What was measured before writing this** (scratch scripts, not in the repository).
- **Ordered waves.** Run every turn exactly in the period's order, but let turns run in the same wave when no
  turn earlier in the order could change what they read or write. The outcome is then Python's sequential
  outcome. The cost is the number of waves: the longest chain of turns that must run in order. Measured on Python
  states, one seed each:

  | Turns scheduled in waves | Regular size | xl |
  |---|---|---|
  | Whole turns, movement included | 34–388 | 703–11,491 |
  | Whole turns for combat, reads and writes kept apart | 81–308 | 3,678 (III-9 at t = 0) |
  | Everything after movement, with movement by deferred acceptance | 8–74 | 19–78; 343 for III-1 |

  A layer costs about 35 µs today, so whole turns with movement are too slow at xl. Movement keeps deferred
  acceptance, and the rest of the turn runs in waves. Combat has to schedule its whole turn in waves: its targets
  are occupied sites and its victims die, so deferred acceptance doesn't apply. That costs about 3,700 waves a
  period at the start of III-9 at xl (roughly 0.3–0.5 s), against Python's 10 s a period.
- **The hybrid's own differences, measured.** Python's model, changed to do exactly what this design does
  (movement chosen first by deferred acceptance from the start-of-period holdings, then every turn in order), was
  run on the 43 non-combat experiments with spice or interactions: 345 seeds, registered steps. A child was never
  placed on the target of an agent still to come. Scored against
  Python's saved results with the Julia agreement rule, **0 of 2,835 tested windows were flagged**. 12 had
  p < 0.01, where chance alone gives about 28.

## Goals

1. **Every rule and option Python has**, through the same `Config` fields:
   - Chapter III: sex S with every option (`mate_contact`, `child_gift`, `child_threshold`, `gift_rounding`,
     `fertility_threshold`, `child_share`), inheritance I, cultural tags, transmission K and friends, combat C_α and
     C_∞, tribal starting blocks, same-tribe replacement.
   - Chapter IV: spice, the welfare-based movement rule with foresight and cultural preferences, trade T with
     `trade_rounding`, credit L, `pollution_stop`.
   - Chapter V: disease E.
   - Chapter VI: the Schelling and Ring World models.
2. **Every metric Python records**, with Python's names and NaN conventions: the 45 columns of
   `sugarscape_metrics`, and `schelling_metrics` and `ring_metrics` for the two Chapter VI models.
3. **Every registered experiment runs** through `bridge.gpu_run`, variants included, at regular size and at xl
   (Python's own `to_xl`).
4. **Agreement with Python** on every registered experiment, under the Julia agreement rule (the
   [Julia design](../../../../docs/superpowers/specs/2026-10-24-julia-design.md), "Statistical agreement"):
   - each seed's mean of each metric over each quarter of the run;
   - a Welch t-test per (experiment, metric, quarter), and Fisher's exact test for extinction;
   - all p-values corrected together by Benjamini–Hochberg at q = 0.01.

   Every flag and every book-target status change is fixed or explained.
5. **Timing that can be compared**: every run writes `timing.csv` and `machine.txt` as today, and a speed table sets
   the GPU against Python, and Julia where it has results, per experiment, at regular size and at xl.

## Non-goals

- Matching Python's random stream. Agreement is statistical, as for Julia and for Chapter II.
- The controlled timing run itself. The user's words: "then we'll time the two versions and compare". This design
  delivers the tools and a development timing (Part F).
- Speed work beyond what the waves need. Speed is reported, not asserted.

## Anti-goals

- **No change to Chapter II.** Chapter II configurations keep today's path. Their existing metric columns stay
  bit-identical, and the four goldens' existing columns with them.
- **No silent difference from Python.** Every remaining difference is named below and measured.
- **No nondeterminism.** A seed gives the same output every time. Nothing that reaches an output may depend on the
  order of floating-point atomics. The one known exception stays as it is: FLAME GPU assigns new agents' ids in
  thread order, and outputs leave those ids out.
- **No silent limits.** Every capacity limit is checked and fails with a message naming it.
- **No hang.** A wave that runs no turn is a scheduler fault and ends the run with an error (exit 4).

## Constraints

- **Toolchain:** FLAME GPU 2 v2.0.0-rc.5, CUDA 13.4, RTX 4080, `scripts\build.cmd`, telemetry off.
- **Context7** lookups before FLAME GPU, CUB or Thrust code is written.
- **Macro-property rule** (FLAME GPU's own): within a layer a macro property is only read, or only atomically
  written. It is why the turns need the device store of section 3.
- **World size:** nothing may assume 50 × 50 or 500 × 500.
- **Saved GPU results become stale.** Every run's CSV gains the new columns, so `GPU_FINGERPRINT` changes and
  Chapter II is rerun in Part F. The four goldens are rewritten with the new columns, and their existing columns
  must not change. Approving this design approves that rewrite.

## Design

### 1. The period

**Without interaction rules** (none of sex, culture, trade, credit, disease or combat on), a run keeps today's
layers: deferred acceptance, commit, metabolism, neighbour counts, replacement, growback. That covers Chapter II,
and runs with tags or spice but nothing else (III-12, the no-trade points of IV-6 and IV-13). Tags and spice only
add variables, spice metabolism, and the welfare score in movement (section 4).

**With any interaction rule** (sex, culture, trade, credit or disease):
1. `start_period`: priority, direction order and look seed, as today.
2. Movement by deferred acceptance picks every agent's target, as today. Nothing moves yet.
3. **Publish**: every citizen copies its state into the device store (section 3).
4. **The turns** (section 2): each agent, in the period's order, moves to its target and takes the rest of its
   turn. Turns that can't affect each other run in the same wave.
5. **Absorb**: citizens read their state back, the dead are removed, and each newborn becomes a citizen, created
   by the cell agent at its site.
6. End of period, in Python's order: aging; old-age deaths with credit and inheritance; settling loans;
   replacement; growback; diffusion.

**With combat**, movement is part of the turn: steps 2 and 4 become one, and every turn runs in waves.

### 2. The turns: Python's order in waves

**The turn**, exactly as Python's `Model.step` runs it, for one agent:
1. Move: to the deferred-acceptance target, or by the combat scan.
2. Harvest, with production pollution.
3. Metabolism, with consumption pollution; death when sugar or spice runs out.
4. Neighbours.
5. S, then K and friends, then T, then L, then E (transmission, then the immune response).

Each rule's code follows its Python function line by line, draws included. Neighbours are recomputed where Python
recomputes them, and the list from before mating is kept where Python keeps it (`update_friends`).

**The footprint.** Before the waves, each turn lists the sites it may read and the sites it may write, from the
state at the start of the turns. Listed per rule:
- **Movement and harvest:** writes the agent's start site and target.
- **Neighbour rules (K, T, L, E, and S with `mate_contact = "neighbors"`):** read and write the four sites around
  the target. A child may go on any empty site around either parent, so mating also writes the four sites around
  each possible partner.
- **S with `mate_contact = "vision"`, for an agent of childbearing age:** the sight lines from the target, out to
  vision, at the period's look distances, and the four sites around each of them.
- **Partners anywhere in the world:** friends (K reads whether they are alive), credit counterparties and heirs.
  The agent lists each one's start site if it comes later in the order, or its target if it comes earlier. That is
  where the partner stands at this agent's turn, and the partner's own turn touches the same site. That shared
  site orders the two turns correctly.
- **Heirs born this period:** a starving agent's heirs include any child it had earlier in the same period, as
  another agent's partner. With inheritance on, an agent of childbearing age also lists where such a child can be
  born: the four sites around its start site, and around every site in sight of it.
- **Combat:** reads the start site's sight lines and, from each site on them, the retaliation sight lines. Writes
  the start site, every site on its sight lines (a target or a victim), and the neighbour-rule footprint of each.

**Scheduling.** A turn waits for every turn earlier in the order that writes a site it reads or writes, or that
reads a site it writes. Turns that only read the same site don't wait for each other.
- The footprints are fixed for the period. Every site lists its turns in key order, and each turn counts the
  turns it waits for.
- A wave runs every turn whose count is 0, then releases the turns that were waiting for it.
- The work per period is proportional to the total footprint, not to waves × agents. *My call*: re-reserving every
  pending turn each wave would cost combat at xl about 10¹⁰ atomic operations a period.
- Correctness depends only on the footprints being complete. They are conservative where the state can't tell in
  advance: every sight-line site is listed whether or not anyone stands there.
- **Combat with inheritance** can't bound its heirs in advance: a victim's children are found only at the turn. It
  runs one turn per wave, which is exact and slow. No registered experiment combines them.

**Serial mode** (`--serial-turns`, *my call*): one turn per wave, strictly in the period's order. Waves and serial
mode must give bit-identical output. That is the test that the footprints are complete.

**Within a wave**, a turn owns everything in its footprint. It reads and writes the device store directly, and
draws from FLAME GPU's per-thread random stream.

### 3. The device store

FLAME GPU can't let one agent's function write another agent's variables, and macro properties can't be read and
written in one layer. During the turns, the agents' state therefore lives in device buffers the run allocates for
the actual world size (*my call*):
- **One row per agent:** every per-agent `Config`-driven variable (holdings, metabolisms, vision, age, max age,
  sex and fertility ages, initial endowments, tags, immune genotype and phenotype, active diseases in infection
  order, friends, children, parents, displacement, last income, the uid), plus the turn's footprint.
- **Index maps:** a site → row map for occupancy, and a uid → row map for partners anywhere in the world.
- **The loan book** in Python's list order, and **this period's logs**: trades (count, sum and sum of squares of
  log price, sugar and spice moved) and new infections.
- **Newborns' rows**, beyond the population, in creation order.

Publish and absorb are two layers a period. Citizens stay the owners outside the turns, so deferred acceptance,
dumps, checks and metrics work as today.

**Creation order (uid).** Python numbers agents in creation order and acts on that order in several places: the
batch of old-age deaths, heirs' shares, `agents_ever`. FLAME GPU's ids aren't in creation order for agents born on
the device. Every agent therefore carries a `uid`, assigned in Python's creation order:
- founders in placement order;
- newborns in the order of their turns, and within a turn in mating order;
- newcomers in the order of the deaths that made room for them.

The period's order key stays `priority << 32 | id`, so Chapter II is unchanged. Two priorities tie about once in
4 × 10⁹ pairs.

### 4. Each rule's GPU form

The turn runs Python's code. These are the choices the GPU adds:
- **Holdings are double** (sugar, spice, loan amounts, welfare, the trade arithmetic; *my call*). Sites stay float.
  For Chapter II this changes no output: every Chapter II holding is a sum of whole numbers and eighths, exact in
  float, and the goldens check it.
- **Welfare movement** (spice on): deferred acceptance scores each site with Python's `welfare_scorer`, in double,
  from the start-of-period holdings (difference 3 below). That includes foresight's φ periods ahead and eq. 5's
  cultural fraction.
- **Sex S:**
  - Partners in sight use the period's look seed, one hash per line, as movement does.
  - A child is never placed on the target of an agent still to come (difference 2 below).
  - A child is born at age 0 and aged at the end of its birth period, as Python ages everyone in `model.agents`.
- **Inheritance I:**
  - A starving agent's share goes to its heirs inside its turn; the heirs are in its footprint.
  - Old-age deaths happen at the end of the period: each heir adds its dying parents' shares in the parents' uid
    order, which is Python's order of the dying batch.
- **Culture K:**
  - Tags are bits.
  - Friends are up to five (uid, distance at the encounter) pairs.
  - A friend counts as dead if it died before this agent's turn: on an earlier period, or at a turn earlier in this
    period's order.
- **Combat C:**
  - Python's `combat_candidates`, `vulnerable` and `combat_move`, with look distances from per-period hashes, one
    per scan.
  - A victim is removed in the attacker's turn and takes no turn of its own.
- **Trade T:** Python's `bargain`, in double. The period's price statistics are summed per turn in the order of the
  exchanges, then added in a fixed order of turns.
- **Credit L:**
  - Loans are made in turns in Python's list order: by turn, then by neighbour order within it.
  - A borrower's total owed is kept with the borrower.
  - When a lender starves, its loans are voided or passed to its heirs at once.
    - A borrower reads its total owed only in its own turn.
    - Borrowers of loans that existed at the start of the period are in the lender's footprint, and their totals
      change at once.
    - A loan made this period was made in its borrower's own turn, which is already over. That borrower's total is
      corrected at the end of the turns.
  - Settling at the end of the period runs through the book in order, on one device thread. The book holds
    hundreds of loans at regular size and thousands at xl.
- **Disease E:**
  - The master list is drawn on the host, as Python draws it, at setup.
  - Diseases with equal bit strings share one canonical id, so "already carrying it" and `diseases_circulating`
    compare strings, as Python's tuples do.
  - Immune strings are bits.
- **Replacement R with the same tribe:** each newcomer's tags are redrawn until their majority matches the dead
  agent's tribe, as in `random_tags`.
- **Founders, setup draws and tribal blocks** are placed on the host, as founders are today.

### 5. Limits

Each limit is checked at setup (exit 2) or when reached (exit 5, *my call*), with a message naming it. All are
*my call*; the registry needs at most the first value given.
- **Tags:** at most 63 bits (11 registered).
- **Immune string:** at most 64 bits (50 registered).
- **Master disease list:** at most 64 diseases (25 registered).
- **Living children an agent can pass an inheritance to:** at most 32 (the most seen in III-7 is 14).
- **Loans and uids:** buffers sized at setup from the world, with headroom.

### 6. Schelling and Ring World

Both are their own models in the same program (`--model schelling|ring`, *my call*), with their own config keys,
metrics and CSV columns.
- Both are small and inherently sequential. A Schelling mover may take any acceptable site in the world, and a Ring
  World agent leapfrogs into sites vacated earlier in the same period.
- Deferred acceptance would change both models. Each period's turns therefore run one at a time, in the period's
  order, in one kernel launched by a host function, whose threads share each turn's scan (*my call*).
- Their timings are reported like any other's, and the README says why the GPU doesn't help here.

### 7. Configuration, bridge, outputs

- **`run.cfg`** takes every `Config` field, with `initial_blocks` written as
  `tribe,x0,y0,w,h,n;tribe,...`. `config_cfg` passes every field, and `unsupported_features` stays as the guard
  for any field Python adds later.
- **The metrics CSV** has Python's 45 columns, in `sugarscape_metrics` order, for every sugarscape run, Chapter II
  included: Python writes them all for every run, and the agreement rule reads them.
- **`--init` and `--dump-agents`** gain the new variables as columns, for the tests.
- **`--version`** reports the limits.
- **Timing** keeps today's `timing.csv` and `machine.txt`. A speed table (stepping per period, GPU / Python and
  GPU / Julia ratios) joins the comparison report.
- **The comparison report** applies the Julia agreement rule, loading `julia/bridge/agreement.py` by path so the rule
  has one implementation (*my call*), and `gpu_report` scores every chapter's book targets.
- **xl** compares with Python where Python has xl results (II-4, II-4-gini, II-6, II-7, II-8, IV-A3), and with
  Julia's full xl registry elsewhere, labelled as such.

### 8. Differences from Python that remain

These come from choosing movement by deferred acceptance before the turns:
1. A site an earlier agent leaves, or a death frees, during the period isn't offered to agents later in the order.
   This is today's difference.
2. A child is never born on a site that an agent later in the order moves to. In Python the child takes the site,
   and the later agent goes elsewhere.
3. Movement scores sites with the holdings, tags and diseases the agent had at the start of the period. Python uses
   them as earlier agents' trades, gifts, loans, tag flips and infections have left them. This affects only the
   welfare score, so only spice runs.

The harness above measured all three together: 0 flags in 2,835 windows. Combat, Schelling and Ring World have
none of them.

## The work, in parts

Each part has its own plan, its own branch, one final review, and a merge. Each part's plan is written once the
part before it has merged, so it builds on real code (*my call*). Each part ends by running every experiment whose
rules are then all on the GPU and checking them against Python under the agreement rule.

- **A. The turns and Chapter III without combat:**
  - The device store, waves and serial mode, uid, tags, tribal blocks, S with every option, I, K and friends.
  - `society_metrics`, the 45-column CSV, and the `run.cfg` and bridge fields.
  - The harness, committed as `bridge/semantics_harness.py` with its result.
  - Unlocks III-1, -3, -4, -5, -7, -8, -12, -15, and the reproduction variants of III-1, -3, -4, -5 (24).
- **B. Combat:** combat turns and same-tribe replacement. Unlocks III-9, -11, -13, -14.
- **C. Chapter IV:**
  - Spice, welfare movement with foresight and cultural preferences, T, L, `pollution_stop`, `economic_metrics`.
  - Unlocks Chapter IV, VI-2, VI-3, their reproduction variants, and VAR-inttrade except VI-1's.
- **D. Chapter V:** disease and `disease_metrics`. Unlocks V-1, V-2, VI-1 and VAR-inttrade/VI-1.
- **E. Schelling and Ring World.** Unlocks VI-4 to VI-9 and their test experiments.
  Skipped by the user's decision (2026-10-27): "I am not interested in the Schelling and Ring World models."
- **F. Everything together:**
  - Chapter II rerun, every experiment at regular size, the full xl registry, the comparison and speed reports,
    the validation write-up, and the README's "How the GPU version differs" and results.

## Verification (pytest, in `flamegpu/tests/`)

1. **Rule parity:**
   - For every rule, small scenarios in which the order and the draws can't change the outcome, run through
     Python and the GPU and required to match (holdings to 1e-9).
   - The Julia port's scenario list (`julia/bridge/scenarios.py`) is the checklist.
2. **Serial equivalence:** waves against `--serial-turns`, bit-identical, for each part's rules, on small crowded
   worlds and several seeds each. This is the test that the footprints are complete.
3. **The scheduler:**
   - Every wave runs at least one turn.
   - Waves per period are reported.
   - A dependency test: in a chain of turns that each touch the next one's site, the order is the key order.
4. **Unchanged guards:**
   - Chapter II's goldens: the existing columns match, and the goldens gain the new columns.
   - The parity, sequential, replacement and xl tests, and `--check`.
5. **Agreement, per part and in Part F:**
   - Registered seeds, the Julia rule, every flag fixed or explained.
   - `gpu_report` for every chapter, every status change explained.
   - Waves and stepping per period reported per experiment.

## Left to the builder

- The layout of the device store, the footprint lists and the scheduler's counters (sort, scan or CSR), within
  section 2's rule that a period's work is proportional to the total footprint.
- Names, file split and the order of the columns that `--init` and dumps add.
- Each part's goldens: which small configurations, and how many.
