# GPU against Python: agreement

436 tested windows, 0 flagged (Benjamini-Hochberg, q = 0.01); 0 untestable; 0 experiments not run.

## Flagged

None.

## Unflagged with p < 0.01

- VI-1 best_friend_closeness quarter 2: p 0.0012, Python 0.7164, GPU 0.7149
- VI-1 best_friend_closeness quarter 3: p 0.0027, Python 0.7172, GPU 0.7157
- VI-1 gini quarter 1: p 0.0087, Python 0.2706, GPU 0.2668

## Untestable windows (fewer than two seed values on a side)

None.

## Not run

None.

## Stale fingerprints or missing seeds

None.

## Speed (per period; development timings, uncontrolled)

| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Python setup s | Python step ms | Python metrics ms | GPU / Python step | Julia step ms | GPU / Julia step |
|---|---|---|---|---|---|---|---|---|---|
| II-4 | 0.2542 | 1.238 | 2.161 | 0.3049 | 1327 | 43.92 | 0.000933 | 14.06 | 0.088 |
| II-4-gini | 0.2305 | 1.552 | 1.932 | 0.2742 | 1671 | 48.86 | 0.000929 | 12.6 | 0.123 |
| II-6 | 0.2339 | 1.344 | 1.777 | 0.398 | 2072 | 55.83 | 0.000648 | 17.08 | 0.0787 |
| II-7 | 0.2342 | 1.068 | 1.906 | 0.3396 | 1044 | 35.78 | 0.00102 | 10.04 | 0.106 |
| II-8 | 0.237 | 3.541 | 2.07 | 0.2478 | 1351 | 40.84 | 0.00262 | 26.53 | 0.134 |
| IV-A3 | 0.2511 | 17.42 | 1.048 | 0.4049 | 1113 | 18.5 | 0.0157 | 28.08 | 0.621 |
| VI-1 | 0.2991 | 597.3 | 29.39 | 4.101 | 1.644e+04 | 477.6 | 0.0363 | 322.9 | 1.85 |
