# Questions for the authors (draft)

A draft for the project owner to adapt and send to Joshua Epstein and Robert Axtell. Each question names the result it
would settle and the page whose wording leaves it open. Our evidence for each is in the [README](../../README.md)
and the chapter records.

---

We have rebuilt Sugarscape from *Growing Artificial Societies* and reproduced most of Chapters II, IV and VI. The
population results of Chapter III (Figs III-1, III-3 to III-5) and Chapter VI's indecomposability runs elude us, as
they did Kehoe (2016). Our rule S as written settles near 360 agents instead of ≈500. We would be grateful for any
of these details of the original code:

1. **The fertility wealth test (p.55).** Did an agent need current sugar at least equal to its own birth endowment,
   or something else (a fixed amount, a fraction of the endowment, sugar plus spice)?
2. **The child's endowment and threshold (p.55).** Was the child's endowment half of each parent's *initial*
   endowment, and was that endowment also the child's own fertility threshold?
3. **Partner contact (p.56).** Did agents mate only with their four lattice neighbors after moving, and was the
   child placed on an empty site next to a parent?
4. **Founders' ages (Figs III-1 to III-5, VI-2).** Did the first generation start at age 0 or at random ages?
   Animation III-1's first histogram and VI-2's first-period births suggest random ages; Fig III-3's opening
   suggests age 0.
5. **Fig III-1 and Animations III-2/III-3.** Were these the same parameters? The animation run falls to about 170
   agents and later exceeds 1,000; Fig III-1 rises to about 570 and settles near 500.
6. **Fig II-5 and Fig IV-6.** At what time were the carrying capacities read? Ours match the figures at t≈50 but
   fall 10–25% below them by t=500 for metabolisms 2–3. And how many agents started the Fig IV-6 sweep?
7. **Animations V-2 and V-3.** What disease and immune-string lengths did the endemic run use, and is V-3's
   "average diseases per agent" the count of active (unmatched) diseases?

Thank you for the book, which remains the clearest account of agent-based social science we know.
