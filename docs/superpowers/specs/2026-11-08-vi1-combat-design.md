# VI-1 with combat — design

The user asked: "make a variant of experiment VI-1 that turns on combat. the attacker takes all the victim's wealth. there
is no automatic replacement of dead agents." Then "skip the questions". Everything below that isn't quoted from the
user is **my call**, marked as such, for the user to accept or change when approving.

## Intent

VI-1 is the book's artificial society: sugar and spice, sex, culture, trade, credit and disease all on (pp.154–157).
Combat is the one Chapter III rule it leaves out. The variant puts combat into that society. Agents of the other tribe
can be attacked and killed, and the attacker takes everything the victim holds. Dead agents aren't replaced: the
population lives or dies by births and deaths alone, as in VI-1.

The book defines combat for sugar only (p.83) and never runs it with credit, so the code bars both
(`julia/src/config.jl`: "combat is defined for sugar only (p.83); not with spice"; "credit needs each agent's income,
which combat movement doesn't record"). Turning combat on in VI-1 means extending rule C to two goods and to credit.
That extension is the substance of this work.

## What the user decided

- A variant of VI-1 with combat on.
- The attacker takes **all** of the victim's wealth.
- **No automatic replacement** of dead agents (VI-1 already has `replacement = false`; it stays off, and
  `replacement_same_tribe` stays off).

## The rule: C with two goods (my calls)

**How much is taken.** With spice on, rule C_α takes min(α, the victim's sugar) sugar **and** min(α, the victim's
spice) spice. The variant uses α = ∞ (the book's C_∞), so the attacker takes all of both: "all the victim's wealth".
With spice off nothing changes. No new config field: α already exists.

**What "wealth" is.** An agent's holdings of sugar plus spice, in units. It is used where the book compares wealth:
- an occupied site is a candidate only if its occupant (of the other tribe) has no more wealth than the attacker;
- a site is vulnerable to retaliation if an agent of another tribe in sight of it has more wealth than the attacker
  would have after taking the site and its occupant's holdings.

With spice off this is the agent's sugar, the book's rule, so every existing combat run is unchanged.

Why not compare welfare: welfare depends on each agent's own metabolisms, so two agents' welfare can't be compared.
Sugar plus spice is the simple common measure. The cost if wrong: an agent rich in one good but starving for the other
counts as strong.

**How a site is valued.** The way the agent's own move values sites in that world, with the victim's loot added to
the site's resources:
- book's world and xl (lattice look): the book's welfare score, as `move!` does with spice, of the site's sugar and
  spice plus the victim's sugar and spice; nearest wins ties, as in rule C;
- xxl (round vision and speed): `net_value` with the agent's `SiteWelfare`, the site's sugar and spice (devalued by
  pollution, as `speed_move!` does) plus the loot, and the travel cost; ties as in `xxl_combat_move!`.

The loot isn't devalued by pollution: it's held goods, not the site's.

**Harvest and income.** The attacker lands, then harvests the site through `harvest!`: sugar and spice into its
holdings and the site's sugar into its income, as in `move!`. Loot is wealth, not income: it isn't counted in
`last_income`. That lets credit work, since credit checks each borrower's income. With spice off and pollution off
(every existing combat experiment), `harvest!` changes nothing a run reads, so the book's combat stays as it is.
This must be shown by the byte-identical test below, not assumed.

**The victim's death.** Through `die!`, as any death: its loans are settled by VI-1's credit rules (`credit_on_death!`)
and, with inheritance off as in VI-1, nothing else passes on. The loot is taken before death, so there is nothing left.
Loans owed *to* the victim are not loot: they follow the credit rules for a dead lender. The kill is recorded in
`m.killed`.

**Tribes.** VI-1 places agents at random and gives them random tags, so tribe is the tag majority, as everywhere.
Culture can turn an agent to the other tribe. There are no tribal blocks.

**Order within a turn.** Combat replaces M, as in Chapter III. The rest of the turn is VI-1's: metabolism, then sex,
culture, trade, credit and disease.

## The experiment (my calls)

- **Id `VI-1-combat`.** Rules `({G1}, {C_∞, S, K, T, L10,10, E})`, 500 steps, 5 seeds, as VI-1.
- **Julia only**, like the `XXL-...` experiments: it has no Python counterpart, so it's defined in Julia, from VI-1's
  config with `combat_alpha = Inf`, rather than in the exported registry.
- **Three worlds**, as the combat stage: the book's 50 × 50 world (VI-1's config), xl (VI-1's xl config with combat),
  and today's xxl (`to_xxl(config, XXL_DEFAULTS)`). Its fingerprint is VI-1's with a line naming the change, so its
  results never pass for VI-1's.
- **Run through the combat study only** (my call). `julia/xxl_combat_study.jl --world book|xl|today --exp VI-1-combat`
  runs it with the combat readings (kills by tribe, contact, wealth). The experiment is a small Julia-side `Experiment`:
  VI-1 with `combat_alpha = Inf` in both `config` and `xl_config`, plus the extra fingerprint line. Only the study looks
  it up. The regular runner, the scorecard and `--exp` matching elsewhere don't need to find it, so the registry lookup
  stays as it is.
- **The combat report isn't extended** (my call). Its bars are built around III-9 to III-14 and aren't asked for here.
- **Readings as they stand** (my call). Home share is already undefined (NaN) without tribal blocks; that is how it's
  marked as not applying. The readings' Gini and largest holding stay sugar only, as their column names say. Adding
  wealth columns would change every combat CSV's header, and changing what they compute only with spice on would
  leave the names wrong. Spice and the society's own wealth measures are in the standard VI-1 CSV. An analysis of the
  variant, if the user asks for one, decides what to read.

## Goals

1. VI-1 with combat runs in the book's world, xl and xxl, with the attacker taking all the victim's sugar and spice and
   no replacement.
2. Combat works with spice and with credit: two goods valued, compared and taken; income recorded.
3. Nothing that ran before changes.

## Non-goals

- **No study run and no analysis.** The user asked for the variant. Running it (and what to look at) is asked
  separately; a short dry run (a few periods per world) checks it works.
- No change to `XXL_DEFAULTS`, to VI-1 itself, or to the scorecard.
- No Python model change.
- No new rule for loans in war (loot from loans, or debts passing to the attacker).

## Anti-goals

- Any existing run changing. Every combat experiment (III-9, III-11, III-12, III-13, III-14) in the book's world, xl and
  xxl, and VI-1 without combat, must give byte-identical CSVs before and after. A test shows it on short runs against
  the current code. Byte-identical means the CSV contents; fingerprint files carry a code hash and change.
- A variant in which no one fights. The dry run must show kills in VI-1-combat in at least one world, or the result goes
  back to the user before anything is called done.

## How it's built (left to the builder, within these)

- Lift the two bars in `config.jl`. Combat with credit is allowed only because the combat move now records income.
  Keep the other combat checks.
- One place defines wealth (sugar + spice with spice on, else sugar), used by both combat moves and both retaliation
  checks.
- The book's `combat_move!` and `xxl_combat_move!` gain the two-good path. The sugar-only path must stay draw for draw
  as it is, which the byte-identical test covers.
- Tests on small hand-built worlds:
  - an attacker takes all of a victim's sugar and spice;
  - a wealthier victim, by sugar + spice, isn't attacked;
  - retaliation counts both goods;
  - site value includes the loot;
  - income is the harvest without the loot;
  - a victim's loans are settled as on any death;
  - no replacement.
- The experiment is defined next to the XXL ones (`julia/src/xxl/experiments.jl`) or in a small file of its own, with a
  test of its config and fingerprint.

## Branch and approvals

Branch `vi1-combat` (worktree `.claude/worktrees/vi1-combat`), from main `e4ec5cc`. Commits on the branch, merging,
pushing and any study run need the user's approval.
