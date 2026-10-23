# Growing Artificial Societies — Implementation Notes

Source: Epstein & Axtell, *Growing Artificial Societies* (MIT/Brookings, 1996).
Page numbers are the book's printed page numbers. These notes record rules,
parameters, and the quantitative results we must reproduce.

Rule-system notation: `({environment rules}, {agent rules})`, e.g. `({G1}, {M, S})`.

---

## Chapter II — Life and Death on the Sugarscape

### Sugarscape (pp. 21–22), Fig II-1
- 50×50 lattice (2500 sites), each site has sugar level and capacity; level starts at
  capacity. Peaks in NE and SW quadrants, falling off in terraces; capacities from
  max **4** at the peaks to 0 at the periphery.
- **Torus**: wraps left↔right and top↔bottom.
- Exact capacity map is not given numerically in the text (only the figure). The
  standard "sugar-map.txt" from the original/CD-ROM is the usual source.

### Growback rule G_α (p. 23)
- At each site, sugar grows back α units per time step up to capacity:
  r(t+1) = min(r(t) + α, c).
- **G_∞** (p. 26): grow back to full capacity immediately.

### Agent states (pp. 23–24)
- Location (x, y); no two agents on one site.
- Genetic: sugar metabolism and vision, fixed for life.
- Initial population: **400 agents** at random positions (Fig II-2).
- Metabolism U{1..4} (for the first runs); vision U{1..6} "unless stated otherwise".
- Vision v: sees v units in the four principal directions (N, S, E, W); no diagonals.
- Initial sugar endowment; gathered-but-not-eaten sugar accumulates, no cap, no decay.

### Movement rule M (p. 25)
- Look out as far as vision permits in the four principal lattice directions and
  identify the unoccupied site(s) having the most sugar;
- If the greatest sugar value appears on multiple sites, select the nearest one;
- Move to this site; collect all the sugar at this new position.
- fn 8: the **order in which the agent searches the four directions is random**.
- fn 9: ties at equal distance → the first site encountered (search order random).
- fn 10: move distance = vision (can move up to v sites in one direction).
- Wealth += collected; wealth −= metabolism. If wealth ≤ 0 → agent starves, removed.
  If it doesn't starve it lives forever (in base runs).
- The agent's current site counts as a candidate at distance 0 and wins ties: p.28 explains II-1's
  agents staying on a ridge because "no point on the level 3 sugar terrace is an improvement".
  (Excluding it reproduces Animation II-5's 0.9 neighbors but leaves 98% of II-1's agents moving.)

### Scheduling (p. 26)
- Each agent moves once per period; **agent order randomized each period**.
- Serial execution: one agent active at a time (fn 12).
- Rule notation (E, A): environment rules, agent rules. Appendix B summarizes all rules.

### First run ({G_∞},{M}) — Animation II-1 (pp. 26–28)
- 400 random agents. Agents "stick" to terrace ridges (limited vision + instant
  growback → no improvement visible). High-metabolism/low-vision agents die; reaches a
  static steady state.
- fn 16: runs are reproducible given RNG seed; search direction in M is stochastic.

### Second run ({G1},{M}) — Animation II-2, Fig II-4 (pp. 28–31)
- 400 random agents, growback 1 unit/period. Two colonies form, one per mountain;
  continuous "hiving"; efficient grazing.
- **Carrying capacity ≈ 224** (population 400 → ~250 by t≈60, asymptote ~224 by t=500).
- Fig II-5: carrying capacity vs initial mean vision, by mean metabolism ⟨m⟩, starting
  with **500 agents**, each point mean of 10 runs:
  - ⟨m⟩=1: ~450 (v≈1), ~465 (2), ~475 (3), ~490 (5.5), ~495 (10.5)
  - ⟨m⟩=2: ~330 (1), ~365 (2), ~375 (3), ~390 (5.5), ~400 (10.5)
  - ⟨m⟩=3: ~225 (1), ~228 (2), ~255 (3), ~260 (4.5), ~260 (5.5), ~287 (6.5), ~280 (8), ~287 (10.5)
- **Selection without sex** (p. 32): in Animation II-2's run, initial mean vision 3.5 and
  metabolism 2.5 → after 500 periods mean vision **4.1**, metabolism **1.8**.

### Finite lives & replacement (p. 32–33)
- Each agent gets a maximum age drawn from [a, b]; still can starve.
- **R[a,b]:** When an agent dies it is replaced by an agent of age 0 having random
  genetic attributes, random position on the sugarscape, random initial endowment,
  and a maximum age randomly selected from [a,b]. (Keeps population constant.)

### Wealth distribution ({G1},{M,R[60,100]}) — Animation II-3 (p. 33–34)
- **250 agents** (≈ carrying capacity) placed randomly; R[60,100]; G1.
- Initial endowments **U[5,25]**. (Metabolism/vision as before: m U{1..4}, v U{1..6}.)
- fn 19: mean death age ≈ 80 when few starve.
- Histogram (10 bins) goes from roughly symmetric to highly skewed. Frames:
  1) bins of 3 up to 30: 0,12,33,31,37,30,39,39,22,7
  2) bins of 11 up to 110: 40,66,30,38,27,17,20,8,2,2
  3) bins of 20 up to 200: 81,50,39,25,24,15,10,3,2,1
  4) bins of 27 up to 270: 122,37,28,25,18,7,9,2,0,2
- fn 20: wealthy agents typically have high vision, low metabolism, born high, long-lived.
- fn 21: income (harvest − metabolism) much less skewed; max income 3.

### Gini / Lorenz (pp. 36–38) — Animation II-4 (same run)
- Lorenz: rank agents poorest→richest; ordinate = cumulative wealth.
- Gini sequence: **0.230 → 0.308 → 0.403 → 0.500 → 0.513 → 0.503**; ≈0.50 long-run.

### Neighbor networks (pp. 37–41) — Animation II-5 ({G1},{M})
- Von Neumann neighborhood (N, S, E, W) used throughout; Moore = + 4 diagonals
  (software can switch).
- After moving, each agent records its 0–4 von Neumann neighbors (post-move) and
  keeps that list until it next moves. Network = directed edges agent → listed
  neighbors, redrawn after each full cycle. Edges can be asymmetric and can span
  beyond the neighborhood if a listed neighbor moves later in the same cycle (fn 29).
- Network stats: average neighbors **0.9**, std dev ~0.8–0.9.

### Migration waves (pp. 42–44) — Animation II-6 ({G1},{M})
- Max vision **10** (vision U{1..10}); otherwise as in Animation II-2 (400 agents,
  m U{1..4}). Agents start in a **dense block** in the SW (approximately the lower-left
  ~20×20 region, covering the SW peak area — per figure frame 1).
- Result: succession of coherent waves moving **diagonally NE** toward the NE peak,
  though individuals move only N/S/E/W (interweaving, Fig II-8).

### Seasonal growback S_αβγ (p. 44)
- Equator splits the grid into top and bottom halves. Initially summer in the top half
  and winter in the bottom. Every γ periods seasons flip.
- Summer: grow back α units per period; winter: α units per β periods.
- fn 33: for top-half sites, season is summer if (t mod 2γ)/γ < 1, else winter
  (bottom half the reverse).
- Example in text: unit rate in summer, one-eighth rate in winter, flip every 50
  periods → S_1,8,50.
- **Animation II-7 ({S_1,8,50},{M})**, random initial distribution (400 agents):
  high-vision agents migrate with the seasons; low-vision/low-metabolism agents
  "hibernate"; low-vision/high-metabolism agents die.

### Pollution P_αβ (p. 47)
- Gathering sugar s → production pollution αs; metabolizing m → consumption
  pollution βm. Accumulates on the site where it occurs: p(t) = p(t−1) + αs + βm.
- Modified M: choose unoccupied site maximizing **sugar/(1 + pollution)** (fn 37);
  ties → nearest; move; collect all sugar.
- fn 36: general multi-pollutant rule in Appendix B (not provided).

### Diffusion D_α (p. 48)
- Every α periods, at each site compute flux = average pollution over its von Neumann
  neighbors; each site's flux becomes its new pollution level. D1 fastest.
- fn 38 alternative growback: zero-sugar sites regrow only if a neighbor is nonzero.

### Polluted run — Animation II-8 ({G1, D1},{M, P11}) (pp. 48–50)
- G1 throughout; pollution P_1,1 turned on at **t = 50**; diffusion D1 on at **t = 100**.
- Agents abandon polluted peaks, migrate to the hinterland, many starve (lower carrying
  capacity); after diffusion, they return to high-sugar regions; pollution rises
  everywhere ("red tide").

---

## Chapter III — Sex, Culture, and Conflict

Twin-peaked sugarscape, G1, movement M throughout.

### Fertility (p. 55)
- Must be of childbearing age.
- Newborn's endowment = **half of father's initial endowment + half of mother's
  initial endowment**. First generation gets random initial endowments (fn 2).
- To be a parent an agent must currently have **at least the amount of sugar it was
  endowed with at birth**. (Chapter IV credit lets agents borrow for this.)
  **Our default departs from this (user decision, 2026-10-22):** 0.83 of the birth endowment, fitted to
  Fig III-1's steady population; p.55's rule runs as the VAR-book experiments.

### Sex rule S (p. 56)
- Select a neighboring agent at random;
- If the neighbor is fertile and of the opposite sex and at least one of the two
  agents has an empty neighboring site (for the baby), a child is born;
- Repeat for all neighbors.
- An agent can mate with each of up to 4 neighbors in its turn (multiple births per
  period allowed, fn 3; no incest prohibition; no one-baby-per-female limit).
- Baby follows M from birth. Sex random 50/50.
- Genetics (metabolism, vision, maximum age, ...) Mendelian: each attribute taken
  from one parent or the other with equal probability (Table III-1).

### Default S parameters — Fig III-1 ({G1},{M,S}) (p. 57)
- **Founders' ages (decided 2026-10-22, user):** U[0, max age) when lives are finite. Animation III-1's
  first frame shows 417 agents spread over all ages (63, 49, 45, 64, 45, 55, 49, 30, 13, 4 per decade),
  Fig III-1 starts near 417, VI-2 has births at t≈1–3, and Ascape uses randomInRange(0, deathAge).
  Newborns and replacements start at 0.
Each period = one "year". Per-agent values random in the stated ranges (fn 4):
- Childbearing begins between ages **12 and 15** (both sexes);
- Women's childbearing ends between **40 and 50**; men's between **50 and 60**;
- Natural death age between **60 and 100** (both sexes);
- Initial population endowments **50 to 100** sugar.
- Vision U{1..6}, metabolism U{1..4} (p. 58, 61). Initial population size not stated
  in the text; Animation III-2 frame 1 looks like ~400 random agents.
- Result: population roughly constant ~450–550 over 2500 periods, quasi-oscillations
  <10% (initial bump to ~575 near t≈100, dip ~400 at t≈150).
- Animation III-1 age histograms (10-year bins 0–100) approximately stationary, e.g.
  63,49,45,64,45,55,49,30,13,4 → 52,70,71,63,67,64,65,47,13,6.
- Animations III-2/III-3: agents fill a NE–SW diagonal band connecting the peaks.
  They show one run (same frames, two colorings), the source of Fig III-2 (p.61), and not Fig III-1's:
  agents counted per frame 384, 172 (all on the peaks), 325, 876, 669, 1,019 (counted 2026-10-22).
  Vision colored blue (1–3)/red (4–6); metabolism blue/red below/above initial mean.
  Selection favors high vision and low metabolism; metabolism falls faster than
  vision rises; vision rise not strictly monotone.

### Evolution under ({G1}, {M, S}) — Fig III-2 (p. 63)
- Mean vision rises from ~3.5 at t=0 to ~5.3 by t≈900 (still rising slowly).
- Mean metabolism falls from ~2.6 to ~1.0 by t≈300, then flat at ~1.0.
- Fitness is emergent ("sustainable coevolution with one's environment").

### Regimes of population dynamics (pp. 64–67)
Baseline (Fig III-1, constant population) uses rule S with default parameters (see p. 55–57, TBD).
- **Fig III-3, small oscillations:** S with fertility ending 10 years earlier:
  women childbearing ends between ages 30 and 40; men between 40 and 50.
  Population oscillates ~250–500 (never below ~250), period ~200 years, over 2500 steps.
  Read from the plot (2026-10-22): starts ≈405, rises to ≈450 by t≈50, dips to ≈250 at t≈190; then
  peaks ≈415–465 at t≈340, 548, 754, 960, 1175, 1405, 1627, 1833, 2151, 2397 (≈225 apart),
  troughs ≈240–330, mean ≈365.
  Footnote 10: ~12,500 agents inhabit the sugarscape over the 2500 periods.
  Average agent lifetime ≈ 80 years (so no agent lives through a full swing).
- **Fig III-4, large oscillations:** restore default infertility ages, but reduce the
  sugar necessary for reproduction (initial-endowment range) to **10 to 40**.
  (MASON reads this as a flat fertility threshold, 25 for III-4 and 10 for III-5, with
  endowments kept at 50–100; probed 2026-10-22 as a 10–40 threshold, not adopted.)
  Amplitude starts >1000 (≈350 to ≈1600), diminishing to ~800; period ≈125 years.
  Digitized (2026-10-22): ≈415 at t=0; peaks ≈1540–1560 at t≈73, 216, 352, 489, 622, 754, 884,
  1010, 1139, 1264, 1389, 1513 (period 143 shortening to 124); troughs 379, 409, 435, 469, 498, 520,
  572, 532, 537, 581, 589 (rising). Inverting the curve with old-age deaths only needs at most ≈70
  starvations per crash: the swings are a demographic echo, not starvation crashes.
- **Fig III-5, extinction:** both changes combined → three growth surges
  (peaks ~1250, ~1450, ~1400) then extinction around t≈550.
- Fig III-6 summarizes: axes infertility age (vertical) × endowment (horizontal).

### Inheritance rule I (p. 67)
- **I:** When an agent dies its wealth is equally divided among all its living children.
- Fig III-7 ({G1},{M,S,I}): vision rises less (to ~4.3 plateau vs ~5.3 without I);
  metabolism falls more slowly but both curves end at ~1.0–1.1.
  "Inheritance retards selection."
- Gini rises: reaches **0.743**. Animation III-4 Gini sequence:
  0.039, 0.199, 0.296, 0.299, 0.408, 0.499, 0.598, 0.700.
- (Footnote 12: software also allows division among sons, daughters, or friends.)

### Genealogical networks (pp. 68–71) — Animation III-5 ({G1},{M,S})
- Line drawn from every parent to each child. Initial population black;
  parent red; child green; both parent and child yellow.
- Network stats shown: average fertility & std dev (e.g. 0→0.4→1.5→1.6→1.4→1.5).

### Cultural tags (p. 72)
- Each agent has a binary tag string; same length for all agents
  (software parameter; tried 1–1000). Standard runs use **length 11**.

### Cultural transmission rule (tag-flipping) (p. 73)
- For each (von Neumann) neighbor, a tag position is randomly selected;
- If the neighbor agrees with the agent at that position, no change; if they
  disagree, the neighbor's tag is flipped to agree with the agent's tag.
- (Agent is the flipper, neighbor the flippee. Runs on the agent's turn.)

### Group membership rule (tag majority) (p. 73)
- Blue if 0s outnumber 1s; Red otherwise. Tag length must be odd.
- **K** = tag-flipping + tag-majority together.
- Footnote 45 (Ch IV): f = fraction of 0s; f > 1/2 → Blue, f < 1/2 → Red.

### Cultural dynamics run (p. 74) — Animation III-6, Fig III-8, ({G1},{M,K})
- Random genetics, random tags (length 11), random initial positions,
  growback at unit rate, movement M, **sex off**.
- Typical run: all agents Blue after ~2700 periods. Each spatially segregated
  subpopulation converges to pure Blue or pure Red (absorbing state).
- Fig III-8: fraction Blue wanders 0.4–0.95 before locking at 1.0 by ~t=2700.
- Animation III-7: per-position % of zeros; positions lock in at 0 or 100.
- Longer tag strings / more agents → longer convergence.

### Vertical transmission (pp. 78–79), Table III-2
- At each tag position: if parents agree, child gets that tag; else fair coin.

### Networks of friends (pp. 79–80) — Animation III-8 ({G1},{M,K})
- Hamming distance measures cultural closeness.
- Each agent remembers the **five** agents it has encountered (as neighbors)
  who are nearest culturally. When it encounters a new neighbor closer than any
  of its five friends, the neighbor displaces one.
- Once stored, friends are never re-evaluated (list can become anachronistic).
- Network stats: "average closeness of best friends" / "of all friends"
  rising 0.52 → 0.91 / 0.52 → 0.89 (closeness ≈ fraction of matching tags).
- Friendship has no effect on behavior.

### Combat rule C_α (p. 83)
- Look out as far as vision permits in the four principal lattice directions;
- Throw out all sites occupied by members of the agent's own tribe;
- Throw out all sites occupied by members of different tribes who are wealthier than the agent;
- Reward of each remaining site = resource level at the site plus, if occupied,
  min(α, occupant's wealth);
- Throw out all sites that are vulnerable to retaliation;
- Select the nearest position having maximum reward and go there;
- Gather the resources at the site plus min(α, occupant's wealth) if occupied;
- If occupied, former occupant is "killed" — permanently removed.
- **Retaliation** (p. 82): attack site is invulnerable iff no other agent of the
  victim's tribe within the attacker's vision (from the attack site) is bigger
  than the attacker will be after the attack (wealth + reward).
- C_∞ means the aggressor receives the full accumulation of the victim.

### Combat results (pp. 83–92)
- **C_∞** ({G1},{C_∞}), infinite lifetimes: outcomes are Blue eradicates Red,
  Red eradicates Blue, or small colonies (as small as one agent) of each coexist on
  their own peak; tribes usually switch mountains. Animation III-9 (Blue takeover),
  III-10 (coexistence; small cluster of low-vision Blues in SW lowlands).
  Initial condition: dense square blocks — Blue block in SW corner, Red block in NE.
- **C_2 + R[60,100]**, population fixed at 400 (dead agent replaced by random agent
  of the **same tribe**): coherent battle fronts, "war of attrition"/"trench war"
  (Animation III-11).
- Animation III-12 ({G1},{M}), combat off: Blue block SW and Red block NE (max vision 10)
  propagate as diagonal waves that collide and interpenetrate.
- Animation III-13 ({G1},{C_2}): combat eliminates the waves.
- Animation III-14 ({G1},{C_∞, K}): with tag-flipping, invaders get assimilated;
  no runaway hegemony.

### Proto-history (p. 92) — Animation III-15 ({G1},{M,S,K})
- Small low-density random "soup" (random genetics, tags, positions) on the
  twin-peaked sugarscape → migration to peaks → each converges to pure Red or Blue
  → growth forces tribes into the lowlands → perpetual interaction.
- Footnote 32: Red and Blue on opposite mountains in somewhat less than 1/2 of runs;
  Red dominates both in ~1/4; Blue in ~1/4; extinction on one or both mountains
  with small frequency.

---

## Chapter IV — Sugar and Spice: Trade

### Landscape (p. 96), Fig IV-1
- Sugar mountains NE and SW (as before); **spice** mountains NW and SE.
- Each site has sugar level/capacity and spice level/capacity.
- Agents keep sugar and spice accumulations and have two metabolisms.
- Agent dies if **either** accumulation falls to zero.

### Welfare function (p. 97), eq. (1)
- W(w1, w2) = w1^(m1/mT) · w2^(m2/mT), with mT = m1 + m2 (Cobb-Douglas).
- τ1 = w1/m1, τ2 = w2/m2 are times to starvation.

### Multicommodity movement rule M (pp. 98–99), eq. (2)
- Look out as far as vision permits in each of the four lattice directions;
- Considering only unoccupied positions, find the nearest position producing
  maximum welfare, evaluating W(w1 + x1^s, w2 + x2^s) at each site s;
- Ties of equal welfare: "first site encountered" / nearest;
- Move there and collect all the resources at that location.
- (Footnote 6: one-commodity case is W(w; m) = w^m.)
- Animation IV-1: vision U[1,10], each metabolism U[1,5]; observational agent trail.

### MRS (p. 102), eq. (3)
- MRS = (w2/m2) / (w1/m1) = τ2/τ1.
- MRS_A > MRS_B → A buys sugar, sells spice; B buys spice, sells sugar (Table IV-1).

### Bargaining (p. 104), eq. (4)
- p = sqrt(MRS_A · MRS_B) (geometric mean). Statistics use π = ln(p).
- If p > 1: p units of spice exchanged for 1 unit of sugar.
  If p < 1: 1 unit of spice exchanged for 1/p units of sugar.
- (Footnote 15: random price in [MRS_A, MRS_B] gives qualitatively same results.)

### Agent trade rule T (p. 105)
- Agent and neighbor compute their MRSs; if equal, end, else continue;
- Spice flows from the agent with the higher MRS to the agent with the lower MRS;
  sugar goes the opposite way;
- Price p = geometric mean of the two MRSs;
- Quantities: if p > 1, p spice for 1 sugar; if p < 1, 1/p sugar for 1 spice;
- If the trade (a) makes both agents better off (welfare increases for both), and
  (b) does not cause their MRSs to cross over, the trade is made and return to start;
  else end. (Footnote 17: stop if one more trade would flip MRS_A >(<) MRS_B.)
- Example Fig IV-2: A endowment (5, 8), B (15, 2).
- **Who trades (p. 107):** after an agent moves, it interacts via T exactly once
  with each of its 0–4 von Neumann neighbors, selected in random order.
  (Footnote 23 variant: arbitrageur re-trading — not the default.)

### Neoclassical market run (p. 108) — Figs IV-3, IV-4, IV-5, ({G1},{M,T})
- 200 infinitely lived agents placed randomly; rules M and T.
- Sugar and spice metabolisms each U[1,5]; vision U[1,5];
  initial endowments U[25,50] for both sugar and spice.
- Results: mean trade price (geometric mean of the period's trade prices)
  converges toward ~1.0 (scatter 0.7–1.5 early, tight by t≈600).
- ~150,000 trades over 1000 periods; per-period volume ~50–200 (spikes to ~300),
  approximately lognormal.
- Std dev of ln(price) per period: starts ~0.8–1.0, falls to ~0.05 by t=1000.

### Carrying capacity with/without trade — Fig IV-6 ({G1},{M,T})
- Carrying capacity vs mean vision (approx. read from plot):
  - With trade: ~100 (v≈1), ~128 (2), ~158 (3), ~173 (6), ~185 (10).
  - No trade:   ~82 (1),  ~90 (2), ~120 (3), ~157 (6), ~177 (10).

### Price variance experiments
- Vision = 1 for all (Figs IV-7, IV-8): mean price ≈1.0 over ~100,000 trades,
  wide scatter 0.6–1.6; std dev ln(price) ~0.6 early trending to ~0.3.
- Vision U[1,15] (Fig IV-9): std dev decays fast to ~0.03.
- **R[60,100]**, vision U[1,5] (Fig IV-10): std dev stays ~0.5 (0.4–0.6).
- **R[960,1000]** (caption; text says 980–1020) (Fig IV-11): std dev falls to ~0.15.
- Fig IV-12: long-run std dev vs average agent age: peaks ~0.5 at short life,
  ~0.3 at age ~300, ~0.2 at ~550, ~0.15 at ~1000.
- **Gini vs trade** (Fig IV-13, R[60,100]) vs mean vision:
  Trade ≈ 0.41, 0.42, 0.44, 0.37, 0.38 at vision ~1.5, 3.5, 5, 10, 15;
  No trade ≈ 0.43, 0.39, 0.34, 0.33, 0.31. Trade increases inequality.
- **With S** (Fig IV-14, {M,S,T}): puberty U[12,15]; childbearing ends U[35,45]
  women, U[45,55] men; max age U[60,100]. Std dev stays ~0.35–0.4.

### Culturally varying preferences (pp. 124–126), eq. (5)
- f = fraction of agent's tags that are 0.
- W(w1,w2) = w1^(m1·f/μ) · w2^(m2·(1−f)/μ), μ = m1·f + m2·(1−f).
- ({G1},{M,K,T}) infinitely lived: mean price random-walks (0.5–1.5) (Fig IV-15);
  std dev ~0.4–0.5 never settling (Fig IV-16); ~10^6 transactions (≈5× volume).
- ({G1},{M,S,K,T}) (Fig IV-17): std dev ~0.45.

### Pollution and prices (pp. 126–129) — Animation IV-3 ({G1, D1},{M,T,P})
- Sugar is "dirty": harvesting sugar → production pollution; metabolizing sugar →
  consumption pollution. Spice is clean.
- Trade from t=0; at t=100 sugar pollution starts; at t=150 pollution generation
  turned off and diffusion activated.
- Price (spice per sugar) rises roughly exponentially to ~3–4 around t≈160–170, then
  returns to ~1.0; recovery takes ~twice as long as the deviation.

### Foresight (p. 129), eq. (6) — Fig IV-18 ({G1},{M,S})
- W(w1,w2; φ) = (w1 − φ·m1)^(m1/mT) · (w2 − φ·m2)^(m2/mT), terms set to 0 if negative.
- φ initially U[0,10], sex on. Mean foresight settles ~4.75–5.0 (peak ~5.6 at t≈150,
  dip ~4.4 at t≈210).

### Trade partner networks (p. 131) — Animation IV-4
- Edges between agents who traded this period. Stats: transactions, sugar traded,
  spice traded (e.g. 602/679/706 early, 134/147/147 later).

### Credit rule L_dr (pp. 131–133)
- Potential lender if too old to have children: may lend at most **half its current wealth**.
- Potential lender if of childbearing age and wealth exceeds the amount needed to
  have children: may lend at most the **excess**.
- Potential borrower if of childbearing age, has insufficient wealth to have a child,
  and has income (resources gathered − metabolism − other loan obligations) in the
  present period making it credit-worthy for a loan at the lender's terms.
- If potential borrower and potential lender are neighbors, a loan originates:
  duration d years, rate r percent; face value transferred lender → borrower.
- At due date: if borrower can repay, transfer; else borrower pays back **half its
  wealth** and a new loan is originated for the remaining sum.
- Borrower dies before due date → lender takes the loss.
- Lender dies before due date → borrower need not repay, unless inheritance I is
  active, in which case the lender's children become the creditors.
- Animation IV-5 ({G1},{M,S,L_10,10}), one-commodity landscape; up to five levels
  of lender–borrower hierarchy. Stats: active loans, lenders, borrowers, both
  (e.g. 187 loans, 155 lenders, 129 borrowers, 21 both).
- Display: lenders green, borrowers red, both yellow; hierarchical plot with pure
  lenders on top, pure borrowers at bottom.

---

## Chapter V — Disease Processes

### Representation (pp. 141–142)
- Immune system = binary string; disease = binary string, always shorter than
  immune systems; diseases may differ in length.
- Agent is immune to D iff D is a substring of its immune system.
- Otherwise it searches for the substring closest to D in Hamming distance; on ties,
  the **leftmost** (first encountered left→right) substring is chosen.
- Each period one bit of that nearest substring is flipped to agree with D, until D is
  matched (then immune). While infected: agent can pass D to neighbors and its
  metabolism is increased (example in text: "hiked by, say, one").
- Worked example (pp. 143–144, Table V-1): I = 1011101001, D = 10011; start-position
  Hamming distances 1,4,3,2,3,3 → position 1 chosen; learning takes 1 period;
  I becomes 1001101001.

### Agent immune response rule (p. 144) — applied each period per disease
- If the disease is a substring of the immune system, end (agent immune); else
  (infected) go on;
- The substring of the immune system with the smallest Hamming distance from the
  disease is selected and the **first bit at which it differs** from the disease is
  changed to match.
- Immunological memory = lock-in; can be corrupted when learning another disease
  overwrites bits (e.g. diseases 11 and 00 cannot both be coded by length-3 system).

### Agent disease transmission rule (p. 145)
- For each neighbor, a disease that currently afflicts the agent is selected at
  random and given to the neighbor.
- **E** = immune response + transmission rules together.
- Each additional disease contracted imposes its characteristic metabolic penalty
  (fees are additive). Same disease can be caught repeatedly.

### Genotype vs phenotype (p. 146)
- Child inherits untrained genotype: where parents' genomes agree, child gets common
  value; where they differ, father's or mother's value with equal probability.
  Genotype is stored for transmission; a copy (phenotype) trains.
- Mutation rates exist in software but are **zero** in the book's runs (fn. 15).
- Childhood diseases persist because acquired immunity is not inherited.

### Runs (pp. 147–150) — ({G1},{M,E}), agents start at random positions
- Master disease list: each disease a random binary string of random length in [1,10].
- Immune systems: random binary strings of **length 50**.
- **Animation V-1:** master list of 10 diseases; each agent initially given 4 randomly
  selected diseases from the list. Result: society rids itself of all disease.
- **Animation V-2:** master list of 25; each agent given 10 distinct random diseases.
  Result: endemic infection sustained; universal health not attained.
- Display: sick (≥1 disease) red, well blue.
- **Animation V-3** disease transmission network (edge from sick agent to agent it
  caught it from). Stats: average diseases per agent 3.41 → 0.90 → 0.88 → 0.82 →
  0.91 → 0.81 (std dev ≈1.0) — this is the endemic (fail-to-clear) case.
- (Metabolic fee magnitude used in runs not stated beyond "say, one".)

---

## Chapter VI — Conclusions

### Emergent society — Animation VI-1 ({G1},{M,S,K,T,L_10,10,E})
- All rules on together, on the sugar-and-spice landscape. 18 views: agents (red =
  diseased, blue = healthy), neighbor network, sugar & spice wealth histograms,
  Lorenz/Gini (Gini 0.246 shown), population, age histogram, family trees,
  per-position count of "Blue" (0) tags, friends network, price, price std dev
  (~0.3–0.4), trade volume, trade network, spatial and hierarchical credit networks,
  fraction infected (starts ~1.0, dips to ~0.65 near t≈90, back to ~0.85),
  disease transmission network.
- Population plot shows start ~200 dropping toward ~150 early.

### Indecomposability (pp. 159–161)
- 500 initial agents on the Chapter IV sugar-and-spice landscape, rules M and S.
- **Animation VI-2 ({G1},{M,S}), no trade:** population crashes to extinction
  (500 → ~100 by t≈20, → ~0 by t≈120–150).
- **Animation VI-3 ({G1},{M,S,T}):** same, with trade on. Declines like no-trade for
  ~75 years (min ~100 around t≈80–100), then grows past 2× initial (~1200 peak at
  t≈210) and settles into sustained oscillations between ~700 and ~1200 with period
  ≈115 years. Mean maximum lifetime ~80 years.
- Footnotes: disease raises deaths (metabolic fee); credit augments fertility.

### Schelling variant (pp. 165–170) — Animations VI-4 … VI-7
- 50×50 torus, 2000 agents (≈ equal Red/Blue), 20% vacant. **Von Neumann**
  neighborhood; dissatisfied agent moves to a **random** acceptable unoccupied site
  (not nearest). Rule: satisfied if fraction of same-color neighbors ≥ preference.
- VI-4: preference 25%, repeat until all satisfied (equilibrium); modest segregation.
- VI-5: 25%, max lifetime U[80,100]; on death replaced by new agent of random color
  placed at random site satisfying its preference. Comparable segregation, never settles.
- VI-6: 50%, lifetimes U[80,100]: high segregation.
- VI-7: preferences U[25%,50%], lifetimes U[80,100]: still highly segregated.

### Ring World (pp. 170–176) — Animations VI-8, VI-9
- Ring of 150 sugar sites; initial sugar U[0,4]; capacity 4; growback unit rate.
- 40 agents placed randomly; vision U[15,30]; agents search **only counterclockwise**.
- Rule: inspect unoccupied sites within vision, go to nearest site with maximum sugar,
  eat it. No death, birth, combat, culture, disease, trade, or accumulation.
- Each agent moves once per period; random call order each period.
- Result: agents form traveling clusters ("flocking") of comparable size; a single
  megagroup of 40 breaks into like-sized groups (VI-9). Group size limited by the
  vision of the most nearsighted member (leapfrogging mechanism).

### Chapter VI readings and decisions (2026-10-22)
Read from the figures for the Chapter VI targets; frame times are estimates from their axes.
- **VI-1 panels:** neighbors 0.7 (fr. 2); Gini 0.246 (fr. 5); population 200 → ≈155 at t≈50 (fr. 6);
  average fertility 1.3 (fr. 8); best-friend / all-friend closeness 0.86 / 0.79 (fr. 10); price ≈1
  and ln-price sd 0.3–0.4 over t≈1–95 (fr. 11–12); ≈100–150 trades per period (fr. 13); active
  loans 211/219, lenders 138/145, borrowers 105/106, both 36/38 (fr. 15–16); infected fraction
  1.0 → ≈0.6 (t≈80) → ≈0.85 (t≈120) (fr. 17); average diseases 2.26, sd 1.47 (fr. 18).
- **VI-2:** 510 → ≈290 (t=10) → ≈130 (t=20) → ≈90 (t=40) → ≈50 (t=60) → ≈15 (t=100) → 0 by t≈140.
- **VI-3:** minimum ≈65 at t≈70–90; 500 at t≈165; peaks ≈1190 (t≈213), 1165 (330), 1215 (452);
  troughs ≈690 (272), 670 (390); bottom panel peaks reach ≈1250; peak spacing ≈117–122.
- **Decisions:** credit on the sugar-and-spice landscape lends sugar only (fertility tests sugar
  only, p.55). VI-1 uses Chapter IV agents (200), tags 11, K, T, L(10,10%), disease 25/10 (V-2's
  endemic setting; our call), no cultural preferences, no I. VI-2/VI-3: 500 Chapter IV agents with
  max age U[60,100]; the runs differ only in T. Schelling: no neighbors = satisfied; a newcomer
  with no acceptable site goes to any empty site. Ring World: integer sugar, counterclockwise =
  increasing index, an agent with a full field of view stays, groups allow one-site gaps.

---

## Appendix A — Software notes (pp. 179–181)
- Sites: n-dimensional resource level and capacity vectors, m-dimensional pollution
  levels and fluxes, pointer to occupant. Methods: growback, pollution deposition,
  diffusion (von Neumann neighbors → cellular automaton), display.
- Agents: vision, metabolism (n-vector), location, accumulations (n-vector), age,
  childbearing ages (puberty etc.), death age, parents, tags, immune system; lists of
  children, friends, loans, diseases. Single agent class (not inheritance hierarchy).
- Population object: aggregate stats (average age, fertility, minimum wealth,
  maximum inheritance gift), sorting/ranking (Gini), census.
- Original: ~20,000 lines, Macintosh, object-oriented.

## Appendix B — Summary of Rule Notation (pp. 182–185)
Source: `epstein_axtell.pdf` (full book scan), PDF pages 194–197. Mostly restates
the chapter rules. Differences from / additions to the chapter wording:
- **M (general form):** look out as far as vision permits in each of the four lattice
  directions; considering only **unoccupied** positions, find the **nearest position
  producing maximum welfare**; move there; collect **all the resources** at that
  location. (One-commodity case: welfare = sugar; with pollution: s/(1+p).)
- **P_Π,X (general pollution):** n resources, m pollutants. Gathering resource vector r
  produces production pollution p = Π·r (Π is m×n); consuming metabolism vector m
  produces consumption pollution c = X·m (X is m×n). Generalizes P_αβ.
- **S:** "if the neighboring agent is of the opposite sex and if **both** agents are
  fertile and at least one has an empty neighboring site, a newborn is produced by
  crossing-over the parents' **genetic and cultural** characteristics". So children
  get tags too (Ch III vertical transmission: agreeing positions copied, else coin flip).
- **Cultural transmission:** select a neighboring agent at random; select a tag
  randomly; if they disagree at that position the **neighbor's** tag flips to the
  agent's; **repeat for all neighbors**. (Each neighbor visited once, random order,
  one random tag position each.)
- **Group membership:** Blue when 0s outnumber 1s, Red otherwise.
- **Combat C_α, Trade T, Credit L_dr, Inheritance I, Immune response, Disease
  transmission, E:** identical to the chapter text already noted above.
- Appendix B gives **no** scheduling/rule-ordering information.

## Appendix C — State-Dependence of the Welfare Function (pp. 186–189)
Not about scheduling. Shows the Ch IV welfare W(w1,w2) makes site preference depend on
current wealth, because M evaluates W(w1 + x1, w2 + x2).
- Theorem (m1 = m2): sites (x1 − Δ1, x2 + Δ2), Δ1Δ2 > 0, are preferred at wealth
  (W1, W2) over (x1, x2) — which was preferred at wealth (w1, w2) — if
  W1 − w1 > (Δ1/Δ2)(W2 − w2) for Δ positive (< for Δ negative).
- **Worked example (use as a unit test of M with two commodities):** m1 = m2.
  At wealth (20, 50), site (3, 3) beats (2, 5): 23·53 = 1219 > 22·55 = 1210.
  At wealth (150, 250), (2, 5) beats (3, 3): 153·253 = 38709 < 152·255 = 38760.

## Not stated anywhere in the book
- Order of rule execution within a period (e.g. growback before/after agents; whether
  each agent does M then S/K/T/L/E in its own turn or each rule runs as a separate
  sweep). Text cues: Ch II neighbor networks — each agent moves, then records its
  neighbors, sequentially in random order; Ch III S — "after moving, agents are
  permitted to engage in sexual reproduction with their neighbors", and an agent mates
  with all viable neighbors "before it is the next agent's turn to move"; Ch IV — after
  an agent moves it trades once with each neighbor in random order. These imply
  **per-agent sequential execution: move, then interact**, in a random agent order
  reshuffled each period. Growback order is our decision.

---

## Kehoe (2016), "The Specification of Sugarscape" (arXiv:1505.06012v3)
A Z-notation formal spec of the Appendix B rules, with synchronous and asynchronous
variants. It is an interpretation, not a source: the author says rule order "is not
stated in the book" and he "chose the simplest" where it was ambiguous. Use it as a
checklist of ambiguities and as a tiebreaker **only where the book is silent**.

### Where Kehoe contradicts the book (do NOT follow Kehoe here)
| Topic | Book | Kehoe |
|---|---|---|
| Scheduling | Per agent, in random order: move, then interact with new neighbors (II p.39, III p.56, IV p.107) | Each rule is a separate sweep over all agents: Tick → Growback → Move/Combat → Inheritance → Death → Replacement or Mating → Culture → Credit → Disease → Trade |
| Metabolism timing | After moving: wealth += harvest − metabolism (p.25) | All agents pay metabolism at the start of the tick (Tick schema) |
| Death test | Wealth "falls to zero or below" | `agentSugar = 0` on naturals |
| Mating wealth test | At least the endowment at birth (≥) | Strictly greater (>) |
| Child endowment | Each parent gives half of **its own initial endowment** | Prose says half of current sugar; schema uses initialSugar/2 (inconsistent) |
| Seasonal winter rate | α units per β periods (fractional rate) | `SUGARGROWTH div WINTERRATE` = 1 div 8 = 0, so **no winter growth** |
| Trade crossing | Do not make a trade that would cross MRSs; trade must raise both welfares | Executes the crossing trade, then stops; no welfare check |
| Quantities | Real-valued (p units of spice, 1/p sugar) | Natural numbers with integer division |
| Credit "needed to have children" | Each agent's own birth endowment | Global constant CHILDAMT |

### Gap-fillers from Kehoe consistent with the book (adoptable)
- **Movement:** the current site counts as a candidate at distance 0; ties go to the
  nearest site. (Resolves open question 3.)
- **Combat:** retaliation is checked from the **proposed** site using the **attacker's**
  vision. If no safe site exists (including the current one), the agent stays put.
  Combat replaces movement for that agent.
- **Replacement:** a newly placed agent does not harvest its arrival site that period.
- **Inheritance:** agents dying in the same step don't inherit from each other; the
  lender's loans pass to its children (split equally) when I is active.
- **Death voids loans:** a dead borrower's loan is the lender's loss; a dead lender's
  loans are cancelled unless I is active.
- **Credit:** simple interest, amount due = principal × (1 + r·d); loan amount =
  min(lender's available amount, borrower's shortfall to its child requirement);
  "credit-worthy" = income/wealth sufficient to cover existing obligations (his
  interpretation; the book doesn't define it).
- **Disease penalty:** metabolism +1 per carried disease the agent is not yet immune to.
- **Two-resource combat:** wealth = sugar + spice (book has no two-resource combat run).
- **Two-resource credit:** separate sugar and spice loan books (book silent).
- **Seasonal growback for spice:** same WINTERRATE as sugar.

### Ambiguities Kehoe raises that the book does not settle
1. Once immune to a disease, is it removed from the agent's disease set, or does the
   agent remain a carrier? (Ch V speaks of agents "ridding" themselves of disease and
   counts "sick" as carrying ≥1 disease, which suggests removal on immunity.)
2. Can an agent transmit a disease it is immune to, or only active infections?
3. Conflict resolution under synchronous updating (not relevant: the book is
   explicitly sequential and asynchronous, Ch II fn 12).

## Findings from the Chapter II replication (2026-10-21)
- **Default initial endowment is most likely U[25,50]** for the landscape runs (II-1, II-2, II-6...):
  only that range reproduces Fig II-4's curve shape (no deaths until t≈7, ≈255 at t≈48).
  The wealth run II-3 states 5–25 explicitly.
- **Animation II-6 block**: the text implies 400 agents ("exactly as in II-2"); frame 1 shows a 20×19 block with ≈284 agents. Both are registered (II-6, II-6-measured).
- **Fig II-5**: our t≈50 populations match all 18 points within ±5%; at t=500 the m2/m3 points run 10–20% low. See
  docs/replication/chapter-2.md for what was ruled out.

## Open questions / gaps to resolve before implementation
1. **Sugar and spice capacity maps.** Only shown as figures (II-1, IV-1). Need the
   original 50×50 capacity data (commonly circulated as `sugar-map.txt`), or a faithful
   reconstruction from the figures.
2. **Order of execution within a period.** Appendices B and C (now read) don't specify
   it. Per-agent "move then interact" is implied by the text (see above); whether
   growback runs before or after the agent sweep must be chosen and documented.
3. **Movement M details:** current site is a candidate at distance 0 (Kehoe, consistent
   with the book). Ties at equal distance in different directions: first encountered
   in a randomly ordered direction scan (fn 9).
4. **Sex rule:** where the baby is placed when both parents have empty neighbor sites;
   whether the parent's sugar check uses current wealth ≥ its own initial endowment
   (as stated) and whether both parents deduct half their *initial* endowment.
   Whether a newborn's birth cost can push a parent's wealth below zero.
5. **Initial populations** not stated for some runs (e.g. Fig III-1, culture runs,
   combat runs). Animation frames suggest ~400 for most landscape runs.
6. **Combat** "nearest position having maximum reward" ties and retaliation vision
   (uses attacker's vision from the attack site).
7. **Disease** metabolic penalty: +1 per non-immune disease (Kehoe's reading of "say,
   one"). Still open: whether immune diseases are dropped from the carried set, and
   whether an agent can transmit a disease it is immune to.
8. **Credit L_dr:** income definition ("resources gathered − metabolism − other loan
   obligations") and how "credit-worthy at lender's terms" is computed.
9. **Chapter IV spice runs:** initial population size (Fig IV-3 text says 200;
   Chapter VI uses 500); default spice landscape is the sugar map mirrored
   (NW/SE peaks).

## Targets to reproduce (headline numbers)
| Result | Rules | Target |
|---|---|---|
| Carrying capacity | ({G1},{M}), 400 agents, v U{1..6}, m U{1..4} | ≈ 224 |
| Carrying capacity curves | ({G1},{M}), 500 agents | Fig II-5 values above |
| Selection without sex | same run as II-2 | vision 3.5→4.1, metabolism 2.5→1.8 by t=500 |
| Wealth Gini | ({G1},{M,R[60,100]}), 250 agents, endow U[5,25] | 0.230 → ~0.50 |
| Neighbor network | ({G1},{M}) | avg neighbors ≈ 0.9 |
| Stable population | ({G1},{M,S}) defaults | ~450–550 over 2500 steps |
| Evolution with sex | ({G1},{M,S}) | vision → ~5.3, metabolism → ~1.0 |
| Small/large oscillations, extinction | S variants (Figs III-3..5) | see Ch III notes |
| Inheritance Gini | ({G1},{M,S,I}) | → ~0.74 |
| Culture convergence | ({G1},{M,K}), tags len 11 | absorbing all-Blue/all-Red, ~2700 steps |
| Price convergence | ({G1},{M,T}), 200 agents | mean price → ~1, σ(ln p) → ~0.05 by t=1000 |
| Trade raises capacity | Fig IV-6 | see Ch IV notes |
| Trade raises Gini | Fig IV-13 | see Ch IV notes |
| Disease cleared vs endemic | ({G1},{M,E}) 10/4 vs 25/10 | cleared vs ~0.8–0.9 diseases/agent |
| Indecomposability | 500 agents, ({G1},{M,S}) vs +T | extinction vs oscillation 700–1200, period ≈115 |
| Schelling, Ring World | Ch VI | qualitative |
