# GPU against Julia: agreement

523 tested windows, 6 flagged (Benjamini-Hochberg, q = 0.01); 0 untestable; 2 experiments not run.

## Flagged

- III-7 moved quarter 1: p 3.2e-06, Julia 4.21e+04, GPU 4.254e+04 (6.93 Julia seed SDs)
- VI-3 moved quarter 3: p 1.8e-05, Julia 7.125e+04, GPU 7.161e+04 (7.32 Julia seed SDs)
- VI-3 moved quarter 4: p 7.3e-05, Julia 7.165e+04, GPU 7.202e+04 (9.62 Julia seed SDs)
- VI-3 price_sd quarter 2: p 0.0001, Julia 0.4037, GPU 0.4089 (11.2 Julia seed SDs)
- VI-3 sugar_traded quarter 3: p 4.1e-05, Julia 5.712e+04, GPU 5.775e+04 (5.07 Julia seed SDs)
- VI-3 sugar_traded quarter 4: p 7.1e-05, Julia 5.674e+04, GPU 5.736e+04 (4.52 Julia seed SDs)

## Unflagged with p < 0.01

- III-7 on_peak_fraction quarter 2: p 0.00018, Julia 0.5022, GPU 0.5017
- III-8 mean_metabolism quarter 2: p 0.0003, Julia 1.799, GPU 1.809
- III-8 mean_metabolism quarter 3: p 0.00043, Julia 1.797, GPU 1.808
- III-8 mean_metabolism quarter 4: p 0.0005, Julia 1.797, GPU 1.808
- III-8 mean_metabolism quarter 1: p 0.00081, Julia 1.838, GPU 1.848
- VI-3 mean_log_price quarter 2: p 0.0014, Julia 0.003184, GPU -0.001556
- VI-3 mean_price quarter 2: p 0.0014, Julia 1.003, GPU 0.9986
- VI-3 trades quarter 4: p 0.0015, Julia 4.674e+04, GPU 4.705e+04
- VI-3 sugar_traded quarter 2: p 0.0019, Julia 5.766e+04, GPU 5.835e+04
- III-7 mean_neighbors quarter 4: p 0.0033, Julia 3.742, GPU 3.737
- VI-3 north_frac_high_vision quarter 4: p 0.0035, Julia 0.5213, GPU 0.5208
- III-8 mean_sugar quarter 2: p 0.0052, Julia 2568, GPU 2539
- VI-3 trades quarter 3: p 0.0053, Julia 4.683e+04, GPU 4.712e+04
- III-7 mean_sugar quarter 1: p 0.0059, Julia 77.01, GPU 77.44
- III-8 mean_sugar quarter 3: p 0.0061, Julia 4283, GPU 4236
- III-8 mean_sugar quarter 1: p 0.0062, Julia 854.2, GPU 845.2
- III-8 mean_sugar quarter 4: p 0.0065, Julia 6000, GPU 5934
- III-8 gini quarter 2: p 0.0094, Julia 0.3807, GPU 0.3846

## Untestable windows (fewer than two seed values on a side)

None.

## Not run

- III-9
- III-11

## Stale fingerprints or missing seeds

None.

## Speed (per period; development timings, uncontrolled)

| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Julia setup s | Julia step ms | Julia metrics ms | GPU / Julia step | Julia step ms | GPU / Julia step |
|---|---|---|---|---|---|---|---|---|---|
| III-1 | 0.2716 | 302.4 | 4.246 | 0.03677 | 109.6 | 14.77 | 2.76 | 109.6 | 2.76 |
| III-7 | 0.2724 | 619 | 10.93 | 0.06109 | 242.3 | 44.91 | 2.55 | 242.3 | 2.55 |
| III-8 | 0.268 | 10.91 | 4.578 | 0.1707 | 37.39 | 20.17 | 0.292 | 37.39 | 0.292 |
| IV-3 | 0.2549 | 12.88 | 1.041 | 0.0413 | 10.35 | 0.9834 | 1.24 | 10.35 | 1.24 |
| IV-6/trade/v6 | 0.2709 | 17.26 | 1.817 | 0.04633 | 34.59 | 2.478 | 0.499 | 34.59 | 0.499 |
| VI-3 | 0.2851 | 449.5 | 8.372 | 0.06115 | 320.2 | 32.27 | 1.4 | 320.2 | 1.4 |
| IV-A5 | 0.3545 | 318.8 | 17.1 | 0.0823 | 256.1 | 47.99 | 1.24 | 256.1 | 1.24 |
| V-2 | 0.3443 | 6.12 | 2.639 | 0.08074 | 32.08 | 7.673 | 0.191 | 32.08 | 0.191 |
