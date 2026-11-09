# VI-1 with combat by cultural distance — design

Branch `vi1-distance` (worktree `.claude/worktrees/vi1-distance`), from main `11633d1`, which has VI-1-combat
(`docs/superpowers/specs/2026-11-08-vi1-combat-design.md`). Everything below that isn't the user's is **my call**, marked
as such, for the user to accept or change when approving.

## Intent

VI-1-combat died out in every seed of the book's world and xl and survived in today's xxl only after losing nearly
everyone. Looking into why, the user asked how a tribe is defined. It is the majority of 11 random tags, so at the start
45% of agents are one tag from the other tribe, and two agents of opposite tribes differ in 5.8 tags on average against
5.2 for two of the same tribe. Combat still treats the label as absolute: any agent of the other tribe is an enemy, and no
one of one's own tribe ever is.

The user's view: "part of the problem with the tribe label is that it is binary. people's cultural attributes are rarely
binary; there are shades of gray." So the variant drops the label from combat and makes fighting, and fear, a matter of
degree: the more two agents' cultures differ, the likelier they are to fight.

## What the user decided

- **Fight only over real cultural distance.** "whether one agent fights another should be a weighted random draw.
  probability of a fight is proportional to the number of different cultural tags."
- **The scale.** "p(fight) = 0.5 if all cultural tags are different. p(fight) = 0.5 * (number different tags / total
  tags)."
- **The label doesn't count.** "the label should not count." Two agents of the same tag majority can fight; two of
  opposite majorities that differ in one tag rarely do.
- **Fear by distance.** "agents should be more afraid of other agents the more culturally different they are."
- Asked to write this up after the rule was played back (below).

## The rule: C by distance

Let d(a, b) be the number of tag positions where agents a and b differ (the Hamming distance), L the tag length (11), and
h the **hostility**, 0.5 here. Then

  p(a, b) = h × d(a, b) / L.

Identical agents never fight; agents that differ everywhere fight with probability h.

**Fighting.** When an agent weighs its candidate sites (rule C's move, in place of M), a site held by another agent is a
candidate only if:
- the occupant is no wealthier than the agent (`combat_wealth`, sugar plus spice, as in VI-1-combat), and
- a fight draw comes up: with probability p(agent, occupant).

The tribe test is gone; everything else in the move is VI-1-combat's (site value with the loot, nearest wins ties in the
book's world, `net_value` and the reservoir over ties in xxl, reach within speed, landing through `harvest!`, the victim
killed through `take_loot!`).

**Fear.** A site is vulnerable to retaliation if some agent that can see it (the same look as today: `vulnerable` in the
book's world and xl, `disc_vulnerable` in xxl), other than the agent and the victim, is wealthier than the agent would be
after taking the site, **and** a fear draw for that watcher comes up: with probability p(agent, watcher). The label test
is gone here too.

So an agent fears another exactly as much as that other would want to fight it: the scale is symmetric, though the two
draws are separate events.

**One draw per pair per move** (my call). Within one agent's move, each other agent gets at most one draw: the first time
it comes up, as a possible victim or a possible avenger, a draw decides whether the mover is hostile to it, and that
answer holds for the rest of the move, whichever role it comes up in again (a watcher seen from several candidate sites,
an occupant that is also a watcher of another site). Why: today's retaliation check is called repeatedly for the same
watchers, and lazily (only for a candidate that would replace the best so far); fresh draws at each call would make an
agent fear someone at one site and not at the next in the same instant, and would tie the result to the check order.
With one draw per pair, the agent forms one view of each agent it meets this turn. The next move draws afresh. An agent
can't be both a possible victim and a feared watcher in one move (a victim is no wealthier than the attacker, a feared
watcher is wealthier than the attacker after the gain), so in practice the cache ties together the answers for one
watcher seen from several sites. Cost if wrong: an agent's fear of a given watcher is one event per move, not one per
site.

**Draws come from the model's generator** (`m.rng`), so runs are reproducible from the seed. The lazy order of today's
checks stays; it changes which draws are made, not what they mean.

**Off by default.** A new config value, `combat_hostility` (my call for the name), default 0 meaning off: combat uses the
tribe label exactly as now. With it set above 0 (at most 1, so p stays a probability), the rule above replaces the label
test in both combat moves and both retaliation checks. It needs tags (`tag_length > 0`) and combat (`combat_alpha`).
Julia only; Python's model is unchanged.

## The experiment (my calls)

- **Id `VI-1-distance`.** VI-1-combat with `combat_hostility = 0.5`: VI-1's rules with C_∞ in place of M, the attacker
  takes all sugar and spice, no replacement, 500 steps. Defined in Julia next to VI-1-combat (`julia/src/xxl/vi1_combat.jl`
  or a sibling file), with a fingerprint line naming the change so its results never pass for VI-1-combat's.
- **Three worlds,** as VI-1-combat: the book's 50 × 50 world, xl and today's xxl, run through the combat study
  (`julia/xxl_combat_study.jl --world book|xl|today --exp VI-1-distance`), which accepts the id as it accepts VI-1-combat.
- **VI-1-combat stays as it is,** so the two can be compared seed for seed.

## Readings (my calls)

The combat readings stay as they are and still sort agents into blue and red by tag majority, only to look at the result;
the rule never sees the label. Their columns don't change (changing them would change every combat CSV's header).

Added, written only for runs with the distance rule on: a per-kill file next to each seed's combat CSV
(`seed<N>-kills.csv`), one row per kill: `t`, `distance` (killer–victim tags that differ, 0–L), `same_label` (1 if the two
had the same tag majority). The kill is recorded where it happens (`take_loot!`), so both moves feed it. From it: how
culturally far apart killers and victims are, and the share of kills within a label, period by period. Recording it must
draw nothing and change nothing in the run.

Settled after the builder check (my calls):
- A kill's `t` is the period whose combat CSV row counts that death, so the two files join on `t`.
- A seed with no kills still gets the file, header only.
- The kills file is written with the seed's combat CSV; the study's check that a seed is complete stays as it is (the
  combat CSV's row count).
- The fight draw is made only for an occupant that passes the wealth test (fewer draws; the odds are the same).
- The dry run (a few periods, two seeds per world, as for VI-1-combat) is part of building and checking, not a study run.

## Goals

1. A variant of VI-1-combat in which whether to fight, and whom to fear, is a weighted draw on cultural distance,
   p = 0.5 × d / L, with no part played by the tribe label.
2. It runs in the book's world, xl and today's xxl through the combat study, with the per-kill readings.
3. Nothing that ran before changes.

## Non-goals

- No study run and no analysis. Running VI-1-distance (and what to compare) is asked separately (runs need the user's go-ahead); a
  short dry run checks that it works and that there are kills.
- No change to VI-1-combat, VI-1, the book's combat experiments, `XXL_DEFAULTS` or the scorecard.
- No change to culture (rule K), to the readings' existing columns, or to anything else that uses the tribe label
  (tribal blocks, same-tribe replacement, the readings).
- No other hostility shapes (thresholds, non-linear curves). h is a config value, so another scale is a config change
  later, not now.
- No Python model change.

## Anti-goals

- Any existing run changing. With `combat_hostility = 0`, every combat experiment (III-9, III-11, III-12, III-13, III-14),
  VI-1 and VI-1-combat, in the book's world, xl and xxl, give byte-identical CSVs. The guard fixtures from VI-1-combat
  (`julia/test/fixtures/vi1-combat-refs/`) cover all but VI-1-combat; add VI-1-combat to them, from the current code,
  before any rule change.
- The label sneaking back in: no tribe test anywhere in the distance path.
- A variant with no fights. The dry run must show kills in at least one world, or the result goes back to the user before
  anything is called done.

## How it's built (left to the builder, within these)

- One function gives p for a pair (from the two tag strings, L and h); one place holds the move's per-pair answers, emptied
  at the start of each move, used by both combat moves and both retaliation checks.
- Tests on small hand-built worlds, with the generator seeded or the hostility set to make the draw certain:
  - p is 0 for identical tags, h for tags that differ everywhere, h × d / L between;
  - two agents of the same label but far apart can fight; with p = 0 (identical tags) an occupant is never a candidate;
  - a richer watcher with identical tags is never feared; a richer watcher at full distance with h = 1 always is;
  - one draw per pair per move: an agent met twice in one move gets the same answer;
  - the per-kill file has one row per kill with the right distance and label;
  - with `combat_hostility = 0` the move is draw for draw today's (the byte-identical guard).
- Config checks: `combat_hostility` in [0, 1]; above 0 it needs tags and combat.

## Branch and approvals

Branch `vi1-distance`, worktree `.claude/worktrees/vi1-distance`, from main `11633d1`. Commits on the branch, merging,
pushing and any study run need the user's approval.
