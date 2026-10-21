# Report and presentation work plan

This is a fill-in outline. Write the interpretation in your own words after
reviewing the code and computed evidence. Do not submit this outline as a report.

## 1. Question and data

- State the forecasting question and a practical decision it might support.
- Identify BLS/FRED series APU0000708111, unit, geography and monthly frequency.
- Give the saved date range and data-quality results.
- Explain why this is a historical exercise ending in April 2025.
- Add the source citation and your course's required disclosure of assistance.

Evidence: README source details, `data_quality.csv`, `01_history.png`.

## 2. Exploration

- Describe the long-run level pattern, large spikes and recent volatility.
- Interpret lag 1 and lag 12 in the training ACF.
- Compare level ACF with the ACF of monthly log changes.
- Explain STL seasonal strength and distinguish annual seasonality from a
  repeatable multi-year cycle. Avoid claiming a cycle from visual peaks alone.
- Explain the log transformation and whether its assumptions fit the data.

Evidence: `02_correlograms.png`, `03_decomposition.png`, `analysis_summary.txt`.

## 3. Methods and evaluation

- Explain the training/validation/test split and fixed-origin forecasts.
- Choose at least two smoothing methods to explain in detail; justify them using
  the exploration. The analysis includes five for comparison.
- Describe level, trend, damping and seasonality as relevant.
- Explain alpha/beta/gamma/phi using their actual fitted values.
- Explain why naive baselines are useful, even if not eligible for selection.
- Define RMSE and at least one complementary error measure in context.
- State that errors and forecast means are in dollars; smoothing residuals are
  log-price innovations.

Evidence: `data_splits.csv`, `model_parameters.csv`, `validation_accuracy.csv`.

## 4. Comparison and residuals

- Compare validation rankings under RMSE, MAE and MAPE; discuss near ties.
- Identify the locked smoothing choice and acknowledge the validation baseline.
- Describe the test results separately; do not change the locked choice merely
  because another model wins the test.
- Interpret each discussed model's residual time plot, histogram and ACF.
- Discuss remaining dependence, unusual residuals and changing spread.
- Explain what the approximate Ljung-Box results add to the visual evidence.
- Discuss observed 80% and 95% prediction-interval coverage.

Evidence: `04_validation.png`, `05_test.png`, residual PNGs,
`test_accuracy.csv`, `residual_diagnostics.csv`.

## 5. Forecast and usefulness

- Explain refitting the chosen specification on all saved observations.
- Give the ten forecast dates and selected estimates from the forecast table.
- Interpret the widening 80% and 95% prediction intervals.
- Explain why the small upward movement of SES means is a bias-adjustment effect.
- Connect forecast uncertainty to a concrete planning decision.
- Discuss what could invalidate the forecast and what additional data would help.
- Distinguish model-based prediction intervals from confidence intervals for a mean.

Evidence: `13_final_forecast.png`, `forecast_10_months.csv`.

## Individual presentation timing (target: 6 minutes)

| Time | Your content | Suggested evidence |
| --- | --- | --- |
| 0:00-0:40 | Question, source, units and saved date range | History plot |
| 0:40-1:30 | Trend, seasonality, shocks and ACF | ACF or STL plot |
| 1:30-2:20 | Two methods and evaluation design | Split table, model definitions |
| 2:20-3:35 | Model comparison and residual findings | Accuracy table, residual panels |
| 3:35-4:55 | Ten-month historical forecast and intervals | Final forecast plot |
| 4:55-6:00 | Reliability, practical decision and future data | Coverage and your interpretation |

Build your own slides around your explanation. Practice explaining why validation
and test winners differ, why a naive benchmark can win, what the log transformation
changes, and why 95% nominal coverage did not yield 95% observed test coverage.
