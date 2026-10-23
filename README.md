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
- `results/individual_plot_manifest.csv`: all 36 individual graphs, ordered by
  method and stage for the report appendix. Each method has a validation plot,
  test plot, historical future forecast and training residual diagnostic panel.

## Gradient descent notebook

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
