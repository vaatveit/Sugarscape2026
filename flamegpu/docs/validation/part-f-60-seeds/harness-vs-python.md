# GPU against Python: agreement

131 tested windows, 4 flagged (Benjamini-Hochberg, q = 0.01); 0 untestable; 0 experiments not run.

## Flagged

- III-7 mean_neighbors quarter 3: p 3e-05, Python 3.456, GPU 3.425 (-0.885 Python seed SDs)
- III-7 mean_neighbors quarter 4: p 1e-06, Python 3.492, GPU 3.473 (-1.02 Python seed SDs)
- III-7 moved quarter 4: p 1.4e-05, Python 84.61, GPU 94.49 (0.89 Python seed SDs)
- III-7 on_peak_fraction quarter 2: p 2.6e-05, Python 0.4965, GPU 0.4943 (-0.917 Python seed SDs)

## Unflagged with p < 0.01

- III-7 moved quarter 3: p 0.0013, Python 115, GPU 126.8

## Untestable windows (fewer than two seed values on a side)

None.

## Not run

None.

## Stale fingerprints or missing seeds

- III-7
- VI-3

## Speed (per period; development timings, uncontrolled)

| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Python setup s | Python step ms | Python metrics ms | GPU / Python step | Julia step ms | GPU / Julia step |
|---|---|---|---|---|---|---|---|---|---|
