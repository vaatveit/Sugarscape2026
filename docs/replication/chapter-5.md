# Replication report

2 pass, 1 near, 3 fail, of 6 targets.

| Experiment | Target | Source | Book | Band | Observed mean [min–max] | Seeds | Status |
|---|---|---|---|---|---|---|---|
| V-1 | society rids itself of disease | Anim V-1, p.147 | 0 | 0–0.01 | 0.004035 [0–0.01071] | 10/10 | pass |
| V-1 | no disease left circulating | p.147 | 0 | 0–0.5 | 1.2 [0–2] | 10/10 | fail |
| V-2 | endemic infection persists (proxy) | Anim V-2, p.150 | — | 0.2–0.8 | 0.01332 [0.005036–0.02183] | 10/10 | near |
| V-2 | average diseases at start | Anim V-3, p.151 | 3.41 | 2.5–4.5 | 4.378 [3.518–5.728] | 10/10 | pass |
| V-2 | endemic average diseases | Anim V-3, p.151 | 0.86 | 0.6–1.1 | 0.0244 [0.009362–0.03958] | 10/10 | fail |
| V-2 | spread of diseases per agent | Anim V-3, p.151 | 1 | 0.8–1.2 | 0.2088 [0.1337–0.2707] | 10/10 | fail |

Run: `python -m replication.report --chapter V --jobs 8` on 2026-10-21 (branch feat/chapter-5). 10 seeds each, 500 periods.
Fast suite 228 passed. Chapter II, III and IV regression runs on this branch: every row identical to their records.

## Choices

- **Active infections only:** an agent carries a disease until its immune system matches it; it can't catch a disease it's immune to, and passes on only diseases that currently afflict it (p.145). Animation V-3's starting average of 3.41 diseases, when each agent was given 10, fits this reading.
- **Learning:** each period, one bit flip per carried disease on the leftmost closest window (p.144); a disease is cleared the moment it matches, so a one-bit gap costs one period of illness (p.143's example).
- **Fee:** +1 sugar metabolism per active disease ("say, one", p.143), used in metabolism, welfare and MRS so illness changes behavior (p.143).
- **Agents and landscape as in Chapter II** (p.147): 400 immortal agents, vision 1–6, metabolism 1–4, endowment 25–50.

## What matches

- **V-1 (10 diseases, 4 per agent): society rids itself of disease.** The sick share is 0.4% at t=450–500 (book: none). In a few seeds one or two agents keep a disease: 1.2 distinct diseases still circulate at t=500 on average, against the band's 0.5.
- **Starting load:** 4.4 active diseases per agent at t=0 (book 3.41; band 2.5–4.5).

## Open discrepancy: V-2's endemic disease is not reproduced

With 25 diseases and 10 per agent the book reports a sustained endemic level: about 0.86 active diseases per agent, spread ≈1.0, and many agents sick in Animation V-2. Ours dies out like V-1. The average falls from 5.7 to 0.5 within 5 periods and to 0.02 by t=500; the sick share is 1.3%. Each disease is typically only 2–3 bits from its nearest window in a 50-bit immune string, so it is learned within a few periods, faster than it can spread.

Readings tested (3 seeds, 300 periods; book: V-1 clears, V-2 ≈0.86 per agent):

| Reading | V-1 late average | V-2 late average | V-2 population |
|---|---|---|---|
| Current: a matched disease is dropped | 0.01 (clears) | 0.04 | 226 |
| Immune agents stay carriers and keep passing it on (Kehoe's open question 1/2) | 0.94 (doesn't clear) | 2.09 | 11 |
| Cleared one period after the matching flip | 0.19 (doesn't clear) | 0.49 | 89 |
| One flip per period in total (oldest, or a random, infection) | 0.00 | 0.00 | 175–188 |

None reproduces both runs. The book's V-2 frames show a population of roughly 200, so fee deaths can't be what sustains it. Unexplored: the original's disease-length or immune-length details, mutation (zero per fn 15), and how often immune memory is corrupted in practice.

## Visual comparison

- **V-1 / V-2:** at t=0 nearly every agent is red (sick). Infection lines are short local links. By t=10 most agents are blue (well), and the colonies on the two peaks end healthy, as in Animation V-1. V-2 ends the same way, unlike Animation V-2's persistent sick agents.
