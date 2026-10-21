# Egg-onomics

Monthly U.S. retail egg-price forecasting in R, using the supplied frozen CSV.
Open **results/index.html** for the self-contained evidence viewer. All charts
are embedded, so that file works offline by itself.

## Run

Open `egg-onomics.Rproj` in RStudio, then run:

```r
# Once, if needed:
install.packages(c("forecast", "jsonlite"))

source("analysis/forecast.R")
```

Or run `Rscript analysis/forecast.R` from the repository root. The command-line
script also resolves its project root when run from another working directory.
No network calls or CSV updates occur during analysis.

Validated locally using R 4.6.1 and forecast 9.0.2. Exact package/runtime details
are recorded in `results/session_info.txt`. Numerical estimates can vary slightly
across package versions.

## Data

- **Series:** APU0000708111, Average Price: Eggs, Grade A, Large (Cost per Dozen)
  in U.S. City Average.
- **Source:** U.S. Bureau of Labor Statistics, distributed by
  [FRED](https://fred.stlouisfed.org/series/APU0000708111).
- **Unit/frequency:** nominal U.S. dollars per dozen, monthly, not seasonally adjusted.
- **Saved snapshot:** January 1980-April 2025; 544 rows; no missing months, missing
  prices or duplicate dates. Month-start dates are month identifiers, not daily prices.
- **Provenance:** the supplied CSV is preserved; its MD5 is saved in
  `results/data_quality.csv`. The file's original retrieval date is unknown.
- **Source interpretation:** BLS average prices describe monthly price levels.
  For an inflation-rate study, an appropriate CPI index would be preferable.

## Investigation design

Question: how well do exponential-smoothing methods forecast monthly egg-price
levels, and what do they project for the ten months following the saved endpoint?

| Partition | Dates | Months | Role |
| --- | --- | ---: | --- |
| Training | Jan 1980-Apr 2023 | 520 | Exploration, estimation, residual diagnostics |
| Validation | May 2023-Apr 2024 | 12 | Choose smoothing method by RMSE |
| Final test | May 2024-Apr 2025 | 12 | Evaluate after model choice is locked |

Five smoothing methods: SES, Holt, Damped Holt, Holt-Winters, automatic ETS.
All fit log prices with additive errors and use bias-adjusted dollar-scale means.
The automatic ETS rule selects its structure by AICc within each fitting window.
Naive and seasonal-naive forecasts on original prices are comparison benchmarks.
Selection is explicitly among smoothing methods, even if a benchmark is stronger.

Forecasts for each evaluation year are fixed-origin 12-step forecasts, without
updating models using that year's observations. All methods receive identical
fitting and evaluation windows. After evaluation, the selected rule is refit to
all 544 observations for the 10-month historical forecast.

## Computed checkpoints

These are analysis notes to verify against the saved tables, not a written report.

- SES has the lowest validation RMSE among smoothing methods: **$0.960/dozen**.
  Damped Holt is nearly tied at $0.960. The naive benchmark is better at $0.912.
- On the final test, Damped Holt has the lowest RMSE: **$1.521/dozen**.
  The preselected SES has RMSE **$1.627**, MAE **$1.221**, MAPE **25.22%**,
  and positive mean error **$1.164** (underprediction).
- SES 95% prediction-interval test coverage is **8/12 = 66.7%**. Nominal interval
  levels overstate the observed coverage in this particular test year.
- Training STL seasonal strength on log prices is **0.214**. Level persistence
  is strong; changes show much less persistence. Seasonal structure exists but
  does not make the seasonal smoothing model the validation winner.
- Smoothing-model residual Ljung-Box p-values are small. Remaining dependence and
  changing volatility limit the white-noise assumption and interval reliability.
- The SES forecast mean runs from approximately **$5.153** in May 2025 to
  **$5.264** in February 2026. Slightly increasing means arise from log-scale
  bias adjustment and increasing variance, not an estimated SES trend.
- February 2026 model-based 95% prediction interval: approximately **$3.340-$7.910**.
  These are historical projections made from April 2025, not current predictions.

## Outputs

| File | Purpose |
| --- | --- |
| `results/index.html` | Self-contained charts, tables, method notes and interpretation prompts |
| `results/figures/*.png` | 13 labeled graphics, including residual diagnostics for every model |
| `results/validation_accuracy.csv` | Validation error and interval-coverage comparison |
| `results/test_accuracy.csv` | Final-test error and interval-coverage comparison |
| `results/evaluation_predictions.csv` | Every evaluation actual, forecast and interval |
| `results/forecast_10_months.csv` | May 2025-Feb 2026 means and 80%/95% prediction intervals |
| `results/model_parameters.csv` | Estimated parameters at each fitting stage |
| `results/residual_diagnostics.csv` | Residual summaries, ACF values and approximate Ljung-Box tests |
| `results/data_splits.csv`, `results/data_quality.csv` | Data validation and provenance |
| `results/fitted_models.rds` | Saved fitted objects for inspection in R |
| `results/analysis_summary.txt`, `results/session_info.txt` | Summary and runtime provenance |

## Finish the assignment

Use `REPORT_OUTLINE.md` to write your interpretation and plan your individual
5-7 minute presentation. The project brief restricts AI-generated written reports
and slides; this repository supplies code, computed evidence, and prompts instead
of completed submission prose or a slide deck. Review the code, adapt it to what
was taught in class, and disclose assistance as your course requires.

Limitations to address: one validation year and one test year, a long historical
estimation window, shocks and volatility changes, no external explanatory data,
approximate log back-transformation, approximate residual tests, and weak observed
interval calibration. No causal attribution to particular events is established
by this univariate analysis.

