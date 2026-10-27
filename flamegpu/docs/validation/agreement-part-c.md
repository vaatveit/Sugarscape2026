# GPU against Python: agreement

4709 tested windows, 0 flagged (Benjamini-Hochberg, q = 0.01); 118 untestable; 0 experiments not run.

## Flagged

None.

## Unflagged with p < 0.01

- VAR-c1c3fit/VI-3 mean_spice quarter 3: p 0.00018, Python 28.18, GPU 30.67
- VAR-c1c3fit/VI-3 mean_sugar quarter 3: p 0.00026, Python 27.87, GPU 30.24
- VAR-c1c3fit/VI-3 mean_children quarter 4: p 0.0003, Python 1.121, GPU 1.201
- VAR-c1c3fit/VI-3 trades quarter 4: p 0.00076, Python 364.6, GPU 381
- VAR-c1c3fit/VI-3 mean_children quarter 3: p 0.00088, Python 1.132, GPU 1.207
- VAR-c1c3fit/VI-3 sugar_traded quarter 4: p 0.0013, Python 436.1, GPU 453.5
- VAR-c1c3fit/VI-3 mean_children quarter 2: p 0.0014, Python 1.128, GPU 1.196
- VAR-c1c3fit/VI-3 mean_sugar quarter 4: p 0.0017, Python 27.98, GPU 30.21
- VAR-inttrade/IV-12/a80 mean_metabolism quarter 2: p 0.0017, Python 2.483, GPU 2.532
- VAR-c1c3fit/VI-3 mean_sugar quarter 1: p 0.002, Python 26.61, GPU 27.77
- IV-13/trade/v3.5 mean_log_price quarter 2: p 0.0023, Python 0.02482, GPU -0.0126
- IV-13/trade/v3.5 mean_price quarter 2: p 0.0025, Python 1.027, GPU 0.9894
- VAR-c1c3fit/VI-3 mean_sugar quarter 2: p 0.0026, Python 28.28, GPU 30.14
- VAR-c1c3fit/VI-3 spice_traded quarter 4: p 0.0034, Python 429.2, GPU 445.1
- IV-6/notrade/v6 on_peak_fraction quarter 3: p 0.0034, Python 0.546, GPU 0.5048
- VAR-c1c3fit/VI-3 mean_spice quarter 4: p 0.0036, Python 28.34, GPU 30.55
- IV-13/trade/v1.5 mean_metabolism quarter 2: p 0.0038, Python 2.453, GPU 2.416
- VAR-c1c3fit/VI-3 gini quarter 4: p 0.0038, Python 0.2413, GPU 0.2549
- VAR-c1c3fit/VI-3 agents_ever quarter 4: p 0.0041, Python 9795, GPU 8898
- VAR-c1c3fit/VI-3 gini quarter 3: p 0.0041, Python 0.2423, GPU 0.2553
- VAR-share/VI-2 gini quarter 1: p 0.0044, Python 0.245, GPU 0.2324
- VAR-inttrade/IV-7 mean_neighbors quarter 2: p 0.005, Python 0.1647, GPU 0.1421
- IV-12/a300 trades quarter 3: p 0.0051, Python 149.4, GPU 133.1
- IV-12/a80 mean_vision quarter 1: p 0.0053, Python 3.219, GPU 3.145
- VAR-c1c3fit/VI-3 trades quarter 3: p 0.006, Python 364.4, GPU 380.1
- IV-15 mean_vision quarter 4: p 0.006, Python 3.21, GPU 3.459
- IV-13/notrade/v1.5 mean_vision quarter 1: p 0.0062, Python 1.533, GPU 1.516
- IV-12/a300 mean_vision quarter 4: p 0.0064, Python 3.355, GPU 3.254
- IV-12/a300 spice_traded quarter 3: p 0.0067, Python 169.5, GPU 150.1
- IV-12/a80 north_frac_low_vision quarter 3: p 0.0069, Python 0.4886, GPU 0.4531
- IV-15 mean_vision quarter 3: p 0.0069, Python 3.21, GPU 3.446
- IV-17 friend_closeness quarter 4: p 0.0073, Python 0.958, GPU 0.8768
- VAR-c1c3fit/VI-3 mean_spice quarter 2: p 0.0074, Python 28.75, GPU 30.68
- VAR-fit83/VI-2 north_frac_high_vision quarter 3: p 0.0088, Python 0.1214, GPU 0.04537
- IV-A3 sugar_traded quarter 2: p 0.0093, Python 41.85, GPU 33.51
- IV-13/trade/v3.5 gini quarter 2: p 0.0096, Python 0.3586, GPU 0.3643
- IV-13/trade/v10 price_sd quarter 2: p 0.0096, Python 0.3096, GPU 0.3035

## Untestable windows (fewer than two seed values on a side)

- IV-14 north_frac_low_vision quarter 3
- IV-14 north_frac_low_vision quarter 4
- IV-17 north_frac_high_vision quarter 3
- IV-17 north_frac_high_vision quarter 4
- IV-17 north_frac_low_vision quarter 2
- IV-17 north_frac_low_vision quarter 3
- IV-17 north_frac_low_vision quarter 4
- IV-17 red_xy quarter 3
- IV-17 red_xy quarter 4
- IV-17 red_advance quarter 3
- IV-17 red_advance quarter 4
- IV-18 north_frac_low_vision quarter 2
- IV-18 north_frac_low_vision quarter 3
- IV-18 north_frac_low_vision quarter 4
- VI-3 north_frac_low_vision quarter 4
- VAR-book/VI-3 north_frac_low_vision quarter 2
- VAR-book/VI-3 north_frac_low_vision quarter 3
- VAR-book/VI-3 north_frac_low_vision quarter 4
- VAR-share/VI-3 north_frac_low_vision quarter 2
- VAR-share/VI-3 north_frac_low_vision quarter 3
- VAR-share/VI-3 north_frac_low_vision quarter 4
- VAR-c1c3fit/VI-3 north_frac_low_vision quarter 3
- VAR-c1c3fit/VI-3 north_frac_low_vision quarter 4
- VAR-intgift/VI-2 north_frac_low_vision quarter 4
- VAR-intgift/VI-3 mean_vision quarter 2
- VAR-intgift/VI-3 mean_vision quarter 3
- VAR-intgift/VI-3 mean_vision quarter 4
- VAR-intgift/VI-3 mean_metabolism quarter 2
- VAR-intgift/VI-3 mean_metabolism quarter 3
- VAR-intgift/VI-3 mean_metabolism quarter 4
- VAR-intgift/VI-3 mean_sugar quarter 2
- VAR-intgift/VI-3 mean_sugar quarter 3
- VAR-intgift/VI-3 mean_sugar quarter 4
- VAR-intgift/VI-3 gini quarter 2
- VAR-intgift/VI-3 gini quarter 3
- VAR-intgift/VI-3 gini quarter 4
- VAR-intgift/VI-3 mean_neighbors quarter 2
- VAR-intgift/VI-3 mean_neighbors quarter 3
- VAR-intgift/VI-3 mean_neighbors quarter 4
- VAR-intgift/VI-3 ne_fraction quarter 2
- VAR-intgift/VI-3 ne_fraction quarter 3
- VAR-intgift/VI-3 ne_fraction quarter 4
- VAR-intgift/VI-3 on_peak_fraction quarter 2
- VAR-intgift/VI-3 on_peak_fraction quarter 3
- VAR-intgift/VI-3 on_peak_fraction quarter 4
- VAR-intgift/VI-3 north_frac_high_vision quarter 2
- VAR-intgift/VI-3 north_frac_high_vision quarter 3
- VAR-intgift/VI-3 north_frac_high_vision quarter 4
- VAR-intgift/VI-3 north_frac_low_vision quarter 2
- VAR-intgift/VI-3 north_frac_low_vision quarter 3
- VAR-intgift/VI-3 north_frac_low_vision quarter 4
- VAR-intgift/VI-3 mean_spice quarter 2
- VAR-intgift/VI-3 mean_spice quarter 3
- VAR-intgift/VI-3 mean_spice quarter 4
- VAR-intgift/VI-3 mean_price quarter 2
- VAR-intgift/VI-3 mean_price quarter 3
- VAR-intgift/VI-3 mean_price quarter 4
- VAR-intgift/VI-3 mean_log_price quarter 2
- VAR-intgift/VI-3 mean_log_price quarter 3
- VAR-intgift/VI-3 mean_log_price quarter 4
- VAR-intgift/VI-3 price_sd quarter 2
- VAR-intgift/VI-3 price_sd quarter 3
- VAR-intgift/VI-3 price_sd quarter 4
- VAR-intgiftc1/VI-3 north_frac_low_vision quarter 4
- VAR-fit83/VI-3 north_frac_low_vision quarter 3
- VAR-fit83/VI-3 north_frac_low_vision quarter 4
- VAR-inttrade/IV-14 north_frac_low_vision quarter 2
- VAR-inttrade/IV-14 north_frac_low_vision quarter 3
- VAR-inttrade/IV-14 north_frac_low_vision quarter 4
- VAR-inttrade/IV-17 mean_vision quarter 3
- VAR-inttrade/IV-17 mean_vision quarter 4
- VAR-inttrade/IV-17 mean_metabolism quarter 3
- VAR-inttrade/IV-17 mean_metabolism quarter 4
- VAR-inttrade/IV-17 mean_sugar quarter 3
- VAR-inttrade/IV-17 mean_sugar quarter 4
- VAR-inttrade/IV-17 gini quarter 3
- VAR-inttrade/IV-17 gini quarter 4
- VAR-inttrade/IV-17 mean_neighbors quarter 3
- VAR-inttrade/IV-17 mean_neighbors quarter 4
- VAR-inttrade/IV-17 ne_fraction quarter 3
- VAR-inttrade/IV-17 ne_fraction quarter 4
- VAR-inttrade/IV-17 on_peak_fraction quarter 3
- VAR-inttrade/IV-17 on_peak_fraction quarter 4
- VAR-inttrade/IV-17 north_frac_high_vision quarter 2
- VAR-inttrade/IV-17 north_frac_high_vision quarter 3
- VAR-inttrade/IV-17 north_frac_high_vision quarter 4
- VAR-inttrade/IV-17 north_frac_low_vision quarter 2
- VAR-inttrade/IV-17 north_frac_low_vision quarter 3
- VAR-inttrade/IV-17 north_frac_low_vision quarter 4
- VAR-inttrade/IV-17 blue_fraction quarter 3
- VAR-inttrade/IV-17 blue_fraction quarter 4
- VAR-inttrade/IV-17 blue_xy quarter 2
- VAR-inttrade/IV-17 blue_xy quarter 3
- VAR-inttrade/IV-17 blue_xy quarter 4
- VAR-inttrade/IV-17 red_xy quarter 3
- VAR-inttrade/IV-17 red_xy quarter 4
- VAR-inttrade/IV-17 blue_advance quarter 2
- VAR-inttrade/IV-17 blue_advance quarter 3
- VAR-inttrade/IV-17 blue_advance quarter 4
- VAR-inttrade/IV-17 red_advance quarter 3
- VAR-inttrade/IV-17 red_advance quarter 4
- VAR-inttrade/IV-17 best_friend_closeness quarter 2
- VAR-inttrade/IV-17 best_friend_closeness quarter 3
- VAR-inttrade/IV-17 best_friend_closeness quarter 4
- VAR-inttrade/IV-17 friend_closeness quarter 2
- VAR-inttrade/IV-17 friend_closeness quarter 3
- VAR-inttrade/IV-17 friend_closeness quarter 4
- VAR-inttrade/IV-17 mean_spice quarter 3
- VAR-inttrade/IV-17 mean_spice quarter 4
- VAR-inttrade/IV-17 mean_price quarter 2
- VAR-inttrade/IV-17 mean_price quarter 3
- VAR-inttrade/IV-17 mean_price quarter 4
- VAR-inttrade/IV-17 mean_log_price quarter 2
- VAR-inttrade/IV-17 mean_log_price quarter 3
- VAR-inttrade/IV-17 mean_log_price quarter 4
- VAR-inttrade/IV-17 price_sd quarter 2
- VAR-inttrade/IV-17 price_sd quarter 3
- VAR-inttrade/IV-17 price_sd quarter 4

## Not run

None.

## Stale fingerprints

None.

## Speed (per period; development timings, uncontrolled)

| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Python setup s | Python step ms | Python metrics ms | GPU / Python step |
|---|---|---|---|---|---|---|---|
| IV-3 | 0.3559 | 23.56 | 0.5082 | 0.003298 | 1.785 | 0.1774 | 13.2 |
| IV-6/trade/v1 | 0.3589 | 21.92 | 0.5092 | 0.003747 | 1.952 | 0.2319 | 11.2 |
| IV-6/trade/v2 | 0.3523 | 25.48 | 0.5141 | 0.003465 | 2.815 | 0.2587 | 9.05 |
| IV-6/trade/v3 | 0.3644 | 28.06 | 0.5469 | 0.003569 | 3.743 | 0.2982 | 7.5 |
| IV-6/trade/v6 | 0.4019 | 32.31 | 0.5924 | 0.003718 | 5.85 | 0.3374 | 5.52 |
| IV-6/trade/v10 | 0.4889 | 38.15 | 0.587 | 0.008332 | 8.486 | 0.3688 | 4.5 |
| IV-6/notrade/v1 | 0.4649 | 8.636 | 0.6067 | 0.005408 | 0.8736 | 0.1624 | 9.89 |
| IV-6/notrade/v2 | 0.4033 | 9.945 | 0.57 | 0.00458 | 1.454 | 0.1892 | 6.84 |
| IV-6/notrade/v3 | 0.4911 | 11.46 | 0.6072 | 0.00363 | 2.325 | 0.2338 | 4.93 |
| IV-6/notrade/v6 | 0.3646 | 14.63 | 0.533 | 0.003765 | 4.429 | 0.2958 | 3.3 |
| IV-6/notrade/v10 | 0.4276 | 19.04 | 0.5781 | 0.003708 | 6.914 | 0.3191 | 2.75 |
| IV-7 | 0.4198 | 17.55 | 0.5123 | 0.002256 | 0.9171 | 0.1523 | 19.1 |
| IV-9 | 0.3793 | 26.59 | 0.4904 | 0.006868 | 4.042 | 0.2586 | 6.58 |
| IV-12/a80 | 0.4117 | 31.44 | 0.5208 | 0.002623 | 5.834 | 0.4436 | 5.39 |
| IV-12/a300 | 0.3962 | 32.94 | 0.476 | 0.002608 | 5.915 | 0.4356 | 5.57 |
| IV-12/a550 | 0.4027 | 33.78 | 0.4752 | 0.002734 | 6.026 | 0.4543 | 5.6 |
| IV-12/a980 | 0.3488 | 33.71 | 0.4836 | 0.003183 | 5.96 | 0.4389 | 5.66 |
| IV-13/trade/v1.5 | 0.3486 | 37.85 | 0.533 | 0.004838 | 11.13 | 0.9398 | 3.4 |
| IV-13/trade/v3.5 | 0.3486 | 46.8 | 0.548 | 0.005348 | 16.39 | 1.009 | 2.85 |
| IV-13/trade/v5.5 | 0.3335 | 52.65 | 0.5195 | 0.008042 | 28.77 | 1.474 | 1.83 |
| IV-13/trade/v10 | 0.3492 | 69.85 | 0.5094 | 0.009679 | 41.23 | 1.543 | 1.69 |
| IV-13/trade/v14.5 | 0.3563 | 83.57 | 0.5167 | 0.0135 | 47.94 | 1.405 | 1.74 |
| IV-13/notrade/v1.5 | 0.3418 | 14.21 | 0.5506 | 0.008207 | 9.975 | 1.191 | 1.42 |
| IV-13/notrade/v3.5 | 0.3273 | 20.84 | 0.5199 | 0.007942 | 14.8 | 1.18 | 1.41 |
| IV-13/notrade/v5.5 | 0.3376 | 27.23 | 0.5162 | 0.00633 | 17.42 | 1.106 | 1.56 |
| IV-13/notrade/v10 | 0.341 | 42.64 | 0.5067 | 0.006834 | 22.66 | 0.8995 | 1.88 |
| IV-13/notrade/v14.5 | 0.3576 | 53.29 | 0.5146 | 0.007655 | 27.76 | 0.8314 | 1.92 |
| IV-14 | 0.3989 | 41.75 | 0.296 | 0.004043 | 28.09 | 1.085 | 1.49 |
| IV-15 | 0.3893 | 53.17 | 0.4692 | 0.003387 | 3.999 | 0.6562 | 13.3 |
| IV-17 | 0.3608 | 265.6 | 0.5 | 0.00429 | 16.27 | 1.773 | 16.3 |
| IV-A3 | 0.3453 | 22.35 | 0.5128 | 0.002144 | 1.974 | 0.1968 | 11.3 |
| IV-18 | 0.3489 | 38.39 | 0.2912 | 0.003084 | 14.41 | 0.6949 | 2.66 |
| IV-A5 | 0.3703 | 108.2 | 0.6379 | 0.004406 | 13.31 | 0.9046 | 8.13 |
| VI-2 | 0.3263 | 54.34 | 0.498 | 0.006787 | 6.52 | 0.4085 | 8.33 |
| VI-3 | 0.3905 | 147.3 | 0.5122 | 0.006425 | 32.07 | 1.074 | 4.59 |
| VAR-book/VI-2 | 0.3509 | 21.45 | 0.4988 | 0.007323 | 1.898 | 0.1881 | 11.3 |
| VAR-book/VI-3 | 0.411 | 32.99 | 0.3417 | 0.006489 | 10.47 | 0.4807 | 3.15 |
| VAR-share/VI-2 | 0.3383 | 21.65 | 0.4935 | 0.00773 | 1.929 | 0.1864 | 11.2 |
| VAR-share/VI-3 | 0.3622 | 28.58 | 0.334 | 0.006608 | 11.02 | 0.4845 | 2.59 |
| VAR-c1c3fit/VI-2 | 0.3315 | 100.6 | 0.5163 | 0.006436 | 14.54 | 0.7797 | 6.92 |
| VAR-c1c3fit/VI-3 | 0.3837 | 154.6 | 0.5095 | 0.006176 | 32.23 | 1.063 | 4.8 |
| VAR-intgift/VI-2 | 0.3292 | 21.56 | 0.4854 | 0.01366 | 3.316 | 0.3031 | 6.5 |
| VAR-intgift/VI-3 | 0.3553 | 15.62 | 0.1682 | 0.01011 | 18.78 | 0.7295 | 0.831 |
| VAR-intgiftc1/VI-2 | 0.3366 | 54.5 | 0.4931 | 0.00757 | 6.905 | 0.4574 | 7.89 |
| VAR-intgiftc1/VI-3 | 0.3689 | 147.3 | 0.5167 | 0.008354 | 34.27 | 1.188 | 4.3 |
| VAR-fit83/VI-2 | 0.3447 | 25.32 | 0.5011 | 0.0117 | 5.615 | 0.4837 | 4.51 |
| VAR-fit83/VI-3 | 0.3829 | 59.77 | 0.5048 | 0.01097 | 16.35 | 0.677 | 3.65 |
| VAR-inttrade/IV-3 | 0.3714 | 22.64 | 0.518 | 0.00295 | 2.13 | 0.2286 | 10.6 |
| VAR-inttrade/IV-6/trade/v1 | 0.364 | 20.6 | 0.5358 | 0.008357 | 2.012 | 0.2703 | 10.2 |
| VAR-inttrade/IV-6/trade/v2 | 0.3582 | 23.87 | 0.5292 | 0.006391 | 2.891 | 0.2913 | 8.26 |
| VAR-inttrade/IV-6/trade/v3 | 0.3421 | 26.36 | 0.4989 | 0.004354 | 4.18 | 0.3436 | 6.31 |
| VAR-inttrade/IV-6/trade/v6 | 0.3527 | 31.6 | 0.4906 | 0.004109 | 6.844 | 0.3848 | 4.62 |
| VAR-inttrade/IV-6/trade/v10 | 0.3351 | 37.02 | 0.4889 | 0.003748 | 9.861 | 0.4105 | 3.75 |
| VAR-inttrade/IV-7 | 0.3769 | 16.52 | 0.4708 | 0.002042 | 0.8287 | 0.1556 | 19.9 |
| VAR-inttrade/IV-9 | 0.3619 | 25.82 | 0.4816 | 0.002031 | 3.995 | 0.2457 | 6.46 |
| VAR-inttrade/IV-12/a80 | 0.3523 | 30.1 | 0.5058 | 0.002511 | 6.009 | 0.42 | 5.01 |
| VAR-inttrade/IV-12/a300 | 0.3588 | 30.99 | 0.5053 | 0.002627 | 6.153 | 0.4212 | 5.04 |
| VAR-inttrade/IV-12/a550 | 0.3508 | 30.99 | 0.4834 | 0.002654 | 6.081 | 0.4258 | 5.1 |
| VAR-inttrade/IV-12/a980 | 0.3702 | 31.29 | 0.4806 | 0.003179 | 6.364 | 0.4536 | 4.92 |
| VAR-inttrade/IV-13/trade/v1.5 | 0.3474 | 36.47 | 0.5273 | 0.00476 | 11.26 | 0.8936 | 3.24 |
| VAR-inttrade/IV-13/trade/v3.5 | 0.3544 | 44.86 | 0.5431 | 0.005424 | 13.86 | 0.8098 | 3.24 |
| VAR-inttrade/IV-13/trade/v5.5 | 0.3382 | 51.24 | 0.5366 | 0.005029 | 16.68 | 0.7826 | 3.07 |
| VAR-inttrade/IV-13/trade/v10 | 0.3442 | 67.3 | 0.5053 | 0.01055 | 22.53 | 0.7438 | 2.99 |
| VAR-inttrade/IV-13/trade/v14.5 | 0.3474 | 78.48 | 0.5088 | 0.005312 | 31.8 | 0.7944 | 2.47 |
| VAR-inttrade/IV-14 | 0.3637 | 58.04 | 0.3527 | 0.003569 | 18.24 | 0.6369 | 3.18 |
| VAR-inttrade/IV-15 | 0.3545 | 40.95 | 0.4679 | 0.004163 | 2.971 | 0.6089 | 13.8 |
| VAR-inttrade/IV-17 | 0.3759 | 14.28 | 0.1566 | 0.004313 | 12.94 | 1.413 | 1.1 |
| VAR-inttrade/IV-A3 | 0.3419 | 21.53 | 0.512 | 0.002221 | 2.03 | 0.2011 | 10.6 |
| VAR-inttrade/VI-3 | 0.3472 | 140 | 0.5205 | 0.008198 | 34.34 | 1.166 | 4.08 |
