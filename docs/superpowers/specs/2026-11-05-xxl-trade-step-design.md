# Sugarscape xxl, stage 5c: smaller trade steps — Design

The next step of stage 5 (trade), after "Stage 5b: the meeting's price" in `docs/xxl.md`. Stage 5b found a meeting moves 1.68 units on
average, and that one whole unit narrows a healthy pair's gap in log MRS by about 0.15 against a typical gap of 0.068: the unit is too
large for most healthy pairs to trade at all. The user chose smaller units next (**the user's**). This step adds a setting for the size of
a trade step, screens it alone and with Rule 14, and recommends. It doesn't change `XXL_DEFAULTS`.

Decisions are marked: **the user's** where the user made them, *my call* where I did. The user may overturn any of mine.

## Intent

The goal is unchanged (**the user's**): some healthy agents should trade in order to get rich; a healthy agent who trades should end up
with more resources than a similar one who doesn't.

**The idea.** With a step a tenth of today's unit, one step narrows a pair's gap by about 0.015, about a fifth of a typical healthy gap,
so a typical healthy pair can take four or five steps before their MRSs would cross, where today most can take none. With Rule 14 the
whole meeting trades at its starting price, so a seller keeps a margin on every one of those steps.

**My guess, written before measuring** (*my call*): with tenth steps, healthy pairs trade far more often, sugar moved per head with no
disease at least doubles, and the matched ratio rises; with Rule 14 too it rises more, past 1.145. Survival is unchanged.

## Decisions

- **Two arms** (**the user's**): S, smaller steps with the book's price recomputed each step; SM, smaller steps with Rule 14's meeting
  price.
- **The step is a fixed tenth of today's unit** (my proposal, **the user's** approval): p > 1: 0.1 sugar for 0.1·p spice; p < 1: 0.1/p
  sugar for 0.1 spice.
- **The no-disease bar is measured in sugar moved, not trades counted** (my proposal, **the user's** approval): with tenth steps the count
  of exchanges would rise about tenfold from the smaller step alone. The bar is still at least twice today's.
- **"Traders" are the agents who moved the most goods** (**the user's**, after the builder check): the matched comparison ranks agents in
  each cell by sugar moved in the window, not by exchanges counted. The snapshot gains a per-agent sugar-moved column. Today's matched
  ratio is recomputed the same way from the extra baseline run (Part 3), and that figure, not stage 5's 1.09, is the "today's" the
  Richer bar compares with (×1.05 and the arm ÷ today interval), so the bar compares like with like.

## Goals

1. An xxl setting for the trade step, at the book's size by default, so nothing changes until it's set.
2. Screen S and SM against today, with the stage-5 bars as the user left them except the no-disease bar's measure.
3. Findings and a recommendation in `docs/xxl.md`; confirmation only if an arm passes and the user says go.

## Non-goals

- Steps sized to each agent's holdings, or trading the exact amount that brings two MRSs together (set aside, my proposal, the user agreed
  to the tenth).
- Changing the price rule (Rule 14 is used as it is), the welfare and no-crossing tests, or trading once with each neighbour.
- Rule 13. `XXL_DEFAULTS`, Python, the viewer, FLAME GPU.

## Anti-goals

- **Changing a run by adding a setting.** With the step at 1, every run's CSV stays byte-identical and fingerprints don't change.
- **Counting smaller steps as more trade.** Every volume bar reads goods moved.
- **Starting a run without the user's go-ahead** (**the user's**, standing).

## Part 1: the setting

**Rule 15: the trade step.** One new `XxlRules` field, `trade_step::Float64 = 1.0` (*my call*: name and type), the share of today's unit
a step trades. In `bargain!` the step's sugar and spice are both multiplied by it, in both price rules; nothing else changes.

- **Refused:** a step at or below 0, above 1, or not finite; a step other than 1 with `trade_rounding = "down"` (whole units would round
  a tenth to nothing; *my call*); a step other than 1 on an experiment without trade if it reaches `Config` directly.
- **Experiments without trade:** `to_xxl` resets it to 1.
- **Fingerprint:** shown only when it isn't 1, after Rule 14's setting.
- **Exactness:** with the step at 1 the code must do today's arithmetic exactly (multiply only when the step isn't 1, or show that
  multiplying by 1.0 changes no bytes; the pinned digests decide).
- **Tests:** byte-identical with the step at 1; the refusals; the reset; the fingerprint; `--set trade_step=0.1` parses; on two hand-made
  agents, a step of 0.1 moves a tenth of the book's unit each time, takes more steps than the book's unit before stopping, and with Rule
  14 every step trades at the meeting's price.
- **`docs/xxl.md`:** Rule 15 in the style of rules 13 and 14.

## Part 2: readings and the report

Measuring in goods (*my call*, following the user's ruling on the no-disease bar so that no bar counts steps):
- **Without disease:** sugar moved per head, `sugar_traded` ÷ population (columns of the seed CSV, which today's folders have), over
  t = 301–500, at least twice today's.
- **Sick agents still trade:** at least half today's, read as sugar moved in exchanges with a sick agent per sick agent. Today's trade
  readings count exchanges only, so the observer gains per-period sugar-moved columns for the pair types (healthy–healthy, healthy–sick,
  sick–sick, as the exchange columns are split). Today's baseline lacks them, so for this one bar today's figure is read from a new
  run of today's rule: see Part 3.
- **Sugar, with spice beside it** (*my call*): a unit moves 1 sugar when p > 1 and 1/p when p < 1, so sugar moved weights low-price
  meetings a little more; spice moved (`spice_traded`) is shown beside every sugar figure, deciding nothing.
- **X6 stays the scorecard's** (*my call*): `price_sd` weights each exchange equally, so smaller steps reweight it towards long
  meetings. It keeps its definition, since it is the scorecard's check against xl, and the report says it is step-weighted. The regional
  price spread and the price–distance slope decide nothing.
- **Readings beside the bars:** sugar moved per head by pair type, exchanges per head (shown, deciding nothing), units per meeting in
  goods (sugar per meeting), the price spread across meetings, the matched ratio's raw and welfare versions, trade on ÷ off.
- The report names Rule 15 with Rule 14 in its arms table, and reads stage-5 and stage-5b folders as it does now.

## Part 3: screening

**Arms, seeds 80–99, 500 periods, in VI-1, the no-disease world and IV-A3 (300 periods):**

| Arm | `trade_step` | `trade_price` |
|---|---|---|
| S | 0.1 | book |
| SM | 0.1 | `"meeting"` |

**Baseline** (*my call*): stage 5's Part 1 rerun for every bar its folders can read. For sick agents' sugar moved and for the matched
ratio ranked by goods, which they lack, one new run of today's rule in VI-1 on the same seeds with the new observer (`trade-p1b-today-…`), checked byte-identical in its seed CSVs
(`seed<k>.csv` only: its trade files gain columns by design) with Part 1's `trade-p1-today-VI-1-s80-20-p500`. That's three runs per arm plus one, about 2–3 hours: smaller steps mean more exchanges each
period, so runs take longer than stage 5b's (*my estimate*).

**Bars:** stage 5's, as the user left them, with the measures above: Richer with trade, traders ranked by goods moved (at least 1.10
with its interval above 1, at least 1.05 × today's from the extra baseline run, the arm ÷ today interval above 1); without disease (sugar moved per head, ×2); sick agents still trade (sugar moved,
×0.5); the trough; X9 and X10 per seed; X6; no extinction.

**Results** (5b's table, applied by hand, *my call*): an arm that passes goes to confirmation, with the user's go-ahead; near (every
failing row within 5% of its bar, or a seed-counted row by one seed) earns one further round with the user's go-ahead; otherwise stop and
report. If both pass, choose by the larger matched ratio. Say plainly if only the volume bar fails with the Richer row passing.

## Part 4: confirmation and findings

As stage 5b: confirmation (the extinction test, both scorecards, the study run on seeds 20–79) only for a passing arm and only on the
user's go-ahead. Findings in `docs/xxl.md` after "Stage 5b", reviewed, committed with the user's approval.

## Constraints

- One map pair; 5 workers; memory watched; every run with the user's go-ahead.
- Build on branch `xxl-trade-step` from `xxl-trade-price` (604e60b), so Rule 14 is there for SM. Commits by the user's approval. The
  suite before every commit to `julia/src`; `julia/src` frozen during runs. Files LF.

## Left to the builder

- The field's name and docs wording.
- The new observer columns' names and order (appended at the end, in the trade file and the snapshot), and how the report reads three
  column sets (stage 5's, 5b's, 5c's) and two snapshot formats.
