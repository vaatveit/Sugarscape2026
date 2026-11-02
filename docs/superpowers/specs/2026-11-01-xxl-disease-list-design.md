# Sugarscape xxl, stage 4: the disease list — Design

The first step of stage 4 of the revised xxl rules, after "Stage 3: why credit's mark lasts" in `docs/xxl.md`. The user read
those findings, ruled that **credit is working as intended** and chose **to design the disease list** (both the user's). This
step adds a switch, measures candidates and recommends one. It doesn't change `XXL_DEFAULTS`: that's the user's decision,
at the end.

Decisions are marked: **the user's** where the user made them, *my call* where I did. The user may overturn any of mine.

## Intent

The overall goal is a society where sex, culture, trade, credit and disease each work as intended and which rarely goes
extinct. Disease passes its checks today, but not in a way anyone would choose. VI-1 under `XXL_DEFAULTS`, seeds 20–79:

- **How much disease a seed ends with is close to a lottery, and it decides a lot.** Diseases at t = 500 run from 0 to 6, and
  from there population at t = 501–1,000 goes from about 77,000 to about 54,000, and trades per head from 0.3 to 2.4.
- **X9 passes narrowly and depends on credit.** 57 of 60 seeds have a disease at t = 500 with credit, 48 of 60 without, against a bar of 54.
- **X10 passes on the mean only.** The mean end share sick is 0.108, but 3 seeds are under 0.01 and 10 are over 0.2. Sickness follows the count:

  | Diseases at t = 2,000 | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
  |---|---|---|---|---|---|---|---|
  | Seeds, credit on | 3 | 1 | 20 | 7 | 13 | 11 | 5 |
  | End share sick (mean of t = 1,951–2,000) | 0 | 0.012 | 0.039 | 0.091 | 0.113 | 0.204 | 0.265 |

- **Most of the list does nothing lasting, but founders still pay for it.** A list of 25 at lengths 1–10, with 10 offered to each founder,
  gives each founder 4.25 diseases on average, at one sugar a period each. Lengths of 8 or less are 54% of that load, and almost none outlast t = 200:

  | Length | Listed per seed | Diseases per founder at t = 0 | Survive to t = 200, credit on | Credit off |
  |---|---|---|---|---|
  | 1–6 | 12.5 | 0.75 | 0 | 0 |
  | 7 | 2.48 | 0.70 | 0.000 | 0.007 |
  | 8 | 2.43 | 0.83 | 0.068 | 0.021 |
  | 9 | 2.60 | 0.96 | 0.449 | 0.205 |
  | 10 | 2.62 | 1.01 | 0.758 | 0.497 |

  Without disease the trough is 9,922 and with it 5,787, so this load is a large part of the one close call in stage 2.

**The idea** (*my call*, and untested): **the list's size sets a ceiling on disease, and its lengths set each disease's odds.** A short list of long diseases
should lift the trough, by dropping the load that does nothing lasting. It should cap the count, so the share sick can't run away. And it should keep disease
from dying out, since each disease has better odds and more hosts. VI-1's list came from the book's V-2 setting ("our call" in the registry) and was never chosen for this world, so
it's a fair thing to change in xxl.

**Note on starting carriers.** A founder is offered `p` of a list of `L`, so a long disease starts with about 20,000 × (p / L) × 0.96 carriers. Today's 10 of 25 gives 7,700.
Founders' load is about p × 0.96 for a list of only long diseases.

**My guess, written before measuring** (*my call*), so the study can show it wrong: 4 diseases of length 9–10, 2 offered to each founder, lifts the trough by a quarter or more, ends
with about 3 diseases per seed, passes X9 at 0.95 or better and puts at least 18 of 20 seeds inside X10's band. A list of 10 long diseases fails X10.
Going beyond the book's length of 10 isn't needed.

## Goals

1. An xxl switch for the disease list, at the book's setting by default, so that nothing changes until it's set.
2. Measure candidate lists on VI-1 against a reading table set before the runs.
3. Confirm the best one with the full scorecard and the user's extinction bar.
4. Findings and a recommendation in `docs/xxl.md`, with the question of whether to adopt it put to the user.
5. `docs/xxl.md` records the user's ruling that credit is working as intended, since its text still says that's the user's call.

## Non-goals

- Changing `XXL_DEFAULTS` or `XXL_V1`, or what a default run does. Adoption is the user's decision and a small step of its own after this one.
- Changing how disease works: the immune response, transmission, the fee of 1 sugar, inheritance of immune genotypes. This stage is about which diseases there are.
- Changing X9's or X10's bars, or adding a scorecard check. Per-seed readings are reported in the study only.
- Judging trade. Trade is mostly set by disease (stage 3), so a new list will move it. X5 and X6 must still pass, and the level is reported. Whether it's right waits until disease is settled.
- Python, the viewer and FLAME GPU: Julia only, as in stages 1–3.

## Anti-goals

- **Propping disease up.** No reintroducing a disease that died out, and no rule that keeps a disease alive by force. X9 would then mean nothing.
- **Reading a pass as a result.** 13 of 13 is required, not sufficient. The point is that the outcome stops depending on a lottery, so spread is read beside the checks.
- **Picking the winner on the seeds that confirm it.** Screening and confirmation use different seeds.
- **Changing a run by adding a switch.** With the settings at their book values a run's CSV must stay byte-identical, and fingerprints must not change.
- **Trading the trough for disease.** A candidate that passes X9 by deepening the trough is refused.

## Part 1: the switch

**Rule 12: the disease list.** Three new `XxlRules` fields, each `nothing` at the book's setting, meaning the experiment's own value:

| Setting | Book setting | What it does | Config field it replaces |
|---|---|---|---|
| `disease_count` | none | Diseases on the master list | `disease_list` |
| `founder_diseases` | none | Diseases offered to each founder | `diseases_per_agent` |
| `disease_lengths` | none | Lowest and highest length, inclusive | `disease_length` |

- **Where:** `to_xxl` puts them into the config, as it does the map. The rules themselves (`init_disease_list!`, `infect_founders!`) don't change, and neither does their
  draw order. A founder is still offered diseases and is still skipped for one it's immune to.
- **Experiments without disease:** for a base experiment with `disease_list == 0`, `to_xxl` sets the three back to `nothing`, as it does `founder_ages`, so a fingerprint never names a rule that can't apply.
- **Refused:** a count below 1; founder diseases below 0 or above the count; a length range that isn't lo ≤ hi with lo ≥ 1, or whose hi reaches `immune_length` (Config already refuses that last one and a per-agent count above the list). Any of the three set on an experiment without disease, if it reaches `Config` directly.
- **Fingerprint:** each of the three appears only when off its book setting, after the four stage-1 settings, so every existing fingerprint stays as it is and no saved result goes stale.
- **`xxl_on`:** a `:disease_list` feature, true when any of the three is set, if the code needs one. *Builder's call.*
- **Tools:** `xxl_scorecard.jl` already takes `--set field=value`. It must parse these. `xxl_extinction.jl` has no `--set`, so it gets one, with the same meaning and in its fingerprint, so a candidate can have an extinction run without being a default. `--report-only` must take it too.
- **Tests:** the switch at book settings leaves a run byte-identical with today's; each setting reaches the config; the refusals refuse; `to_xxl` resets on an experiment without disease; fingerprints are unchanged at book settings and name a setting when it's on; the two tools' `--set` parse. Any existing test that assumes "thirteen settings" changes to match (*my call*: this request covers that and no other test changes).
- **`docs/xxl.md`:** Rule 12 in the style of rules 8–11, the settings table, refused combinations and fingerprint text.

## Part 2: the study

### Screening

**VI-1 under `XXL_DEFAULTS` plus the candidate, credit on, seeds 80–99, 500 periods, one run per candidate** (*my call*). The seeds are new, so the winner isn't picked on the seeds that confirm it. Today's baseline for comparison is the existing 60 seeds 20–79. They don't need rerunning, since a different list changes the random stream from the start, so seeds wouldn't pair anyway.

| Arm | `disease_count` | `founder_diseases` | `disease_lengths` | Load per founder, about | Starting carriers, about | Why |
|---|---|---|---|---|---|---|
| Today | 25 | 10 | (1, 10) | 4.25 | 7,700 at length 10 | Baseline, existing runs |
| A | 6 | 2 | (9, 10) | 1.9 | 6,400 | Today's long diseases, without the rest |
| B | 4 | 2 | (9, 10) | 1.9 | 9,600 | My guess |
| C | 4 | 2 | (10, 10) | 1.9 | 9,600 | Same, at better odds |
| D | 3 | 1 | (9, 10) | 1 | 6,400 | The lightest load |
| E | 10 | 4 | (9, 10) | 3.8 | 7,700 | Today's load, all long: the ceiling check. Expected to fail X10 |
| F | 4 | 2 | (12, 12) | 2 | 10,000 | Beyond the book's lengths: does a longer disease need less luck? |

The arms are *my call*. If an arm is refused or crashes, that's a bug to fix, not a result. Runs use `run_extinction`-style checkpoints, 5 workers, and memory watched as in stage 3.

**Readings per arm, from the run CSVs, with the baseline's over 60 seeds beside them.** Trough and when; births at t ≤ 100; diseases circulating at t = 100, 200 and 500, mean, sd and distribution; X9's share at t = 500; end share sick, mean, and seeds inside 0.01–0.2 (mean of the last 50 periods); population at t = 301–500, mean and spread over seeds; Gini; mean sugar; trades per head; mean price.

Intervals: ratio of means against the baseline, by bootstrap over seeds, resampling each side independently since seeds don't pair. Twenty seeds are enough to rank arms and not enough to prove them. Confirmation does that.

### The reading table, set before the runs

An arm **passes screening** if all of these hold (*my call*):

| Row | Bar | Why |
|---|---|---|
| X9 | At least 18 of 20 seeds | The scorecard's bar on these seeds |
| X10, mean | 0.01–0.2 | The scorecard's bar. Read over t = 451–500, an early reading of the end share |
| X10, per seed | At least 18 of 20 inside 0.01–0.2, over t = 451–500 | The lottery is the problem. Today's reads 42 of 60 over the same window (4 under, 14 over) and 47 of 60 at the end |
| Trough | Mean at or above today's 5,787, with no seed below today's lowest of 3,441 | The anti-goal above |
| Extinction | None of 20 | The user's bar |

**Choosing among those that pass, in order** (*my call*): the most seeds inside X10's band; then the smallest spread of population over seeds at t = 301–500; then the book's own lengths over longer ones; then the shorter list. Arm F can only win if no arm within the book's lengths passes.

| Result | Reading |
|---|---|
| One or more arms pass | Take the choice to confirmation |
| None passes, but one is near, meaning it misses one row by one seed or by no more than 5% of the bar | One further round of at most 3 arms around it (*my call*), named in the ledger before running, on the same seeds. No more without the user |
| None passes after that | Stop. Report what failed. The idea was wrong, and what next is the user's call. No confirmation run |
| A passes and B–D don't | The ceiling matters less than the idea says. Say so |
| E passes X10 | The ceiling isn't where I think it is. Say so |

### Confirmation

The chosen arm, on the same terms as stage 2 and stage 3, so everything compares (*my call*):

1. **The extinction test:** seeds 20–79, 2,000 periods, credit on. The bar is the user's: under a 5% chance, at 95% confidence, so **0 of 60 extinct**. Today's run is `extinction-defaults-s20-60-p2000`.
2. **The scorecard:** seeds 0–19 and seeds 20–39, as stage 1 confirmed the defaults. It must read 13 of 13 on both.
3. **Credit off:** seeds 20–39, 500 periods. X9 and the count, to see whether disease still depends on credit. This is a reading and not a bar. The user ruled credit is working, so credit stays on.

**Readings:** every reading above over 60 seeds, and at t = 501–1,000 and t = 1,501–2,000 against today's. Diseases at t = 2,000 as well as t = 500. Whether seeds lose diseases after t = 200. The table of the share sick by count. Which of X1–X10 and S1–S5 moved, and how far. Trades per head and price, reported with no bar.

| Result | Reading |
|---|---|
| 0 of 60, 13 of 13 on both seed sets, per-seed X10 at 0.9 or better | Recommend adopting it |
| Any seed extinct | Don't recommend it. Report what happened |
| Passes, but per-seed X10 falls under 0.9 | Report it as an improvement, if it is, and say the lottery is still there |
| A scorecard check fails | Report it. Recommend only if the user would accept that, and say what it costs |

No reading changes after the runs. Anything found afterwards is labelled as found afterwards.

## Part 3: findings and the handover

A new section in `docs/xxl.md`, in the style of stage 3's: the short answer, the table of arms, the reading table with what fired, my guess against what happened, what this doesn't show, run time and a recommendation that isn't a decision. It records the user's ruling on credit. A fresh reviewer recomputes the figures from the CSVs and pushes on the strongest claims, and any figure it offers is recomputed before use. The question put to the user is whether to adopt the chosen list.

If the user adopts it, a separate small step changes `XXL_DEFAULTS`, which makes saved default results stale and needs its own run list. That isn't part of this design.

## Constraints

- All runs share stage 2's one generated map pair, so every finding is for those maps.
- The machine is shared. Memory watched, 5 workers, runs resumable by stopping and running the same command.
- Rough time, from stages 2 and 3: about 50 minutes per screening arm, 5 hours for six; about 12–15 hours for the extinction run, more if population runs well above today's; about 40 minutes per scorecard; about 1 hour for credit off. About 20 hours in all. *My estimate.*
- Commits are by the user's approval. Rerun the Julia suite before any merge.

## Left to the builder

- Field names may change if the code suggests better ones, as long as the docs say what they mean.
- How the screening readings get produced: a small tool in `julia/`, or scripts kept beside the results as in stage 3, so long as the figures can be recomputed from the CSVs.
- Whether `xxl_credit_compare.jl` can be reused for the intervals. Its seed-pair bootstrap is fine for independent seeds only if it's noted, and resampling each side independently is what this design asks.
