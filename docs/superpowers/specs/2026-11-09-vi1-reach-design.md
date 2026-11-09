# VI-1-distance with combat and culture at the same reach — design

Branch `vi1-reach` (worktree `.claude/worktrees/vi1-reach`), from main `1372321`, which has VI-1-distance
(`docs/superpowers/specs/2026-11-09-vi1-distance-design.md`). Everything below that isn't the user's is **my call**,
marked as such, for the user to accept or change when approving.

## Intent

In VI-1-distance, combat and culture reach very different distances:

| World | Combat (attack, fear, movement) | Culture (rule K: whose tags an agent changes) |
|---|---|---|
| Book's | the 4 lattice lines out to vision (1–5) | the 4 adjacent sites |
| xl | the 4 lattice lines out to vision (10–50), every 10th site (`look_stride` 10) | the 4 adjacent sites |
| Today's xxl | sight: the round look out to vision; attack only within speed (1–6); fear: the look of vision from the candidate site | the sites within 1.5 (`interaction_radius`) |

So killing reaches far and assimilation only next door. The user: "Right now the reach for combat is different than the
reach for assimilation. They should be the same. test making the reach for both the same as that currently for combat,
and test making the reach for both the same as that currently for assimilation."

## What the user decided

- Two directions, both tested: both at combat's current reach, and both at culture's current reach.
- When combat takes culture's reach, **all three** parts of combat's reach change: whom an agent can attack, whom it
  fears, and where it can move ("all 3").
- In today's xxl, where combat sees within vision but attacks only within speed, culture at combat's reach is tested
  **both** ways: within vision and within speed ("test both").

## The variants

All three are VI-1-distance (C_∞ by cultural distance, h = 0.5, all sugar and spice taken, no replacement, 500 steps)
with one change of reach. VI-1-distance stays as it is, for comparison.

**VI-1-near: combat at culture's reach.** Attack, fear and movement reach only the culture neighbourhood.
- Book's world and xl: an agent's candidate sites are its own site and the 4 adjacent sites, whatever its vision and
  `look_stride`. A site is vulnerable if a watcher on one of the 4 sites adjacent to it passes the fear test.
- Today's xxl: candidates are its own site and the sites within `interaction_radius` (1.5): 8 sites. Any occupied one can
  be attacked, whatever the agent's speed (my call: speed 1 would otherwise rule out the diagonals, which culture
  reaches). Moving there is a jump, as an attack within reach is now. Remembered sites beyond the radius are not
  candidates (my call: they are beyond reach). A site is vulnerable if a watcher within 1.5 of it passes the fear test.
- **The agent still looks as far as now** (my call). In today's xxl it still looks out to vision, remembers what it saw
  and passes it on by word of mouth; only the candidates are cut to the sites within 1.5. "Where it can move" limits the
  move, not what the agent knows: shrinking the look would also switch off memory and word of mouth, a second change the
  user didn't ask for. In the book's world and xl, which have no memory, the 4 adjacent sites are scanned directly (xl's
  `look_stride` would otherwise skip distance 1).
- Nothing else about the move changes: site value, ties, the wealth tests, the distance draw, the per-move hostility
  answers (`m.hostile`).

**VI-1-far: culture at combat's sight.** In rule K, an agent changes one random tag of every agent it would see in its
combat move, not just its neighbours.
- Book's world and xl: the agents on the sites of the lattice look from its position: the 4 lines out to its vision, with
  xl's `look_stride` draws, as `combat_move!` scans them.
- Today's xxl: the agents on the sites of `look!` from its position, without memory (`memory=false`): every site within
  its speed, plus the sampled ring out to vision.
- In xl the look samples every 10th site along each line, so an adjacent agent is reached only about 1 time in 10, as
  combat sees it; that is combat's reach, kept as it is.
- The look for culture is drawn afresh in rule K (my call: the agent may have moved, and the move's look is gone by
  then). Everything else in rule K is as now: the order is shuffled, one random tag position per agent reached, copied if
  they differ.

**VI-1-far-speed: culture at combat's attack reach.** Today's xxl only: rule K reaches every agent within the agent's
speed (`near_offsets` of its speed). At speed 1 that is the 4 adjacent sites, fewer than today's 8 within 1.5: it is
combat's attack reach, kept as it is. In the book's world and xl there is no speed and the attack reach is the sight, so
VI-1-far already covers them (my call: no duplicate runs).

## What stays the same (my calls)

- Trade, credit, disease, mating and the networks of friends keep their current neighbourhoods. Only combat's reach (in
  VI-1-near) or culture's (in VI-1-far, VI-1-far-speed) changes.
- **The readings stay comparable.** The combat readings' mixing and front use the current culture neighbourhood (the 4
  adjacent sites, or 1.5 in xxl) in every variant, so "mixing" means the same in all runs. The builder must check how
  `culture_neighbors!` is shared between rule K and the readings and keep the readings on the current neighbourhood.
- The kills file and every existing reading, as in VI-1-distance.

## How it's switched on (my calls, names left to the builder within these)

Two config values, both defaulting to today's behaviour:
- `combat_reach`: `"vision"` (as now) or `"neighbours"` (VI-1-near).
- `culture_reach`: `"neighbours"` (as now), `"sight"` (VI-1-far) or `"attack"` (VI-1-far-speed; refused without xxl
  speed).

They need combat (`combat_reach`) and culture (`culture_reach`) respectively. Julia only.

## The experiments

`VI-1-near`, `VI-1-far` and `VI-1-far-speed`, defined next to VI-1-distance, each with a fingerprint line naming its
change, run through the combat study (`--exp`), which accepts them as it accepts VI-1-distance. VI-1-far-speed is refused
in the book's world and xl. Runs (my call, after the user's go-ahead): seeds 0–19, 500 periods; VI-1-near and VI-1-far in
all three worlds, VI-1-far-speed in today's xxl: 7 sets of 20 seeds.

## Goals

1. Combat and culture at one reach, in both directions, as above.
2. The three experiments run in their worlds through the combat study, with the kills file.
3. Nothing that ran before changes.

## Non-goals

- No study run and no analysis until asked; a short dry run checks each variant works and how long it takes.
- No change to VI-1-distance, VI-1-combat, VI-1, the book's combat experiments, `XXL_DEFAULTS`, the scorecard, or the
  reach of any rule other than combat and culture.
- No Python model change.

## Anti-goals

- Any existing run changing. With both values at their defaults, every experiment the guard fixtures cover (III-9,
  III-11, III-12, III-13, III-14, VI-1 and VI-1-combat, in all three worlds) gives byte-identical CSVs; add VI-1-distance
  to the fixtures, from the current code, before any change.
- A "same reach" that isn't: in each variant a test shows the two rules reach the same agents on a small hand-built
  world.
- A variant too slow to run: if the dry run puts any 20-seed set over about 2 hours at the usual 5 workers (`--jobs 5`),
  it goes back to the user before the runs.

## How it's built (left to the builder, within these)

- Tests on small hand-built worlds:
  - VI-1-near: an occupant two sites away (in reach of vision) is not attacked; an adjacent one can be; a richer watcher
    two sites from the candidate isn't feared, an adjacent one can be; the agent never moves more than one site (book,
    xl) or 1.5 (xxl).
  - VI-1-far: an agent changes a tag of an agent several sites away along a line within its vision (book) and within its
    look (xxl), and not of one outside it.
  - VI-1-far-speed: within speed yes, beyond speed no; refused without speed.
  - The readings' mixing is the same function of the population in every variant (counts pairs in the current culture
    neighbourhood).
  - Config checks, and byte-identical old runs.
