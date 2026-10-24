# Egg onomics

## Current working folder

Continue the revised study in **[revised-2014/](revised-2014/README.md)**.
Its README is the main Markdown file to keep updated. That folder contains the
current R code, original input, RStudio project and results in one portable place.
Open `revised-2014/egg-onomics.Rproj` to work on it.

The layout described below is retained as an earlier project snapshot. Use the
commands and result paths in the new folder's README for current work.

## Earlier project layout

The active workflow trains on January 1980-December 2013, validates on
January-June 2014, and tests on July-December 2014. All nine models use six-month
windows. Observations after December 2014 are excluded from modeling and scoring.
One full 1980-April 2025 history graph keeps all source observations visible and
marks the three data cuts with vertical lines. The original data file is unchanged.

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

4. Open `results/pre_2015/index.html` for the charts and tables, or `results/pre_2015/results.txt`
   for the plain-text summary.

Command line: `Rscript analysis/forecast.R`. RStudio Source also works when the
working directory is `analysis/`. `EGG_FORECAST_OUTPUT` optionally changes the
output directory.

To regenerate only the full-history graph and split metadata, set
`Sys.setenv(EGG_PLOTS_ONLY = "1")` before sourcing, then
`Sys.unsetenv("EGG_PLOTS_ONLY")` afterward. The graph is
`results/pre_2015/figures/00_history.png`; its cut lines mark January 2014,
July 2014 and January 2015. Earlier experiment outputs remain separate in `results/`.

## Folder guide

| Location | Purpose |
| --- | --- |
| `data/APU0000708111.csv` | Original unchanged input, January 1980-April 2025 |
| `analysis/forecast.R` | Main analysis: six-month validation and test in 2014 |
| `analysis/helpers.R` | Shared model, scoring and plotting functions and colors |
| `analysis/viewer.R` | HTML presentation of the current results |
| `results/pre_2015/` | Current generated charts, tables, fitted models and runtime details |
| `report/REPORT_OUTLINE.md` | Writing guide tied to the current analysis |
| `junk/previous-work/` | Archived experiments, 2026 data, old results and annual report draft |

## Data and evaluation

The input is BLS/FRED series APU0000708111, the U.S. city average price of large
Grade A eggs in nominal U.S. dollars per dozen, monthly and not seasonally
adjusted. Source: [FRED](https://fred.stlouisfed.org/series/APU0000708111).
There are 544 complete observations and no missing months or prices.

| Partition | Dates | Months |
| --- | --- | ---: |
| Training | January 1980-December 2013 | 408 |
| Validation | January-June 2014 | 6 |
| Test | July-December 2014 | 6 |
| Historical forecast (no actuals used) | January-June 2015 | 6 |

Methods: SES, Holt, Damped Holt, Holt-Winters, automatic ETS, naive, seasonal
naive, nonseasonal automatic ARIMA and seasonal automatic ARIMA. Smoothing and
ARIMA models fit log prices and return bias-adjusted dollar-scale means.
Benchmarks operate on original dollar prices. Validation RMSE selects the method
before the final-test scores are calculated. Every method is also refitted to
all 420 observations through December 2014 to produce its own six-month forecast.

The seasonal period remains 12 months even though the forecast horizon is six
months. Both evaluation windows are entirely in 2014. The January 2015 cutoff
is the chosen study boundary. All later actual prices remain visible only in
the full-history graph; they do not enter fitting, model selection or scoring.

## Useful output files

These current files are under `results/pre_2015/`:

- `data_quality.csv` and `data_splits.csv`: source hash, completeness and dates.
- `validation_accuracy.csv` and `test_accuracy.csv`: all nine comparisons.
- `forecast_means_by_model.csv`: compact forecast table for January-June 2015.
- `forecast_6_months_all_models.csv`: all 54 means with 80% and 95% prediction intervals.
- `evaluation_predictions.csv`: all 108 validation and test predictions.
- `model_structures.csv`, `model_parameters.csv` and `residual_diagnostics.csv`: model audit.
- `figures/00_history.png`: one full-history graph with the three data cuts.
- `monthly_calendar.csv`: 420 modeling observations; `full_monthly_calendar.csv`: all 544 for context.
- `individual_plot_manifest.csv`: all 36 individual graphs, ordered by
  method and stage for the report appendix. Each method has a validation plot,
  test plot, historical future forecast and training residual diagnostic panel.

## Gradient descent notebook

The notebooks and pre-spike study below retain the earlier experimental designs.
They have not been changed to the new 2014 validation/test split.

Open `analysis/gradient_descent.ipynb` in Jupyter or VS Code with a Python 3
kernel. It contains executed outputs, a NumPy implementation of gradient
descent, its learning curve, and validation, test and historical future
forecast plots. Python dependencies are listed in
`analysis/requirements-gradient-descent.txt`.

The model fits a log-price trend to the latest 24 months at each origin and
compares against naive forecasts over the same three-month evaluation dates.
Exponentiated predictions are unadjusted point forecasts, rather than the
bias-adjusted means from the R smoothing and ARIMA models. Its settings are fixed
across stages. Outputs go to `results/gradient_descent/`; the R analysis stays
separate. This notebook is an additional experiment, outside the nine-model R
comparison.

## Neural network notebook

Open `analysis/neural_network.ipynb` with a Python 3 kernel. It implements
12 log-price lag inputs, two hidden layers with 30 neurons and ReLU activations
each, and 16 softmax output probabilities for fixed half-dollar price ranges
from $0 to $8. The probability-weighted range centers give a dollar point
forecast, bounded by $0.25 and $7.75. It learns with Adam and cross-entropy.

The notebook contains executed results, training curves, three-month forecast
comparisons, and softmax probability plots. Its dates match the R experiment;
training examples and feature scaling use only history available at each origin.
The model recursively feeds its point forecasts into subsequent steps. Outputs,
weights and settings are in `results/neural_network/`; dependencies are listed
in `analysis/requirements-neural-network.txt`. This is a separate experiment
from the earlier log-trend regression and the nine-model R comparison.

## Direct three month neural forecasts

Open `analysis/direct_neural_network.ipynb` for the regression experiment with
12 monthly log changes as inputs, two 30-neuron ReLU layers, 10% dropout, and
three linear outputs. The outputs are cumulative log changes from the current
price. An exponential decoder converts them to positive dollar forecasts, and
training minimizes dollar MSE. All three months are predicted directly.

Eight combinations of training duration and weight decay are compared over
12 rolling origins whose targets end by October 2024. The best settings are
locked before the usual validation and test periods are scored. This provides
a comparison with the earlier softmax classifier and naive baseline. Results,
selection details, rolling predictions and weights are saved separately under
`results/direct_neural_network/`. Dependencies are the same as for the softmax
notebook. The previously inspected test remains an exploratory comparison.

## Forecasts frozen before the spikes

Run `Rscript analysis/spike_counterfactual.R`, then open
`results/spike_counterfactual/index.html`. The executed Python notebook
`analysis/spike_counterfactual.ipynb` explains the design and displays the results.
It reads the R outputs; set `RECOMPUTE = True` in its first code cell to refit.
It needs the existing R packages plus Python `matplotlib` and `ipykernel`.

This separate experiment freezes a 12-month forecast at November 2014, January
2022, and September 2024, before documented HPAI outbreak periods. At each
origin, six disjoint earlier 12-month validation blocks choose among all nine R
methods; neither fitting nor selection uses later prices. Each model is fitted
to all available history from January 1980. Forecasts are not updated during the
event. Both first-three-month accuracy and the longer observed departures are
reported. Only seven of the final event's 12 months are observed in our snapshot;
the other five actuals remain unavailable, without interpolation.

The resulting baseline is a continuation of earlier patterns, **not an identified
price path without HPAI**. Actual-minus-baseline gaps include other influences.
In particular, September 2024 already contains previous outbreaks and price
increases, so it is only a baseline before the later wave. The 2014–15 outbreak
is labeled HPAI rather than implying every historical outbreak was H5N1.
Event dates and primary-source links are in `analysis/spike_events.csv`.

Outputs include 324 frozen forecasts with 80%/95% model prediction intervals,
27 individual model plots, three selected-model comparisons and gap plots,
pre-event validation predictions, all-model summaries, calendar leakage audits,
saved fitted models, and sensitivity forecasts from one and three months earlier.
The earlier-origin sensitivity reselects using the five fully available earlier
validation blocks. These retrospective cases are exploratory; they are not
independent causal estimates or evidence of a new forecasting accuracy gain.

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
