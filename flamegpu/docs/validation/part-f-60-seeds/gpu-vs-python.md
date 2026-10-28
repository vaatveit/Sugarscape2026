# GPU against Python: agreement

131 tested windows, 2 flagged (Benjamini-Hochberg, q = 0.01); 0 untestable; 0 experiments not run.

## Flagged

- III-7 mean_neighbors quarter 4: p 4e-07, Python 3.492, GPU 3.474 (-0.956 Python seed SDs)
- III-7 on_peak_fraction quarter 2: p 1.8e-07, Python 0.4965, GPU 0.4935 (-1.26 Python seed SDs)

## Unflagged with p < 0.01

- III-7 ne_fraction quarter 3: p 0.00026, Python 0.3743, GPU 0.3703
- III-7 on_peak_fraction quarter 3: p 0.0012, Python 0.4746, GPU 0.4702
- III-7 moved quarter 4: p 0.0017, Python 84.61, GPU 90.83
- III-7 mean_neighbors quarter 3: p 0.0059, Python 3.456, GPU 3.438

## Untestable windows (fewer than two seed values on a side)

None.

## Not run

None.

## Stale fingerprints or missing seeds

None.

## Speed (per period; development timings, uncontrolled)

| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Python setup s | Python step ms | Python metrics ms | GPU / Python step | Julia step ms | GPU / Julia step |
|---|---|---|---|---|---|---|---|---|---|
| III-7 | 0.3597 | 181.4 | 0.8112 | 0.01782 | 50.35 | 2.808 | 3.6 | nan | nan |
| VI-3 | 0.2815 | 122.4 | 0.5806 | 0.02499 | 67.94 | 2.16 | 1.8 | nan | nan |
