# Sugarscape xxl, stage 5: trade — Design

Stage 5 of the revised xxl rules, after "Adopting list D" and its reference rerun in `docs/xxl.md`. Stage 4 recommended judging trade
once disease was settled, and the user chose to go on with it. This stage measures why healthy agents trade so little, adds a switch
for movement that counts on trade, measures candidates and recommends one. It doesn't change `XXL_DEFAULTS`: that's the user's
decision, at the end.

Decisions are marked: **the user's** where the user made them, *my call* where I did. The user may overturn any of mine.

## Intent

The overall goal is a society where sex, culture, trade, credit and disease each work as intended and which rarely goes extinct.
Trade passes its checks today (X5: 98% of agents trade in a 10-period window; X6: price spread 1.15 times xl's), but not in the way
the user wants.

- **Trade follows sickness.** Stage 3 found trades per head go from 0.2–0.3 in seeds with no disease to about 2.4 with six, and
  correlate 0.9 with the count of diseases. Under list D, VI-1 has 3 diseases or fewer and reads about 1.34 trades per head at
  t = 301–500 and 1.13 at t = 1,501–2,000, with only 6–8% of agents sick at a time.
- **The user's ruling:** that bothers them. **Some healthy agents should trade in order to get rich**, and a healthy agent who trades
  should end up with more resources than one who doesn't (both **the user's**).
- **The healthy way to get rich** (my proposal, which **the user** accepted): gather whatever is plentiful where you stand and trade it
  for the other good instead of walking for it. In xxl each site walked costs `travel_cost = 0.2` sugar, so not walking is a saving.

**Why healthy agents trade little, as I read the code** (*my call*, untested; Part 1 tests it):
- Trade moves goods and makes none. One exchange swaps 1 sugar for p spice (or 1/p sugar for 1 spice) at the geometric mean of the two
  MRSs, and only while both welfares rise and the MRSs don't cross (`bargain!`, `julia/src/rules/trade.jl`). A trader who gains units
  gains them from its partner, or gains by trade saving it work.
- Movement assumes there's no trade. A site scores the welfare of the agent's holdings plus that site's sugar and spice (`welfare_score`
  and `SiteWelfare`, `julia/src/rules/welfare.jl`; used by `move!`, `xxl_move!` and `speed_move!`). An agent short of spice walks to
  spice. So every healthy agent keeps its holdings in about the balance its metabolisms want, healthy neighbours have nearly the same
  MRS, and they have little to trade.
- Disease adds its fee to the sugar side of the MRS (`sugar_burn` in `mrs`), which pulls a sick agent's MRS away from its neighbours'.
  That's the lead stage 3 left.

**A caution I can't settle without measuring:** 98% of agents trade within 10 periods and over 90% are healthy at any time, so most
healthy agents do trade already. What isn't known is with whom (a sick partner?), how much, and whether it leaves them richer. Part 1
answers that before any rule changes.

**A note for the builder on the economics** (*my call*). With Cobb-Douglas welfare and a fixed price p (spice per sugar), the best bundle
an agent can trade to from holdings worth V = sugar + spice / p is worth a constant times V. So an agent that expects to trade at p
ranks sites by the site's value at p, `sugar + spice / p` (after pollution devaluation), not by the welfare of the raw bundle. At p equal to
the agent's own MRS this is the book score's first-order term; the difference is that it is linear, with no diminishing returns, and uses
the market's price, not the agent's own. That is what lets an agent specialise. The risk is that trade happens only with neighbours,
one unit at a time, so an agent can't always realise p, and an agent that specialises among others who specialised the same way has no
one to trade with.

**My guess, written before measuring** (*my call*), so the study can show it wrong: under today's rules healthy traders end within 5% of similar healthy
non-traders, and most of their trades are with sick partners. Movement that counts on trade at a local price, with a guard for agents short
of a good, doubles trades per head in a world with no disease and leaves healthy traders at least 10% richer than similar non-traders, at a
small cost to the trough.

## Goals

1. Part 1: measure who trades with whom, and whether trade makes healthy agents richer today.
2. Part 2: an xxl switch for movement that counts on trade, off by default, so nothing changes until it's set.
3. Part 3: screen candidate versions on VI-1 against bars set before the runs, then confirm the best one with the full scorecard and
   the user's extinction bar.
4. Findings and a recommendation in `docs/xxl.md`, with the question of whether to adopt it put to the user.

## Non-goals

- Changing `XXL_DEFAULTS` or `XXL_V1`, or what a default run does. Adoption is the user's decision and a small step of its own after this.
- Changing rule T itself: the price, the unit exchange, the welfare tests, trading once with each neighbour. This stage changes what
  agents do before they trade.
- Changing credit or disease. Both are settled (credit by **the user's** ruling after stage 3; list D adopted in stage 4).
- Adding a scorecard check. The trade bars below are the study's. Whether one belongs on the scorecard is a question for the user at the end.
- Python, the viewer and FLAME GPU: Julia only, as in stages 1–4.

## Anti-goals

- **Sick agents stop trading.** Trade for a sick agent's fee is fine; the problem is that it's nearly the only trade (**the user's**
  concern as I read it; *my call* to make it a bar below).
- **Inequality jumps unnoticed.** The Gini is reported beside every result, and any rise of more than 0.03 is said up front (*my call*).
- **The book rules change.** With the switch off, a run's CSV must stay byte-identical and fingerprints must not change.
- **Reading a pass as a result.** Trades per head can rise for reasons that don't make anyone richer. The richer-with-trade bar is the
  one that answers the user.
- **Picking the winner on the seeds that confirm it.** Screening and confirmation use different seeds.
- **Buying trade with survival.** A candidate that deepens the trough beyond the bar below is refused.

## Part 1: who trades, and does it pay

**Resources** (*my call*): an agent's holdings valued at the run's mean price over the window being read, `sugar + spice / p̄`, so that
shifting toward the cheaper good doesn't count as getting richer. Raw sugar + spice and Cobb-Douglas welfare are reported beside it.

**A trade trace** (*my call*): for VI-1 under `XXL_DEFAULTS`, credit on, seeds 80–84, 500 periods, record each exchange with both agents'
state (healthy or sick, sugar, spice, MRS, metabolisms, and whether each moved this period and how far), and per agent per period its
holdings and whether it traded. A small tool or a script kept beside the results, as stage 3's loan trace was; *builder's call*. "Healthy"
means no active disease, so `sugar_burn(a) == a.metabolism`. Agents that recovered in the last 10 periods are also reported as a group of
their own, since a recent fee may still skew their holdings.

**Readings, at t = 301–500:**
- Exchanges and trades per head by pair: healthy–healthy, healthy–sick, sick–sick, against what random pairing of neighbours would give.
- For healthy agents: the gap between their MRS and their neighbours', in log terms, against the same for sick agents.
- The share of healthy agents who traded with a healthy partner at least once in the last 10 periods.
- **Traders against similar non-traders** (the comparison **the user** chose for the bar). Take the agents alive and healthy throughout
  t = 401–500. Group them into cells of the same sugar and spice metabolism, vision, age band (10 periods) and quintile of resources at
  t = 400; rich agents make more exchanges anyway, since each one-unit exchange moves their MRS less, so matching on the start matters.
  Within each cell, the third with the most exchanges in t = 401–500 are traders and the third with the fewest are non-traders. The reading
  is traders' mean resources at t = 500 ÷ non-traders', pooled over cells weighted by cell size, per seed, then the mean over seeds with
  a bootstrap over seeds. Cells with fewer than 6 agents are left out, and how many agents that leaves out is reported. Matching makes
  this fairer, not a randomised test.
- Sick agents' trades per head.

**Today's controls, the same seeds 80–99, 500 periods, no trace** (*my call*):
- **Trade on:** `XXL_DEFAULTS`. Also the baseline for screening. Today's traders against similar non-traders is read here, over 20 seeds,
  so this run records each agent's resources, health and identity at t = 400 and t = 500 and its exchange count over t = 401–500. So does
  every screening arm and the confirmation's extinction run (*builder's call* how: a snapshot beside the CSV is enough).
- **Trade off:** the same, with VI-1's `trade = false`. A reading, not a bar: healthy agents' mean resources, population and total
  resources with trade on ÷ off, by bootstrap over seeds, resampling each side independently, since seeds don't pair once trade changes
  the draws. A rule that helps can show up as more agents rather than richer ones, as credit did in stage 3, which is why this isn't the bar.
- **No disease:** `founder_diseases = 0`, so no disease ever circulates. Trades per head there are healthy trade only.
- **IV-A3 under `XXL_DEFAULTS`:** already in the scorecard, with sugar, spice and trade and no disease or births; trades per head and price, read from the scorecard's runs.

The tools need a way to turn VI-1's trade off. *Builder's call*, but it must show in the fingerprint and must not be an `XxlRules` field
that `XXL_DEFAULTS` could carry by accident.

**What Part 1 decides:**

| Result | Reading |
|---|---|
| Healthy agents are richer with trade today by the bar below, and healthy–healthy trade is common | The premise is wrong. Stop and report; what next is the user's call |
| Healthy agents are richer with trade today, but mostly by trading with sick partners | Go on to Part 2. Riches from selling to the sick are still trade that follows sickness, which is what the user objected to, and the no-disease bar tests it (*my call*) |
| Healthy trade is mostly with sick partners, and healthy MRS gaps are small | The diagnosis holds. Go on to Part 2 |
| Healthy trade is mostly with sick partners, but healthy MRS gaps aren't small | Go on to Part 2, and say the diagnosis was only half right: something besides movement keeps healthy neighbours from trading |
| Healthy agents trade with each other, but it doesn't pay | Go on to Part 2, and say the diagnosis was only half right |

The words in that table, set before Part 1 runs (*my call*): healthy–healthy trade is **common** when it meets the healthy-trade bar below
(25% of healthy agents in a 10-period window); healthy trade is **mostly with sick partners** when more than half of healthy agents'
exchanges have a sick partner; healthy MRS gaps are **small** when healthy agents' median |log MRS gap| to their neighbours is at most half
of sick agents'.

Part 1's readings may also correct the bar values below if one is already met today. Any change is made before screening, recorded in the
ledger and in the findings, and put to the user before screening starts (*my call*).

## Part 2: the switch

**Rule 13: movement that counts on trade.** New `XxlRules` field(s), off (`nothing`) by default (*my call*: names and exact shape are the
builder's). When on, under an experiment with trade, an agent scores a site by the value of the site's goods at its expected price, as in
the note above, instead of by the welfare of its raw bundle. The settings the candidates need:

| Setting | Values | What it does |
|---|---|---|
| Expected price | `own` (the agent's last trade price, falling back to its MRS) / `local` (the mean log price of trades within its vision over the last few periods, falling back to its MRS) | Which price p the agent expects |
| Blend | a weight from 0 to 1 | How far the score moves from the book's welfare score toward the value at p, so that 1 is the full rule. Builder's call how to blend two scores of different units, e.g. by ranking or by normalising each by the agent's own-site score |
| Guard | periods k, or none | An agent whose sugar or spice would last fewer than k periods at its metabolism scores by the book's rule, so it doesn't gamble on a trade it may not find |

- **Where:** in the site score shared by `move!`, `xxl_move!` and `speed_move!`, including remembered sites and word of mouth. A cached
  `SiteWelfare` stays exact for the book rule; the new score may need its own. Speed and travel cost don't change.
- **Experiments without trade:** `to_xxl` resets the field(s) to `nothing`, as it does the disease list, so a fingerprint never names a
  rule that can't apply.
- **Refused:** a blend outside 0–1, a negative guard, an unknown price source; the rule set on an experiment without trade if it reaches
  `Config` directly.
- **Fingerprint:** the field(s) appear only when on, after the disease list, so every existing fingerprint stays as it is.
- **Tools:** `xxl_scorecard.jl` and `xxl_extinction.jl` already take `--set`; they must parse the new field(s).
- **Tests:** byte-identical runs with the switch off; each setting reaches the config; the refusals refuse; `to_xxl` resets on an experiment
  without trade; fingerprints unchanged when off and naming the rule when on; on a small hand-built landscape, an agent with the rule
  chooses the site of greatest value at p where the book rule chooses the site that balances its holdings; the guard sends a short agent
  to the book's choice; the expected price falls back to the MRS with no trades. No existing test changes except one that counts the
  settings, which this request covers (*my call*).
- **`docs/xxl.md`:** Rule 13 in the style of rules 8–12, the settings table, refused combinations and fingerprint text.

## Part 3: the study

### Screening

**VI-1 under `XXL_DEFAULTS` plus the candidate, credit on, seeds 80–99, 500 periods, one run per candidate, with a trade-off twin**
(*my call*). The twin is Part 1's trade-off run, shared by every arm, since with trade off the rule doesn't apply. IV-A3 and the
no-disease world are run for each arm too: they are cheap and show healthy trade on its own.

| Arm | Expected price | Blend | Guard | Why |
|---|---|---|---|---|
| Today | — | — | — | Baseline, Part 1's runs |
| A | local | 1 | 5 | My guess |
| B | own | 1 | 5 | Does the agent need the market's price, or is its own enough? |
| C | local | 0.5 | 5 | Half the pull: less specialising, less risk |
| D | local | 1 | none | Is the guard needed? Expected to cost the trough |
| E | local | 1 | 15 | A cautious guard |

The arms are *my call*. If an arm is refused or crashes, that's a bug to fix, not a result. Runs use checkpoints, 5 workers, and memory
watched as in stages 3 and 4.

**Readings per arm, with the baseline's beside them:** trades per head by pair type (Part 1's), in VI-1, the no-disease world and IV-A3;
traders against similar non-traders; healthy agents' resources, population and total resources with trade on ÷ off; the share of healthy agents trading with a healthy partner; sick agents' trades per head; the
trough and when; births at t ≤ 100; population at t = 301–500, mean and spread; Gini; mean sugar and mean spice; mean price and price
spread (X6's reading); distance walked per agent per period; X9 and X10 per seed; and the scorecard's IV-A3 survivors (S5's reading).

### The reading table, set before the runs

An arm **passes screening** if all of these hold (*my call*; the values may change once after Part 1, as above):

| Row | Bar | Why |
|---|---|---|
| Richer with trade | Traders against similar non-traders (Part 1): at least 1.10, with the 95% interval above 1 | **The user's** goal and comparison, as a number |
| Healthy trade | At least 25% of healthy agents trade with a healthy partner in a 10-period window, t = 451–500 | "Some" healthy agents |
| Without disease | Trades per head in the no-disease world at least twice today's | Healthy trade that doesn't come from disease |
| Sick agents still trade | Sick agents' trades per head at least half today's | The anti-goal |
| Trough | Mean at least 95% of today's, no seed below 90% of today's lowest | Not bought with survival |
| Disease | X9 at least 18 of 20 seeds; X10 per seed at least 18 of 20 inside 0.01–0.2, over t = 451–500 | Stage 4's result kept |
| Prices | X6's reading at most 1.5 | Its scorecard bar |
| Extinction | None of 20 | The user's bar |

**Choosing among those that pass, in order** (*my call*): the largest ratio of traders to similar non-traders; then the smallest rise in
Gini; then the higher trough; then the simpler rule (no blend over a blend, own price over local).

| Result | Reading |
|---|---|
| One or more arms pass | Take the choice to confirmation |
| None passes, but one is near, meaning it misses one row by no more than 5% of the bar or by one seed | One further round of at most 3 arms around it, named in the ledger before running, on the same seeds. No more without the user |
| None passes after that | Stop. Report what failed and what that says about the idea. What next is the user's call. No confirmation run |
| Trades rise but healthy agents aren't richer | Say so plainly: more trade isn't the goal |

### Confirmation

The chosen arm, on the same terms as stages 2–4 (*my call*):

1. **The extinction test:** seeds 20–79, 2,000 periods, credit on. **0 of 60 extinct.** Against the reference rerun,
   `extinction-list-d-default-s20-60-p2000`.
2. **The scorecard:** seeds 0–19 and 20–39. **13 of 13 on both.** Against `scorecard-list-d-default-*`.
3. **Richer with trade, confirmed:** traders against similar non-traders, read at t = 401–500 of the extinction run on all 60 seeds, so that
   run records what the reading needs. It must pass its bar again. Trade off, seeds 20–39, 500 periods, is read beside it as in screening.

**Readings:** every screening reading over 60 seeds, and at t = 501–1,000 and t = 1,501–2,000 against the reference rerun. Which of
X1–X10 and S1–S5 moved, and how far.

| Result | Reading |
|---|---|
| 0 of 60, 13 of 13 on both, the ratio passes again | Recommend adopting it |
| Any seed extinct | Don't recommend it. Report what happened |
| A scorecard check fails | Report it. Recommend only if the user would accept that, and say what it costs |
| The ratio fails on the new seeds | Report it as not confirmed |

No reading changes after the runs. Anything found afterwards is labelled as found afterwards.

## Part 4: findings and the handover

A new section in `docs/xxl.md`, in the style of stages 3 and 4: the short answer; Part 1's readings and whether the diagnosis held; the arms;
the reading table with what fired; my guess against what happened; what this doesn't show; run time; and a recommendation that isn't a
decision. A fresh reviewer recomputes the figures from the CSVs and pushes on the strongest claims. The questions put to the user are
whether to adopt the chosen rule and whether a trade check belongs on the scorecard.

If the user adopts it, a separate small step changes `XXL_DEFAULTS`, makes saved default results stale and needs a reference rerun, as
list D did.

## Constraints

- All runs share stage 2's one generated map pair, so every finding is for those maps. Where sugar and spice sit on that pair decides how
  much specialising can pay, so this is a bigger limit here than in earlier stages.
- The machine is shared. Memory watched, 5 workers, runs resumable by stopping and running the same command.
- Rough time, from the reference rerun: about 20 minutes per VI-1 arm of 20 seeds at 500 periods, plus a few minutes for IV-A3 and the
  no-disease world; about 1 hour for the trace; about 7 hours for the extinction run; about 30 minutes per scorecard. About 12 hours in
  all. *My estimate.*
- Commits are by the user's approval. Rerun the Julia suite before any merge.

## Left to the builder

- Field names and the exact formulas for the expected price, the blend and the guard, within the meanings above. The docs must say what they mean.
- How "the last few periods" of the local price is counted, and what an agent with no trades in sight expects (its MRS).
- How the trace and screening readings are produced: a tool in `julia/` or scripts kept beside the results, so long as the figures can be
  recomputed from saved files.
- Whether the new score can stay as fast as today's. A slower score is acceptable for the study; a large slowdown is worth reporting.
