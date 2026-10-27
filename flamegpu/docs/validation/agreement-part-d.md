# GPU against Python: agreement

432 tested windows, 0 flagged (Benjamini-Hochberg, q = 0.01); 10 untestable; 0 experiments not run.

## Flagged

None.

## Unflagged with p < 0.01

None.

## Untestable windows (fewer than two seed values on a side)

- VI-1 north_frac_high_vision quarter 3
- VI-1 north_frac_high_vision quarter 4
- VI-1 north_frac_low_vision quarter 2
- VI-1 north_frac_low_vision quarter 3
- VI-1 north_frac_low_vision quarter 4
- VAR-inttrade/VI-1 north_frac_high_vision quarter 3
- VAR-inttrade/VI-1 north_frac_high_vision quarter 4
- VAR-inttrade/VI-1 north_frac_low_vision quarter 2
- VAR-inttrade/VI-1 north_frac_low_vision quarter 3
- VAR-inttrade/VI-1 north_frac_low_vision quarter 4

## Not run

None.

## Stale fingerprints

None.

## Speed (per period; development timings, uncontrolled)

| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Python setup s | Python step ms | Python metrics ms | GPU / Python step |
|---|---|---|---|---|---|---|---|
| V-1 | 0.3898 | 26.76 | 0.5968 | 0.03418 | 3.453 | 0.4074 | 7.75 |
| V-2 | 0.4213 | 27.24 | 0.6044 | 0.07814 | 3.64 | 0.3907 | 7.48 |
| VI-1 | 0.3897 | 60.86 | 0.412 | 0.0442 | 7.794 | 0.9162 | 7.81 |
| VAR-inttrade/VI-1 | 0.3604 | 60.15 | 0.4274 | 0.04079 | 8.5 | 1.02 | 7.08 |
