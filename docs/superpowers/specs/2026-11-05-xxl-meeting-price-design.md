# Sugarscape xxl, stage 5b: the meeting's price — Design

The next step of stage 5 (trade), after "Stage 5: trade" in `docs/xxl.md`. The user agreed not to adopt any version of Rule 13 and asked
to investigate trades larger than one unit (both **the user's**). This step adds a rule for how a meeting is priced, screens it against
today, and recommends. It doesn't change `XXL_DEFAULTS`: that's the user's decision, at the end.

Decisions are marked: **the user's** where the user made them, *my call* where I did. The user may overturn any of mine.

## Intent

The goal is unchanged from stage 5 (**the user's**): some healthy agents should trade in order to get rich; a healthy agent who trades
should end up with more resources than a similar one who doesn't.

**The user's reasoning.** In rule T (`bargain!`, `julia/src/rules/trade.jl`) two neighbours trade one unit at a time (1 sugar for p spice,
or 1/p sugar for 1 spice), and the price p is recomputed before every unit as the geometric mean of their current MRSs. Each unit moves
the two MRSs towards each other, so the price follows them and the last units are worth almost nothing to either side. The user's view:
it isn't realistic for the MRS to set a new price during a single bargaining session. The price should be set when the session starts and
apply to every unit exchanged, and there has to be a way for the seller to profit from a trade, not just break even.

**What a session already moves.** `bargain!` loops until a unit would not raise both welfares or would cross the MRSs, so a meeting already
trades about as much as both sides want. The change is to the price, not to how much one exchange step holds.

**How a healthy agent profits** (*my call*, the reading the stage-5 bar measures). Resources are valued at the market's mean price. With a
price fixed per meeting, prices differ between meetings by who meets whom, so an agent can sell dearly to a neighbour in need (a sick agent
valuing sugar highly) and buy cheaply from one with a good to spare. Today the per-unit price follows the pair's MRSs down to where they
meet, which squeezes that out.

**My guess, written before measuring** (*my call*), so the study can show it wrong: with the meeting's price, each meeting moves fewer units
than today (it stops when the first agent's MRS reaches the price, where today's moving price lets the pair go on), so trades per head fall,
in the no-disease world too, and the no-disease bar fails. Healthy traders' matched ratio rises a little, to about 1.12, short of the bar's
1.145. If so, the bar that fails is the volume bar, and that is worth saying plainly.

## Goals

1. An xxl switch for the meeting's price, at the book's setting by default, so nothing changes until it's set.
2. Screen it on VI-1 against the stage-5 bars, as they stand after the user's changes, with today's runs from stage 5's Part 1 rerun as the
   baseline.
3. If it passes, confirm it, with the user's go-ahead for every run. If it fails, report, and put the second version to the user.
4. Findings and a recommendation in `docs/xxl.md`.

## Non-goals

- Rule 13. It stays off and isn't combined with this.
- Changing how many units a step holds, the welfare tests, the no-crossing test, or trading once with each neighbour in random order. Only
  the price changes.
- A price that leans towards one side. It's the second version, screened only if the user agrees after this one fails (below).
- New scorecard checks, `XXL_DEFAULTS`, Python, the viewer, FLAME GPU.

## Anti-goals

- **Changing a run by adding a switch.** With the setting off, a run's CSV stays byte-identical and fingerprints don't change.
- **Starting a run without the user's go-ahead** (**the user's**, standing).
- **Reading more trade as success.** The matched ratio answers the user; volume is one bar among several.
- **Buying trade with survival.** The trough, disease and extinction bars hold.

## Part 1: the switch

**Rule 14: the meeting's price.** One new `XxlRules` field, `trade_price::Union{Nothing,String} = nothing` (*my call*: the name; the
builder may pick a better one and say so):

| Value | What a meeting does |
|---|---|
| `nothing` (book) | Today's rule T: the price is the geometric mean of the two current MRSs, recomputed before every unit |
| `"meeting"` | The price is the geometric mean of the two MRSs when the meeting starts, computed once. Which agent buys sugar (the one with the higher MRS then) is fixed for the meeting too. Every unit trades at that price, with the book's unit sizes (p > 1: 1 sugar for p spice; p < 1: 1/p sugar for 1 spice; whole units with `trade_rounding = "down"`) and the book's tests on each unit: holdings stay positive, the buyer's MRS stays at or above the seller's, and both welfares strictly rise. The meeting ends at the first unit that fails a test |

- **Where:** `bargain!`. Each accepted unit still goes to `m.trade_log` with its price, so the trade log, `last_price` (Task 2 of stage 5)
  and every metric read it as before.
- **Validity:** a meeting whose starting MRSs aren't both valid (`valid_mrs`) or are equal doesn't trade, as now.
- **Experiments without trade:** `to_xxl` resets it to `nothing`, as it does Rule 13.
- **Refused:** an unknown value; the rule set on an experiment without trade if it reaches `Config` directly.
- **Fingerprint:** it appears only when on, after Rule 13's fields, so every existing fingerprint stays as it is.
- **Tools:** `--set trade_price=meeting` must parse in `xxl_extinction.jl`, `xxl_scorecard.jl` and `xxl_trade_study.jl`.
- **Report:** `xxl_trade_report.jl`'s arms table names the rule's setting (today it names Rule 13's). It must also read a baseline folder
  made by an earlier commit of the code: the code's checksum line differs, which a finished folder may.
- **Tests:** a run with the setting off is byte-identical with today's; the refusals refuse; `to_xxl` resets without trade; fingerprints
  unchanged when off and naming the rule when on; `--set` parses; and on two hand-made agents, every unit of a meeting trades at the
  starting price, the meeting stops at the first unit that would not raise both welfares, and the units and the stopping point differ from
  the book's on the same pair.
- **`docs/xxl.md`:** Rule 14 in the style of rules 12 and 13: what it does, the setting, refused combinations, fingerprint text.

## Part 2: screening

**One arm, M: `trade_price = "meeting"`, under `XXL_DEFAULTS`, seeds 80–99, 500 periods**, run with `xxl_trade_study.jl` in VI-1, the
no-disease world (`founder_diseases = 0`) and IV-A3 (300 periods), the same as stage 5's arms (*my call*).

**Baseline:** stage 5's Part 1 rerun: `trade-p1-today-VI-1-s80-20-p500`, `trade-p1-nodisease-VI-1-s80-20-p500`,
`trade-p1-today-IV-A3-s80-20-p300`, with `trade-p1-off-VI-1-s80-20-p500` for trade on ÷ off and `scorecard-xl-s80-20/VI-1` for X6, all in
the main checkout's `results-julia-xxl/`, where M's folders go too. With the setting off, the code makes the same runs, so they stand
(*my call*).

**Bars:** stage 5's screening bars as they stand after the user's changes, read by the report's screening mode unchanged (**the user's**,
"the same bars"):
- Richer with trade: traders ÷ similar non-traders (strictly healthy, last 20 periods) at least 1.10 with its interval above 1, at least
  1.05 × today's (1.09, so 1.145), and the arm ÷ today interval above 1;
- without disease: trades per head at least ×2 today's (0.308, so 0.617);
- sick agents still trade (at least ×0.5 today's 7.53), the trough (mean at least 95% of 8,544, none below 90% of 8,027), X9 and X10 per
  seed (18 of 20), X6 at most 1.5, and no extinction.

**Readings beside the bars,** from the report as it is: trades per head by pair, mean price and the price spread (X6's reading), the
matched ratio's raw and welfare versions, trade on ÷ off, distance walked. Two more help read a price rule (*my call*): the mean units per
meeting (exchanges ÷ meetings) and the spread of prices across meetings within a period. If the trade log can't tell meetings apart without
changing the run, the builder adds what's needed to the observer, not the simulation.

| Result | Reading |
|---|---|
| M passes | Recommend confirmation; ask the user before any run |
| M is near (every failing row within 5% of its bar, or one seed) | One further round, with the user's go-ahead: the second version below and at most one variant of M |
| M fails | Stop and report. Put the second version to the user |
| The no-disease bar alone fails, with the Richer row passing | Say so plainly: the price rule makes healthy traders richer with less trade. Whether that bar should stand is the user's call |

The rows are read in order, and the first that holds is the result, except that the last row's sentence is said whenever it holds
(*my call*). "One seed" in the near row means a row counted in seeds (X9, X10 per seed, extinction) missed by one seed, as the report's
screening mode already reads it.

**The second version, not built yet:** the price leans towards the agent who needs the trade less (for example the one whose MRS is nearer
the market price). It needs a design of its own and a number to set, so it is the user's call after M.

## Part 3: confirmation, only if M passes and the user says go

As stage 5 designed it: the extinction test (seeds 20–79, 2,000 periods, 0 of 60), both scorecards (13 of 13 on seeds 0–19 and 20–39), and
the study run on seeds 20–79 with the matched ratio against today's from Part 1, plus trade off on seeds 20–39 as a reading.

## Part 4: findings

A section in `docs/xxl.md` after "Stage 5: trade": the short answer, the rule, the reading table with what fired, my guess against what
happened, what this doesn't show, run time, and a recommendation that isn't a decision. A fresh reviewer recomputes the figures.

## Constraints

- One map pair; 5 workers; memory watched; every run with the user's go-ahead first.
- Rough time: three screening runs, about 1½–2 hours, more if the machine is shared.
- Build on branch `xxl-trade-price` from `xxl-trade` (bf4aa65). Commits by the user's approval. The suite before every commit that touches
  `julia/src`, and `julia/src` frozen during runs.

## Left to the builder

- The field's name and the docs' wording.
- How meetings are counted for the units-per-meeting reading.
