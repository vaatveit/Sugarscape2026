# GPU against Julia: agreement

131 tested windows, 2 flagged (Benjamini-Hochberg, q = 0.01); 0 untestable; 0 experiments not run.

## Flagged

- III-7 mean_neighbors quarter 4: p 1.2e-06, Julia 3.491, GPU 3.474 (-0.909 Julia seed SDs)
- III-7 on_peak_fraction quarter 2: p 3.7e-05, Julia 0.4961, GPU 0.4935 (-0.818 Julia seed SDs)

## Unflagged with p < 0.01

- III-7 ne_fraction quarter 3: p 0.0035, Julia 0.3736, GPU 0.3703
- III-7 moved quarter 4: p 0.008, Julia 85.53, GPU 90.83

## Untestable windows (fewer than two seed values on a side)

None.

## Not run

None.

## Stale fingerprints or missing seeds

None.

## Speed (per period; development timings, uncontrolled)

| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Julia setup s | Julia step ms | Julia metrics ms | GPU / Julia step | Julia step ms | GPU / Julia step |
|---|---|---|---|---|---|---|---|---|---|
| III-7 | 0.3597 | 181.4 | 0.8112 | 0.01444 | 1.732 | 0.258 | 105 | 1.732 | 105 |
| VI-3 | 0.2815 | 122.4 | 0.5806 | 0.0179 | 2.455 | 0.1652 | 49.9 | 2.455 | 49.9 |
