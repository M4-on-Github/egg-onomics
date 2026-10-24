# Report writing guide

## Current data split (revised)

Use `results/pre_2015/` for the current R study. Training is January 1980-December
2013 (408 months), validation is January-June 2014 (6 months), and testing is
July-December 2014 (6 months). All later actuals are excluded from modeling and
scoring. `figures/00_history.png` retains the full 1980-April 2025 history with
vertical lines at January 2014, July 2014 and January 2015. There is no separate
zoomed split graph. The future-forecast table is `forecast_6_months_all_models.csv`.

The older writing guide below describes the previous experiment and is retained
as reference; its evaluation dates and scores do not describe the revised study.

Use the current `results/` folder. The previous annual report draft is archived
in `junk/previous-work/report/`; its numerical comparisons are not the current
three-month analysis.

## Dataset

- State the question: how accurately can historical monthly egg prices forecast
  the next three months?
- Cite BLS/FRED series APU0000708111. Units are nominal U.S. dollars per dozen.
- Give the original January 1980-April 2025 date range and 544 complete observations.
- Explain that the analysis uses observed data without filling or interpolation.
- Interpret `figures/00_history.png`, `00_training_acf.png` and `00_training_stl.png`.
  Distinguish persistent price levels, annual dependence and irregular shocks.

## Forecasting Methods

- Describe the training window through October 2024, validation in November
  2024-January 2025, and testing in February-April 2025.
- Explain at least two methods in detail and include the naive benchmarks.
- Explain why smoothing and ARIMA use log prices and bias-adjusted means.
- Use `model_structures.csv` and `model_parameters.csv` for actual estimates.
- Explain that validation RMSE selects the method before test evaluation.

## Comparison

- Compare `validation_accuracy.csv` and `test_accuracy.csv`; keep validation and
  test rankings separate.
- Explain RMSE, MAE, MAPE and the direction of mean error in dollars per dozen.
- Discuss remaining dependence and large residuals using
  `residual_diagnostics.csv` and the individual residual figures.
- Interpret the early-2025 shock and observed interval coverage.
- Three test months provide limited evidence of performance in other periods.

## Forecast

- Present the May-July 2025 historical forecasts from
  `forecast_means_by_model.csv` and the complete interval table in
  `forecast_3_months_all_models.csv`.
- Use the selected method's `future_*.png` figure, with its 80% and 95% prediction
  intervals. Distinguish those intervals from confidence intervals for a mean.
- Explain uncertainty, potential budgeting uses and what additional data could help.
- Keep the three-month horizon distinct from the 12-month seasonal period.

Write and review the report in your own words and apply the course requirements
for permitted assistance and disclosure.

## Appendix

- Include the 36 graphs listed in `results/individual_plot_manifest.csv`, grouped
  by method. For each of the nine methods, show validation, test, the May-July
  2025 historical forecast and training residual diagnostics.
- Forecast panels include 80% and 95% prediction intervals. Validation and test
  panels also include held-out actual prices. Prediction lines connect to the
  last observed price at their origin.
- Residual panels use the original training window through October 2024.
