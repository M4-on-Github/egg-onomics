# Egg onomics

Forecast monthly U.S. egg prices using the original complete dataset through
April 2025. The active workflow compares all nine models over three-month
validation, test and forecast windows. It uses no 2026 observations, missing-value
fills or interpolation.

## Start here

1. Open `egg-onomics.Rproj` in RStudio.
2. Install dependencies once if necessary:

   ```r
   install.packages(c("forecast", "jsonlite"))
   ```

3. Run the single main script:

   ```r
   source("analysis/forecast.R")
   ```

4. Open `results/index.html` for the charts and tables, or `results/results.txt`
   for the plain-text summary.

Command line: `Rscript analysis/forecast.R`. RStudio Source also works when the
working directory is `analysis/`. `EGG_FORECAST_OUTPUT` optionally changes the
output directory.

## Folder guide

| Location | Purpose |
| --- | --- |
| `data/APU0000708111.csv` | Original unchanged input, January 1980-April 2025 |
| `analysis/forecast.R` | Main analysis for all nine models and three-month forecasts |
| `analysis/helpers.R` | Shared model, scoring and plotting functions and colors |
| `analysis/viewer.R` | HTML presentation of the current results |
| `results/` | Current generated charts, tables, fitted models and runtime details |
| `report/REPORT_OUTLINE.md` | Writing guide tied to the current analysis |
| `junk/previous-work/` | Archived experiments, 2026 data, old results and annual report draft |

## Data and evaluation

The input is BLS/FRED series APU0000708111, the U.S. city average price of large
Grade A eggs in nominal U.S. dollars per dozen, monthly and not seasonally
adjusted. Source: [FRED](https://fred.stlouisfed.org/series/APU0000708111).
There are 544 complete observations and no missing months or prices.

| Partition | Dates | Months |
| --- | --- | ---: |
| Training | January 1980-October 2024 | 538 |
| Validation | November 2024-January 2025 | 3 |
| Test | February-April 2025 | 3 |
| Historical forecast | May-July 2025 | 3 |

Methods: SES, Holt, Damped Holt, Holt-Winters, automatic ETS, naive, seasonal
naive, nonseasonal automatic ARIMA and seasonal automatic ARIMA. Smoothing and
ARIMA models fit log prices and return bias-adjusted dollar-scale means.
Benchmarks operate on original dollar prices. Validation RMSE selects the method
before the final-test scores are calculated. Every method is also refitted to
all 544 observations to produce its own three-month forecast.

The seasonal period remains 12 months even though the forecast horizon is three
months. The final test contains the 2025 price spike. With only three outcomes,
accuracy and interval coverage are sensitive to the chosen period. Historical
forecasts from April 2025 should not be described as current forecasts.

## Useful output files

- `results/data_quality.csv` and `data_splits.csv`: source hash, completeness and dates.
- `results/validation_accuracy.csv` and `test_accuracy.csv`: all nine comparisons.
- `results/forecast_means_by_model.csv`: compact forecast table for May-July 2025.
- `results/forecast_3_months_all_models.csv`: all 27 means with 80% and 95% prediction intervals.
- `results/evaluation_predictions.csv`: all 54 validation and test predictions.
- `results/model_structures.csv`, `model_parameters.csv` and `residual_diagnostics.csv`: model audit.
- `results/figures/`: history, ACF, STL, residual checks and individual model forecasts.

## Archived work

The former project layout was moved intact to `junk/previous-work/`, including
the newer CSV with the missing October 2025 observation, its three experimental
scripts, their outputs, and the earlier annual-analysis report and outline.
`MOVE_MANIFEST.csv` records the original locations and SHA-256 hashes of moved
files. The archive has its own copied project file and original input for recovery.
It is not part of the active workflow and is excluded from the clean project ZIP.
No files were deleted. The user's RStudio settings and Git history were kept in place.

The archived report uses an older evaluation design. Use the current result tables
and report outline when continuing the report.
