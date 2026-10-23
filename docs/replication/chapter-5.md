# Replication report

2 pass, 0 near, 4 fail, of 6 targets.

| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Seeds | Status |
|---|---|---|---|---|---|---|---|
| V-1 | society rids itself of disease | Anim V-1, p.147 | 0 | 0–0.01 | 0.005618 [0–0.02127] | 10/10 | pass |
| V-1 | no disease left circulating | p.147 | 0 | 0–0.5 | 1 [0–4] | 10/10 | fail |
| V-2 | endemic infection persists (proxy) | Anim V-2, p.150 | — | 0.2–0.8 | 0.009562 [0–0.01791] | 10/10 | fail |
| V-2 | average diseases at start | Anim V-3, p.151 | 3.41 | 2.5–4.5 | 4.378 [3.518–5.728] | 10/10 | pass |
| V-2 | endemic average diseases | Anim V-3, p.151 | 0.86 | 0.6–1.1 | 0.01753 [0–0.03117] | 10/10 | fail |
| V-2 | spread of diseases per agent | Anim V-3, p.151 | 1 | 0.8–1.2 | 0.1695 [0–0.238] | 10/10 | fail |

Run: `python -m replication.report --chapter V --jobs 8` on 2026-10-21 (branch feat/chapter-5). 10 seeds each, 500 periods.
Fast suite 229 passed. Re-run after the final-review fix (E order: transmission, then immune response). Chapter II, III and IV regression runs on this branch: every row identical to their records.
Re-run 2026-10-22 (branch feat/threshold-default) after the default fertility threshold became 0.83 (user decision; see the Chapter III record): every row identical (no Chapter V run uses rule S).
Re-run 2026-10-23 (main) after two reporting decisions (user, 2026-10-23). Near now means within the smaller of half the band's width and a quarter of the nearer bound's magnitude, so V-2's endemic-infection proxy falls from near to fail, which removes the artifact noted below. Every observed value is identical to the previous table.

## Choices

- **Active infections only:** an agent carries a disease until its immune system matches it; it can't catch a disease it's immune to, and passes on only diseases that currently afflict it (p.145). Animation V-3's starting average of 3.41 diseases, when each agent was given 10, fits this reading.
- **Order within E:** an agent passes diseases on first, then its immune system responds (design §Scheduling), so a one-bit disease costs one period of illness and can still spread in it (p.143).
- **Learning:** each period, one bit flip per carried disease on the leftmost closest window (p.144); a disease is cleared the moment it matches, so a one-bit gap costs one period of illness (p.143's example).
- **Fee:** +1 sugar metabolism per active disease ("say, one", p.143), used in metabolism, welfare and MRS so illness changes behavior (p.143).
- **Agents and landscape as in Chapter II** (p.147): 400 immortal agents, vision 1–6, metabolism 1–4, endowment 25–50.

## What matches

- **V-1 (10 diseases, 4 per agent): society rids itself of disease.** The sick share is 0.6% at t=450–500 (book: none). In a few seeds one or more agents keep a disease: 1.0 distinct disease still circulates at t=500 on average, against the band's 0.5.
- **Starting load:** 4.4 active diseases per agent at t=0 (book 3.41; band 2.5–4.5).

## Open discrepancy: V-2's endemic disease is not reproduced

With 25 diseases and 10 per agent the book reports a sustained endemic level: about 0.86 active diseases per agent, spread ≈1.0, and many agents sick in Animation V-2. Ours dies out like V-1. The average falls from 5.7 to 0.5 within 5 periods and to about 0.02 by t=500; the sick share is about 1%. **The report's "near" for the sick-share row is an artifact:** its generic near zone reaches below 0, and a 1% sick share is plainly a fail. (The tighter near rule of 2026-10-23 now reports it as a fail.) In substance V-2 fails all three endemic rows. Each disease is typically only 2–3 bits from its nearest window in a 50-bit immune string, so it is learned within a few periods, faster than it can spread.

Readings tested (3 seeds, 300 periods; book: V-1 clears, V-2 ≈0.86 per agent):

| Reading | V-1 late average | V-2 late average | V-2 population |
|---|---|---|---|
| Current: a matched disease is dropped | 0.01 (clears) | 0.04 | 226 |
| Immune agents stay carriers and keep passing it on (Kehoe's open question 1/2) | 0.94 (doesn't clear) | 2.09 | 11 |
| Cleared one period after the matching flip | 0.19 (doesn't clear) | 0.49 | 89 |
| One flip per period in total (oldest, or a random, infection) | 0.00 | 0.00 | 175–188 |

None reproduces both runs. The book's V-2 frames show a population of roughly 200, so fee deaths can't be what sustains it.

The final review measured and ruled out more (V-2, 3 seeds, 300 periods):
- **Memory corruption is not the bottleneck:** 56% of immune flips break a disease the agent had already coded, so agents become susceptible again constantly.
- **Spread is the bottleneck.** At t=1 there are 194 new infections against ≈2,300 active ones (0.08 per infection per period). With illness lasting ≈2 periods (active diseases start 1–3 bits from a match), each infection passes to only ≈0.17 others. Contact density is faithful: 0.6–0.8 neighbors per agent, against the book's 0.9 in Animation II-5.
- **Also ruled out:** no fee (V-2 0.07); immune receivers relaying a disease once (0.01–0.03); eight neighbors instead of four, or every agent in sight as a contact (0.02 / 0.09). Even ≈3 contacts per agent keeps each infection's spread below 1.
- **Lifelong disease sets:** contracted diseases stay with the agent and only unmatched ones cost and spread (the reading behind p.150's "sum of lengths" remark). This sustains V-2 (2.05) but makes V-1 chronic (0.88, 62% sick) and crashes V-2's population to 13.
- **A book-side oddity:** Animation V-3's first frame reports a spread of 0.62 at mean 3.41. No 10-disease draw gives that (expected 1.2–1.5; ours 1.3), so that frame's statistic may not be "active diseases per agent".

## Candidate C6: every disease to each neighbor (2026-10-23)

README candidate C6, run by [candidates2.py](../../diagnostics/candidates2.py) (5 seeds). A sick agent passes every
active disease to each neighbor, not one chosen at random. This departs from p.145, but spread was the measured
bottleneck.

| Target | Book | Default | C6 |
|---|---|---|---|
| V-1 society rids itself of disease | 0 | 0.006 pass | 0.009 pass |
| V-2 endemic infection persists (sick share, t=300–500) | 0.2–0.8 | 0.011 fail | 0.027 fail |
| V-2 endemic average diseases | 0.86 | 0.020 fail | 0.048 fail |
| V-2 spread of diseases per agent | 1.0 | 0.19 fail | 0.30 fail |

V-1 still clears, but V-2 barely moves. Passing more diseases per contact can't make up for too few contacts: each
agent has 0.6–0.8 neighbors on average, and a disease is learned within about two periods. This fits the earlier
finding that even about three contacts per agent keep each infection's spread below 1.

## Visual comparison

- **V-1 / V-2:** at t=0 nearly every agent is red (sick). Infection lines are short local links. By t=10 most agents are blue (well), and the colonies on the two peaks end healthy, as in Animation V-1. V-2 ends the same way, unlike Animation V-2's persistent sick agents.
