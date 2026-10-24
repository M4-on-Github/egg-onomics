# Helpers for the final two-model study only.
# Sourced locally by final_two_models.R; output helpers use its out and FIG paths.
# Data passed to plotting and scoring functions is explicit.

LEVELS <- c(80, 95)
HISTORY_COLOR <- "#172554"
BAND_80 <- "#93c5fd"
BAND_95 <- "#dbeafe"
ACTUAL_COLOR <- "#c2410c"

# ---- Saving tables and figures ----
save_csv <- function(d, name) {
  write.csv(d, file.path(out, paste0(name, ".csv")), row.names = FALSE)
}

figure <- function(name, draw, height = 1000L, width = 1600L) {
  png(file.path(FIG, paste0(name, ".png")), width = width, height = height, res = 150)
  on.exit(dev.off())
  par(
    mar = c(5, 5, 4, 1), las = 1, family = "sans", col.main = HISTORY_COLOR,
    col.axis = "#334155", col.lab = HISTORY_COLOR, fg = "#334155", bg = "white"
  )
  draw()
}


# ---- Model fitting and forecast accuracy ----
fit_damped_holt <- function(y) {
  forecast::ets(y, model = "AAN", damped = TRUE)
}

forecast_model <- function(fit, h) {
  forecast::forecast(fit, h = h, level = LEVELS)
}

search_arima <- function(y) {
  forecast::auto.arima(y,
    seasonal = TRUE, ic = "aicc", stepwise = TRUE,
    approximation = FALSE, method = "ML", trace = FALSE
  )
}
describe_fit <- function(fit) {
  if (inherits(fit, "Arima")) {
    a <- fit$arma
    label <- paste0("ARIMA(", a[1], ",", a[6], ",", a[2], ")")
    if (any(a[c(3, 4, 7)] > 0)) label <- paste0(label, "(", a[3], ",", a[7], ",", a[4], ")[", a[5], "]")
    if ("drift" %in% names(fit$coef)) label <- paste(label, "with drift")
    if ("intercept" %in% names(fit$coef)) label <- paste(label, "with mean")
    return(label)
  }
  fit$method
}

accuracy_measures <- function(actual, predicted, mase_scale) {
  e <- actual - predicted
  data.frame(
    ME = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
    MAPE = 100 * mean(abs(e / actual)), MASE = mean(abs(e)) / mase_scale
  )
}

# ---- Plot helpers ----
slug <- function(model) gsub(" ", "_", tolower(model))
month_label <- function(dates) paste(format(min(dates), "%b %Y"), "to", format(max(dates), "%b %Y"))

# Convert to numeric so every ACF uses explicit MONTH lags, not ts year units.
draw_acf <- function(y, heading, max_lag = 36L, color = "#2563eb") {
  acf(as.numeric(y),
    lag.max = max_lag, main = heading, xlab = "Lag in months",
    col = color, lwd = 2
  )
}

draw_pacf <- function(y, heading, max_lag = 48L, color = "#2563eb") {
  pacf(as.numeric(y),
    lag.max = max_lag, main = heading, xlab = "Lag in months",
    ylab = "Partial ACF", col = color, lwd = 2
  )
}

draw_fan <- function(fc, model_data, origin_n, h, color, label, heading, history_from,
                     actual = NULL, unscored_from = NULL) {
  dates <- seq(model_data$date[origin_n], by = "month", length.out = h + 1L)[-1L]
  past <- which(model_data$date >= as.Date(history_from) & seq_len(nrow(model_data)) <= origin_n)
  mean_h <- as.numeric(fc$mean)[seq_len(h)]
  lo80 <- as.numeric(fc$lower[, "80%"])[seq_len(h)]
  hi80 <- as.numeric(fc$upper[, "80%"])[seq_len(h)]
  lo95 <- as.numeric(fc$lower[, "95%"])[seq_len(h)]
  hi95 <- as.numeric(fc$upper[, "95%"])[seq_len(h)]
  anchor_date <- model_data$date[origin_n]
  anchor <- model_data$price[origin_n]
  y_range <- range(model_data$price[past], lo95, hi95, actual$price)
  y_range[2] <- y_range[2] + .12 * diff(y_range) # room for the legend
  plot(range(model_data$date[past], dates), y_range,
    type = "n", xlab = "Month",
    ylab = "U.S. dollars per dozen", main = heading
  )
  if (!is.null(unscored_from)) {
    u <- par("usr")
    rect(unscored_from, u[3], u[2], u[4], col = "#f1f5f9", border = NA)
  }
  band_dates <- c(anchor_date, dates)
  polygon(c(band_dates, rev(band_dates)), c(anchor, lo95, rev(c(anchor, hi95))), col = BAND_95, border = NA)
  polygon(c(band_dates, rev(band_dates)), c(anchor, lo80, rev(c(anchor, hi80))), col = BAND_80, border = NA)
  lines(model_data$date[past], model_data$price[past], col = HISTORY_COLOR, lwd = 2)
  lines(band_dates, c(anchor, mean_h), col = color, lwd = 2.5)
  abline(v = anchor_date, col = "#64748b", lty = 2)
  if (!is.null(actual)) {
    lines(c(anchor_date, actual$date), c(anchor, actual$price), col = ACTUAL_COLOR, lwd = 2)
    if (nrow(actual) <= 24L) points(actual$date, actual$price, pch = 16, col = ACTUAL_COLOR)
  }
  legend("topleft", c(
    "Observed", label, "80% interval", "95% interval",
    if (!is.null(actual)) "Actual", if (!is.null(unscored_from)) "No actuals"
  ),
  col = c(
    HISTORY_COLOR, color, BAND_80, BAND_95, if (!is.null(actual)) ACTUAL_COLOR,
    if (!is.null(unscored_from)) "#f1f5f9"
  ),
  lwd = c(2, 2.5, 8, 8, if (!is.null(actual)) 2, if (!is.null(unscored_from)) 8), bty = "n", cex = .8,
  ncol = if (h > 24L) 1 else 2
  )
}

# ---- Purchasing-power comparison (never used to fit a model) ----
compare_inflation <- function(full, forecast_table, cpi, better) {
  stopifnot(
    nrow(cpi) == 2L, all(cpi$series_id == "CUUR0000SA0"),
    all(cpi$index_base == "1982-1984=100"), all(is.finite(cpi$cpi)), all(cpi$cpi > 0),
    identical(cpi$period, c("1980", "2026-09")),
    identical(cpi$aggregation, c("Annual average", "Monthly observation"))
  )
  price_1980 <- mean(full$price[format(full$date, "%Y") == "1980"])
  forecast_2026 <- forecast_table$mean[format(forecast_table$date, "%Y") == "2026"]
  stopifnot(
    length(forecast_2026) == 12L,
    !any(forecast_table$scored[format(forecast_table$date, "%Y") == "2026"])
  )
  inflation_factor <- cpi$cpi[2] / cpi$cpi[1]
  adjusted_1980 <- price_1980 * inflation_factor
  data.frame(
    model = better, actual_year = 1980L,
    actual_months = 12L, actual_nominal_mean = price_1980, forecast_year = 2026L,
    forecast_months = length(forecast_2026), forecast_nominal_mean = mean(forecast_2026),
    cpi_series = cpi$series_id[1], base_cpi_period = cpi$period[1], base_cpi = cpi$cpi[1],
    benchmark_cpi_period = cpi$period[2], benchmark_cpi = cpi$cpi[2],
    inflation_factor = inflation_factor, actual_1980_in_benchmark_dollars = adjusted_1980,
    forecast_difference_pct = 100 * (mean(forecast_2026) / adjusted_1980 - 1),
    provisional = TRUE,
    note = paste(
      "1980 annual-average price adjusted to Sep 2026 purchasing power;",
      "2026 value is a mean forecast, not an actual price; CPI benchmark is not the 2026 annual average"
    )
  )
}

# ---- Output catalog ----
# Keep each output path, description and assignment task together.
final_output_catalog <- function() {
  entry <- function(file, contents, pdf_task) {
    data.frame(file = file, contents = contents, pdf_task = pdf_task)
  }
  do.call(rbind, list(
    entry("data_check.csv", "Completeness checks of the source file and the month counts per split", "Task 2"),
    entry("exploration_summary.csv", "Training-data exploration numbers: ACF/PACF values, STL strengths, peak and trough months, ndiffs", "Task 2"),
    entry("exploration_by_decade.csv", "Mean price and monthly-change spread by decade (training data)", "Task 2 / Task 6 confidence"),
    entry("accuracy_table.csv", "ME, MAE, RMSE, MAPE, MASE and interval coverage: 2014 test and one-step training fit", "Task 3 / Task 4"),
    entry("test_predictions_2014.csv", "Each 2014 test month: actual, both forecasts, errors and 80%/95% intervals", "Task 3"),
    entry("test_accuracy_by_half_year.csv", "Same 2014 test forecasts scored on Jan-Jun and Jul-Dec separately", "Task 4"),
    entry("better_model.csv", "The better model, the stated tie rule and which measures each model won", "Task 4"),
    entry("residual_diagnostics.csv", "Residual mean, sd, skewness, kurtosis, ACF at lags 1/12/24 and Ljung-Box tests", "Task 3 / Task 4"),
    entry("residual_sd_by_decade.csv", "Residual sd by decade for each model (training fit)", "Task 6 confidence"),
    entry("model_structures.csv", "Model form, fit window, log-likelihood, AIC/AICc/BIC and sigma for each fit", "Task 3 parameters"),
    entry("model_parameters.csv", "Estimated parameters (alpha, beta, phi; AR coefficients with standard errors)", "Task 3 / Task 5 parameters"),
    entry("better_forecast_6_months.csv", "Better model, Jan-Jun 2015 forecast and intervals, with post-hoc actuals", "Task 5"),
    entry("better_forecast_12_months.csv", "Better model, Jan-Dec 2015 forecast and intervals, with post-hoc actuals", "Task 5"),
    entry("better_forecast_144_months.csv", "Better model, Jan 2015-Dec 2026; months after Apr 2025 are marked unscored", "Task 5"),
    entry("gap_summary.csv", "Post-hoc gap at 6, 12 and 124 months (ME, MAE, RMSE, MAPE, coverage); 20 months unscored", "Task 6 confidence"),
    entry("gap_by_year.csv", "Post-hoc gap by calendar year 2015-2025 (2025 = Jan-Apr)", "Task 6 confidence"),
    entry("sensitivity_other_test_years.csv", "Context only: both models re-run with test years 2005-2014 (not used to choose)", "Task 4 caveat"),
    entry("leakage_checks.csv", "Assertions that no 2014 value entered the test fits and no post-2014 value entered any fit", "Method integrity"),
    entry("results.txt", "Plain-text summary of the main tables", "All"),
    entry("session_info.txt", "R and package versions", "Reproducibility"),
    entry("fitted_models.rds", "Saved model objects (readRDS)", "Reproducibility"),
    entry("file_guide.csv", "This file", "Index"),
    entry("figures/01_history_with_cuts.png", "Full 1980-2025 price history with the test year and post-hoc period marked", "Task 2"),
    entry("figures/02_correlogram.png", "ACF and PACF of training prices and of monthly price changes", "Task 2"),
    entry("figures/03_stl_decomposition.png", "STL decomposition of training prices", "Task 2"),
    entry("figures/04_seasonal_by_month.png", "Month-by-year view and average seasonal effect", "Task 2"),
    entry("figures/05_residuals_damped_holt.png", "Damped Holt training residuals: time plot, histogram, ACF, Q-Q", "Task 3"),
    entry("figures/05_residuals_seasonal_arima.png", "Seasonal ARIMA training residuals: time plot, histogram, ACF, Q-Q", "Task 3"),
    entry("figures/06_test_forecast_damped_holt.png", "Damped Holt 2014 test forecast with intervals and the test data", "Task 3"),
    entry("figures/06_test_forecast_seasonal_arima.png", "Seasonal ARIMA 2014 test forecast with intervals and the test data", "Task 3"),
    entry("figures/07_test_comparison.png", "Both 2014 test forecasts and monthly errors on one figure", "Task 4"),
    entry("figures/08_accuracy_comparison.png", "Bar chart of the 2014 error measures for both models", "Task 4"),
    entry("figures/09_better_forecast_6_months.png", "Better model forecast with intervals and post-hoc actuals: 6 months", "Task 5 / Task 6"),
    entry("figures/10_better_forecast_12_months.png", "Better model forecast with intervals and post-hoc actuals: 12 months", "Task 5 / Task 6"),
    entry("figures/11_better_forecast_144_months.png", "Better model forecast with intervals and post-hoc actuals: 144 months", "Task 5 / Task 6"),
    entry("figures/09_better_forecast_6_months_clean.png", "Better model forecast with intervals, no actuals: 6 months", "Task 5 / Task 6"),
    entry("figures/10_better_forecast_12_months_clean.png", "Better model forecast with intervals, no actuals: 12 months", "Task 5 / Task 6"),
    entry("figures/11_better_forecast_144_months_clean.png", "Better model forecast with intervals, no actuals: 144 months", "Task 5 / Task 6"),
    entry("figures/12_gap_by_year.png", "Signed post-hoc gap by year", "Task 6 confidence"),
    entry("report_final_forecast_2015.csv", "Main 12-month forecast with fitting dates and intervals; contains no post-2014 actuals", "Task 5"),
    entry("report_model_parameters.csv", "Key parameters and meanings for both training fits and the selected final refit", "Task 3 / Task 5 parameters"),
    entry("inflation_comparison.csv", "Reproducible 1980 versus forecast-2026 comparison using a provisional Sep 2026 CPI benchmark", "Extra: inflation comparison"),
    entry("figures/13_final_forecast_2015.png", "Main Task 5 forecast for Jan-Dec 2015 with prediction intervals and no later actual prices", "Task 5"),
    entry("figures/14_inflation_comparison.png", "1980 average price in Sep 2026 dollars versus the 2026 average forecast; provisional", "Extra: inflation comparison")
  ))
}
