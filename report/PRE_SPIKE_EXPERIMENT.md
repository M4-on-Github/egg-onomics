# Forecasts frozen before the spikes

We fitted forecasts before three documented outbreak periods, then held them fixed while actual prices unfolded. All inputs are from the original complete January 1980–April 2025 snapshot. No 2026 observations or interpolated prices enter this study.

At each origin, six disjoint earlier 12-month validation blocks select among the same nine R models using pooled RMSE. The final selected model is refitted through that origin and forecasts the next 12 months once. Automatic model structures and coefficients use the available history only. First-three-month RMSE is retained separately. The late-2024 case has seven observed months and five unavailable actuals; all five remain missing.

| Episode | Selected method | Observed peak month | Actual price | Baseline at peak | Actual minus baseline | Mean monthly gap |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| hpai_2014_15 | Auto ETS | 2015-09 | $2.966 | $2.000 | $+0.966 | $+0.422 |
| hpai_2022 | Auto ETS | 2023-01 | $4.823 | $1.926 | $+2.897 | $+1.295 |
| hpai_late_2024 | Holt-Winters | 2025-03 | $6.227 | $4.454 | $+1.773 | $+0.447 |

Prices and gaps are nominal U.S. dollars per dozen. The peak is the highest observed price in the fixed event window, not necessarily the peak over the entire outbreak. Mean gaps are signed averages over 12, 12 and 7 observed months respectively. They are not expenditure totals.

The largest departure in these windows occurred in the 2022 episode: January 2023 actual prices reached $4.823, while the pre-outbreak selected ETS model projected $1.926. The gap was $2.897 per dozen, approximately 150.4% above the reference. That measures departure from the fitted historical pattern; it does not assign the entire gap to avian influenza.

## Origin sensitivity

Moving the origin earlier can change both the fitted baseline and the selected method. Sensitivity runs keep the same target months, but select again using only the five complete earlier validation blocks available at each earlier origin. These checks are not independent replications or confidence bounds.

| Episode | Origin | Selected method | Baseline in primary peak month | Actual minus baseline |
| --- | --- | --- | ---: | ---: |
| hpai_2014_15 | 2014-11 | Auto ETS | $2.000 | $+0.966 |
| hpai_2014_15 | 2014-10 | Auto ETS | $2.023 | $+0.943 |
| hpai_2014_15 | 2014-08 | Auto ETS | $2.057 | $+0.909 |
| hpai_2022 | 2022-01 | Auto ETS | $1.926 | $+2.897 |
| hpai_2022 | 2021-12 | Auto ETS | $1.840 | $+2.983 |
| hpai_2022 | 2021-10 | Auto ETS | $1.987 | $+2.836 |
| hpai_late_2024 | 2024-09 | Holt-Winters | $4.454 | $+1.773 |
| hpai_late_2024 | 2024-08 | Auto ETS | $3.250 | $+2.977 |
| hpai_late_2024 | 2024-06 | Auto ETS | $3.143 | $+3.084 |

## Interpretation

This is an exploratory, model-based reference scenario, not an identified no-HPAI counterfactual. The event dates were selected retrospectively from outbreak records. The reference assumes that the model fitted to earlier prices would remain relevant through the event. Inflation, feed costs, demand, policies and other supply shocks can also produce forecast gaps. The September 2024 origin already includes earlier outbreaks and higher prices; it is only a reference before the later wave.

The shaded 80% and 95% bands are model prediction intervals for future prices. They do not quantify uncertainty in a causal HPAI effect. Neither post-event RMSE nor the model with the smallest post-event gap identifies the unobserved price path without an outbreak. The input is one later historical snapshot, rather than a collection of real-time data vintages.

## Reproduce and inspect

- Run `Rscript analysis/spike_counterfactual.R` or open the executed `analysis/spike_counterfactual.ipynb`.
- Open `results/spike_counterfactual/index.html` for selected baselines, all nine alternatives and the 27 individual model graphs.
- `predictions.csv` contains 324 frozen forecasts and associated gaps; `cv_predictions.csv` contains 1,944 pre-event validation forecasts.
- `origin_sensitivity.csv` contains 72 forecasts from earlier origins.
- `leakage_audit.csv`, `cv_folds.csv`, `settings.json`, `frozen_models.rds` and `sessionInfo.txt` retain cutoffs, settings, fitted models and runtime details.
- The notebook also plots earlier-origin sensitivity. The neural networks and Chronos model are outside this new experiment.

## Timing sources

- [USDA ERS: December 2014–June 2015 HPAI outbreak](https://www.ers.usda.gov/data-products/charts-of-note/79273). Origin: November 2014.
- [CDC: commercial poultry H5N1 outbreak announced in February 2022](https://www.cdc.gov/bird-flu/situation-summary/current-bird-flu-situation-in-poultry.html). Origin: January 2022.
- [USDA ERS: mid-October 2024–early March 2025 HPAI wave](https://www.ers.usda.gov/data-products/charts-of-note/112677). Origin: September 2024.
