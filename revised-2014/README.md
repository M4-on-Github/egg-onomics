# Egg-onomics: revised 2014 study

This is the current working folder. Keep this file updated as the plan, code,
results or report changes. Last updated: **23 October 2026**.

## Current plan

Use data before 2014 for training, then split 2014 into two six-month periods.

| Use | Dates | Months |
| --- | --- | ---: |
| Training | January 1980-December 2013 | 408 |
| Validation | January-June 2014 | 6 |
| Test | July-December 2014 | 6 |
| Excluded from fitting and scoring | January 2015-April 2025 | 124 |

The source still contains all 544 monthly observations from January 1980 to
April 2025. Only the first 420 enter the analysis. No values are filled or
interpolated. January 2015 is the chosen cutoff, not a date estimated by a model.

Keep **one full 1980-2025 history graph** with vertical lines at January 2014,
July 2014 and January 2015. Later prices stay visible for context. Do not create
a separate zoomed data-split graph.

![Full egg-price history with data cuts](results/figures/00_history.png)

## Run the project

Open `egg-onomics.Rproj` in RStudio. Install the two R packages once if needed:

```r
install.packages(c("forecast", "jsonlite"))
```

Run the complete analysis:

```r
source("analysis/forecast.R")
```

Or, from this folder in a terminal:

```text
Rscript analysis/forecast.R
```

To update only the history graph and data-split metadata:

```r
Sys.setenv(EGG_PLOTS_ONLY = "1")
source("analysis/forecast.R")
Sys.unsetenv("EGG_PLOTS_ONLY")
```

The plot-only option does not refit models or rebuild the full results viewer.
Run the complete analysis after changing modeling settings or evaluation dates.
`EGG_DATA_FILE` and `EGG_FORECAST_OUTPUT` are optional overrides; leave them unset
to use this folder's own data and results.

## Folder guide

| File or folder | Purpose |
| --- | --- |
| `README.md` | Main plan, current status and work log |
| `egg-onomics.Rproj` | RStudio project |
| `analysis/forecast.R` | Import, splits, all nine models, evaluation and plots |
| `analysis/helpers.R` | Model functions, colors and the full-history cut graph |
| `analysis/viewer.R` | Builds the HTML results viewer |
| `data/APU0000708111.csv` | Original full input, kept unchanged |
| `results/index.html` | Open this for the current charts and tables |
| `results/figures/00_history.png` | The single full-history data-cut graph |
| `results/data_splits.csv` | Exact training, validation and test dates |
| `results/plot_cut_dates.csv` | The three vertical cut-line dates |
| `results/monthly_calendar.csv` | The 420 observations used by the analysis |
| `results/full_monthly_calendar.csv` | All 544 observations retained for context |
| `results/validation_accuracy.csv`, `results/test_accuracy.csv` | Current model comparisons |
| `results/evaluation_predictions.csv` | 108 predictions: nine models, two six-month windows |
| `results/forecast_6_months_all_models.csv` | January-June 2015 projections and intervals |
| `results/fitted_models.rds` | Saved models |
| `results/session_info.txt` | R and package versions from the last full run |
| `MANIFEST.csv` | SHA-256 hashes and sizes of the packaged files |

## Current results and status

- All nine R methods have been run on the revised split: SES, Holt, Damped Holt,
  Holt-Winters, Auto ETS, Naive, Seasonal naive, ARIMA and Seasonal ARIMA search.
- Naive has the lowest validation RMSE: **$0.054721 per dozen**. ARIMA is almost
  tied at **$0.054721**; the full-precision CSV values determine the selection.
- The validation-selected Naive model has test RMSE **$0.113400**. Seasonal ARIMA
  has the lowest observed test RMSE, **$0.070192**. That test ranking does not
  replace the validation choice.
- The January-June 2015 forecasts are saved projections only. Actual prices from
  those months are not used in fitting, selection or scoring.
- Split checks confirm 408/6/6 months. The original source-file MD5 is
  `bf246189cbf9d52a5da338e57f838d30`.
- The full-history graph and its three cut lines have been visually checked.
- Packaging checks passed: a complete run from the new folder, a detached
  plot-only run outside the old repository, and validation of source hashes,
  split dates, prediction counts and plot references.

The earlier neural-network, foundation-model and outbreak-comparison experiments
are outside this folder. Their settings, dates and scores do not describe this
revised study.

## Report

The [Google Docs report](https://docs.google.com/document/d/1Ww4--ggtK9WUdG6Yw6T0TQmVG8rBN-eF-vWENc38lqg/edit)
has been pruned. Use the revised dates and results above for subsequent report
work, and preserve the user's current report edits. Packaging this folder does
not change the online report.

## Work log

### 23 October 2026

- Changed the study to training before 2014, validation in the first six months
  of 2014, and testing in the last six months of 2014.
- Kept all source observations, but excluded post-2014 actuals from modeling.
- Put the three cut lines directly on the full 1980-2025 graph and removed the
  separate zoomed graph.
- Re-ran all nine R methods for the revised six-month windows.
- Packaged the current code, input and results in this self-contained folder.
  This README is now the main project note for further work.
