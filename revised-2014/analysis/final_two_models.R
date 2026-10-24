# Training Jan 1980-Dec 2013 (408 months). Test Jan-Dec 2014 (12 months). No validation set.
# predict 6, 12 and 144 months ahead (Jan 2015-Dec 2026).

run_final_two_models <- function() {
  # Project paths and helpers
  source_files <- unlist(lapply(sys.frames(), function(fr) {
    if (!is.null(fr$ofile)) as.character(fr$ofile) else character()
  }))
  cli <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  candidates <- c(rev(source_files), cli)
  candidates <- candidates[file.exists(candidates)]
  root <- NULL
  for (start in c(dirname(candidates), getwd())) {
    for (path in c(start, dirname(start))) {
      if (file.exists(file.path(path, "egg-onomics.Rproj"))) {
        root <- normalizePath(path, winslash = "/")
        break
      }
    }
    if (!is.null(root)) break
  }
  if (is.null(root)) stop("Run the saved script from the egg-onomics project.")
  if (!requireNamespace("forecast", quietly = TRUE)) {
    stop("Install the forecast package before running this script.", call. = FALSE)
  }
  out <- Sys.getenv("EGG_FINAL_OUTPUT", unset = file.path(root, "results", "final_two_models"))
  INPUT <- Sys.getenv("EGG_DATA_FILE", unset = file.path(root, "data", "APU0000708111.csv"))
  FIG <- file.path(out, "figures")
  dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
  source(file.path(root, "analysis", "final_helpers.R"), local = TRUE)

  # ---- Study settings ----------------------------------------------------
  TRAIN_END <- as.Date("2013-12-01") # last month the test-stage fits may see
  DATA_END <- as.Date("2014-12-01") # last month ANY fit may see
  N_TRAIN <- 408L
  N_TEST <- 12L
  H_SHORT <- 6L
  H_YEAR <- 12L
  H_LONG <- 144L # Jan 2015-Dec 2026
  MODELS <- c("Damped Holt", "Seasonal ARIMA")
  MODEL_COLORS <- c("Damped Holt" = "#0d9488", "Seasonal ARIMA" = "#7c3aed")
  MODEL_LTY <- c("Damped Holt" = 2, "Seasonal ARIMA" = 1)
  EXPECTED_ORDER <- "ARIMA(1,1,0)(2,0,0)[12]" # what earlier runs found; checked below

  # ---- Import and validate the data --------------------------------------
  raw <- read.csv(INPUT, stringsAsFactors = FALSE)
  stopifnot(identical(names(raw), c("observation_date", "APU0000708111")))
  full <- data.frame(date = as.Date(raw$observation_date), price = as.numeric(raw$APU0000708111))
  expected_months <- seq(as.Date("1980-01-01"), as.Date("2025-04-01"), by = "month")
  stopifnot(
    nrow(full) == 544L, !anyNA(full), !anyDuplicated(full$date),
    all(is.finite(full$price)), all(full$price > 0), identical(full$date, expected_months)
  )
  # Only these 420 months (Jan 1980-Dec 2014) are ever passed to a model.
  # The later months stay in `full` for the history plot and the post-hoc gap section.
  model_data <- full[full$date <= DATA_END, ]
  series <- ts(model_data$price, start = c(1980, 1), frequency = 12)
  train_y <- window(series, end = c(2013, 12))
  train_dates <- model_data$date[seq_len(N_TRAIN)]
  test_id <- seq.int(N_TRAIN + 1L, N_TRAIN + N_TEST)
  test_dates <- model_data$date[test_id]
  test_actual <- model_data$price[test_id]
  stopifnot(
    nrow(model_data) == 420L, length(train_y) == N_TRAIN, max(train_dates) == TRAIN_END,
    identical(test_dates, seq(as.Date("2014-01-01"), DATA_END, by = "month"))
  )
  in_window <- function(lo, hi) model_data$date >= as.Date(lo) & model_data$date <= as.Date(hi)
  data_check <- data.frame(
    item = c(
      "Series", "Units", "Rows in source file", "First month",
      "Last month", "Missing months in the monthly sequence", "Missing or non-numeric prices",
      "Duplicate dates", "Non-positive prices", "Imputed or filled values",
      "Months available to models (Jan 1980-Dec 2014)", "Training months (Jan 1980-Dec 2013)",
      "Test months (Jan-Dec 2014)", "Months kept for post-hoc comparison only (Jan 2015-Apr 2025)",
      "Training price range ($)", "Test-year price range ($)", "Post-hoc price range ($)",
      "Source file MD5"
    ),
    value = c(
      "BLS average price APU0000708111: eggs, grade A, large, per dozen, U.S. city average",
      "U.S. dollars per dozen, monthly", nrow(full), format(min(full$date)), format(max(full$date)),
      length(setdiff(expected_months, full$date)), sum(is.na(raw$APU0000708111)),
      sum(duplicated(full$date)), sum(full$price <= 0), 0, nrow(model_data), N_TRAIN, N_TEST,
      sum(full$date > DATA_END),
      paste(sprintf("%.3f", range(train_y)), collapse = " to "),
      paste(sprintf("%.3f", range(test_actual)), collapse = " to "),
      paste(sprintf("%.3f", range(full$price[full$date > DATA_END])), collapse = " to "),
      unname(tools::md5sum(INPUT))
    )
  )
  save_csv(data_check, "data_check")


  # ---- Explore training prices (1980-2013) -------------------------------
  # One full-history plot keeps the later prices visible for context, with the cuts marked.
  test_start <- as.Date("2014-01-01")
  posthoc_start <- as.Date("2015-01-01")
  figure("01_history_with_cuts", function() {
    plot(full$date, full$price,
      type = "n", xlab = "Month", ylab = "U.S. dollars per dozen",
      main = "Egg price, Jan 1980-Apr 2025"
    )
    lines(full$date, full$price, col = HISTORY_COLOR, lwd = 2)
    abline(v = c(test_start, posthoc_start), col = c("#0f766e", "#dc2626"), lty = c(3, 4), lwd = 2)
    legend("topleft", c("Observed price", "Jan 2014", "Jan 2015"),
      col = c(HISTORY_COLOR, "#0f766e", "#dc2626"),
      lty = c(1, 3, 4), lwd = 2, bty = "n", cex = .85
    )
  })
  train_change <- diff(train_y)
  figure("02_correlogram", function() {
    par(mfrow = c(2, 2), mar = c(4.5, 4.5, 3, 1))
    draw_acf(train_y, "ACF of price", 48L)
    draw_pacf(train_y, "PACF of price")
    draw_acf(train_change, "ACF of price change", 48L, "#0f766e")
    draw_pacf(train_change, "PACF of price change", 48L, "#0f766e")
  }, height = 1200L)
  stl_fit <- stl(train_y, s.window = "periodic", robust = TRUE)
  parts <- stl_fit$time.series
  seasonal_strength <- max(0, 1 - var(parts[, "remainder"]) / var(parts[, "seasonal"] + parts[, "remainder"]))
  trend_strength <- max(0, 1 - var(parts[, "remainder"]) / var(parts[, "trend"] + parts[, "remainder"]))
  # A periodic seasonal is identical every year; training starts in January.
  seasonal_by_month <- setNames(as.numeric(parts[1:12, "seasonal"]), month.abb)
  figure("03_stl_decomposition", function() {
    par(mfrow = c(4, 1), mar = c(2, 5, 2, 1), oma = c(3, 0, 2, 0))
    plot(train_dates, as.numeric(train_y),
      type = "l", col = HISTORY_COLOR, lwd = 1.5,
      xlab = "", ylab = "Price ($/dozen)", main = "Observed price"
    )
    plot(train_dates, as.numeric(parts[, "trend"]),
      type = "l", col = "#2563eb", lwd = 2,
      xlab = "", ylab = "Trend ($/dozen)", main = "Trend"
    )
    plot(train_dates, as.numeric(parts[, "seasonal"]),
      type = "l", col = "#0f766e", lwd = 1.5,
      xlab = "", ylab = "Seasonal ($/dozen)", main = "Seasonal"
    )
    abline(h = 0, lty = 2, col = "#64748b")
    plot(train_dates, as.numeric(parts[, "remainder"]),
      type = "h", col = "#64748b",
      xlab = "", ylab = "Remainder ($/dozen)", main = "Remainder"
    )
    abline(h = 0)
    mtext("Month", side = 1, outer = TRUE, line = 1.2, col = HISTORY_COLOR)
    mtext("STL decomposition", side = 3, outer = TRUE, line = .5, font = 2, col = HISTORY_COLOR)
  }, height = 1500L)
  figure("04_seasonal_by_month", function() {
    par(mfrow = c(1, 2), mar = c(4.5, 5, 3, 1))
    # monthplot() mishandles col/main passed through `...`; set the line color with par()
    # and add the titles separately.
    par(col = HISTORY_COLOR)
    monthplot(train_y,
      labels = month.abb, ylab = "U.S. dollars per dozen",
      col.base = ACTUAL_COLOR, lwd.base = 2
    )
    par(col = "#334155")
    title(main = "Price by calendar month", xlab = "Calendar month")
    bars <- barplot(100 * seasonal_by_month,
      names.arg = month.abb, border = NA, las = 2,
      col = ifelse(seasonal_by_month >= 0, BAND_80, "#fdba74"),
      ylim = 100 * range(seasonal_by_month) * 1.25, xlab = "Calendar month",
      ylab = "Seasonal effect (cents per dozen)",
      main = "Seasonal effect by month"
    )
    abline(h = 0, col = "#334155")
    text(bars, 100 * seasonal_by_month, sprintf("%.1f", 100 * seasonal_by_month),
      pos = ifelse(seasonal_by_month >= 0, 3, 1), cex = .7
    )
  })
  # Price level and monthly-change spread by decade: the dollar spread grows with the level.
  decades <- list(
    "1980-1989" = c("1980-01-01", "1989-12-01"), "1990-1999" = c("1990-01-01", "1999-12-01"),
    "2000-2009" = c("2000-01-01", "2009-12-01"), "2010-2013" = c("2010-01-01", "2013-12-01")
  )
  change_all <- c(NA, diff(model_data$price))
  by_decade <- do.call(rbind, lapply(names(decades), function(k) {
    keep <- in_window(decades[[k]][1], decades[[k]][2]) & !is.na(change_all)
    data.frame(
      period = k, months = sum(in_window(decades[[k]][1], decades[[k]][2])),
      mean_price = mean(model_data$price[in_window(decades[[k]][1], decades[[k]][2])]),
      sd_monthly_change = sd(change_all[keep]),
      sd_change_as_pct_of_mean_price = 100 * sd(change_all[keep]) /
        mean(model_data$price[in_window(decades[[k]][1], decades[[k]][2])])
    )
  }))
  save_csv(by_decade, "exploration_by_decade")
  acf_level <- as.numeric(acf(as.numeric(train_y), lag.max = 48L, plot = FALSE)$acf)
  acf_change <- as.numeric(acf(as.numeric(train_change), lag.max = 48L, plot = FALSE)$acf)
  pacf_change <- as.numeric(pacf(as.numeric(train_change), lag.max = 48L, plot = FALSE)$acf)
  exploration <- data.frame(
    measure = c(
      "training_months", "training_mean_price", "training_min_price",
      "training_min_month", "training_max_price", "training_max_month",
      "acf_price_lag1", "acf_price_lag12", "acf_price_lag24", "acf_price_lag48",
      "acf_change_lag1", "acf_change_lag12", "acf_change_lag24", "pacf_change_lag1",
      "pacf_change_lag12", "pacf_change_lag24", "acf_95pct_bound_change",
      "stl_seasonal_strength", "stl_trend_strength", "stl_seasonal_range_cents",
      "stl_peak_month", "stl_trough_month", "kpss_ndiffs", "seasonal_nsdiffs"
    ),
    value = c(
      N_TRAIN, mean(train_y), min(train_y), format(train_dates[which.min(train_y)], "%b %Y"),
      max(train_y), format(train_dates[which.max(train_y)], "%b %Y"),
      acf_level[c(2, 13, 25, 49)], acf_change[c(2, 13, 25)], pacf_change[c(1, 12, 24)],
      1.96 / sqrt(length(train_change)), seasonal_strength, trend_strength,
      100 * diff(range(seasonal_by_month)), names(which.max(seasonal_by_month)),
      names(which.min(seasonal_by_month)), forecast::ndiffs(train_y), forecast::nsdiffs(train_y)
    ),
    note = c(
      "Jan 1980-Dec 2013", "$ per dozen", "$ per dozen", "", "$ per dozen", "",
      "slow decay = trend / non-stationary level", "", "", "",
      "after first differencing", "seasonal spike check", "seasonal spike check",
      "", "", "", "approximate +/- bound for one ACF lag",
      "1 - var(R)/var(S+R); 0 = none, 1 = strong", "1 - var(R)/var(T+R)",
      "peak-to-trough of the average seasonal effect", "", "",
      "number of first differences suggested by KPSS (used by auto.arima)",
      "number of seasonal differences suggested (used by auto.arima)"
    )
  )
  save_csv(exploration, "exploration_summary")

  # ---- Fit both models through December 2013 -----------------------------
  test_fits <- list(
    "Damped Holt" = fit_damped_holt(train_y),
    "Seasonal ARIMA" = search_arima(train_y)
  )
  # Fix the order the search found on the training data. Later refits re-estimate the
  # coefficients for this order but do not search again.
  arima_found <- describe_fit(test_fits[["Seasonal ARIMA"]])
  arima_order <- forecast::arimaorder(test_fits[["Seasonal ARIMA"]])
  arima_seasonal <- if (length(arima_order) > 3L) arima_order[4:6] else c(0L, 0L, 0L)
  arima_drift <- "drift" %in% names(coef(test_fits[["Seasonal ARIMA"]]))
  arima_mean <- "intercept" %in% names(coef(test_fits[["Seasonal ARIMA"]]))
  if (arima_found != EXPECTED_ORDER) {
    warning("Training search found ", arima_found, " (earlier runs: ", EXPECTED_ORDER,
      "). Re-check the guide's numbers.",
      call. = FALSE
    )
  }
  refit_arima <- function(y) {
    forecast::Arima(y,
      order = arima_order[1:3], seasonal = list(order = arima_seasonal, period = 12),
      include.mean = arima_mean, include.drift = arima_drift, method = "ML"
    )
  }
  cat("Seasonal ARIMA order fixed from the training search:", arima_found, "\n")
  test_fc <- lapply(test_fits, forecast_model, h = N_TEST)

  # ---- Evaluate the 2014 forecasts ---------------------------------------
  # MASE scale: in-sample mean absolute seasonal-naive error on the training data.
  mase_scale <- mean(abs(diff(as.numeric(train_y), lag = 12L)))
  test_predictions <- do.call(rbind, lapply(MODELS, function(m) {
    fc <- test_fc[[m]]
    data.frame(
      model = m, date = test_dates, horizon = seq_len(N_TEST), actual = test_actual,
      forecast = as.numeric(fc$mean), error = test_actual - as.numeric(fc$mean),
      pct_error = 100 * (test_actual - as.numeric(fc$mean)) / test_actual,
      lower80 = as.numeric(fc$lower[, "80%"]), upper80 = as.numeric(fc$upper[, "80%"]),
      lower95 = as.numeric(fc$lower[, "95%"]), upper95 = as.numeric(fc$upper[, "95%"]),
      row.names = NULL
    )
  }))
  test_predictions$in80 <- with(test_predictions, actual >= lower80 & actual <= upper80)
  test_predictions$in95 <- with(test_predictions, actual >= lower95 & actual <= upper95)
  save_csv(test_predictions, "test_predictions_2014")
  test_scores <- do.call(rbind, lapply(MODELS, function(m) {
    z <- test_predictions[test_predictions$model == m, ]
    cbind(data.frame(model = m, set = "Test: Jan-Dec 2014 (12 months ahead from Dec 2013)"),
      accuracy_measures(z$actual, z$forecast, mase_scale),
      Coverage80 = mean(z$in80), Coverage95 = mean(z$in95),
      months = nrow(z)
    )
  }))
  train_scores <- do.call(rbind, lapply(MODELS, function(m) {
    cbind(data.frame(model = m, set = "Training: one-step-ahead fit, Jan 1980-Dec 2013"),
      accuracy_measures(as.numeric(train_y), as.numeric(fitted(test_fits[[m]])), mase_scale),
      Coverage80 = NA_real_, Coverage95 = NA_real_, months = N_TRAIN
    )
  }))
  save_csv(rbind(test_scores, train_scores), "accuracy_table")
  halves <- list(
    "Jan-Jun 2014 (horizons 1-6)" = 1:6, "Jul-Dec 2014 (horizons 7-12)" = 7:12,
    "Full year 2014 (horizons 1-12)" = 1:12
  )
  by_half <- do.call(rbind, lapply(names(halves), function(k) {
    do.call(rbind, lapply(MODELS, function(m) {
      z <- test_predictions[test_predictions$model == m & test_predictions$horizon %in% halves[[k]], ]
      cbind(data.frame(window = k, model = m), accuracy_measures(z$actual, z$forecast, mase_scale), months = nrow(z))
    }))
  }))
  save_csv(by_half, "test_accuracy_by_half_year")

  # ---- Choose the better model -------------------------------------------
  # Rule: lower 2014 test RMSE wins. RMSEs equal to the nearest $0.001 (a tenth of a
  # cent per dozen) count as a tie; a tie goes to the lower MAE (also to $0.001), and a
  # remaining tie to the smaller absolute ME. Only 2014 test errors enter the rule.
  ranked <- test_scores[order(round(test_scores$RMSE, 3), round(test_scores$MAE, 3), abs(test_scores$ME)), ]
  better <- ranked$model[1]
  runner_up <- ranked$model[2]
  decided_by <- if (round(ranked$RMSE[1], 3) != round(ranked$RMSE[2], 3)) "RMSE" else if (round(ranked$MAE[1], 3) != round(ranked$MAE[2], 3)) "MAE (RMSE tied)" else "|ME| (RMSE and MAE tied)"
  wins <- sapply(c("MAE", "RMSE", "MAPE", "MASE"), function(k) {
    ranked$model[which.min(ranked[[k]])]
  })
  wins <- c(wins, "|ME|" = ranked$model[which.min(abs(ranked$ME))])
  better_table <- data.frame(
    better_model = better, runner_up = runner_up, decided_by = decided_by,
    better_RMSE = ranked$RMSE[1], runner_up_RMSE = ranked$RMSE[2],
    RMSE_difference = ranked$RMSE[2] - ranked$RMSE[1],
    RMSE_difference_pct = 100 * (ranked$RMSE[2] - ranked$RMSE[1]) / ranked$RMSE[2],
    better_MAE = ranked$MAE[1], runner_up_MAE = ranked$MAE[2],
    measures_won_by_better = paste(names(wins)[wins == better], collapse = " "),
    measures_won_by_runner_up = paste(names(wins)[wins == runner_up], collapse = " "),
    rule = paste(
      "Lower 2014 test RMSE; tie = equal to $0.001; then lower MAE (to $0.001);",
      "then smaller |ME|"
    )
  )
  save_csv(better_table, "better_model")
  cat("Better model on the 2014 test:", better, "(decided by", decided_by, ")\n")

  # ---- Check training residuals ------------------------------------------
  diagnostics <- do.call(rbind, lapply(MODELS, function(m) {
    fit <- test_fits[[m]]
    r <- as.numeric(residuals(fit))
    stopifnot(length(r) == N_TRAIN, all(is.finite(r)))
    fitdf <- if (inherits(fit, "Arima")) {
      sum(fit$arma[1:4])
    } else {
      sum(names(fit$par) %in% c("alpha", "beta", "gamma", "phi"))
    }
    r_acf <- as.numeric(acf(r, lag.max = 36L, plot = FALSE)$acf)
    lb12 <- Box.test(r, lag = 12L, type = "Ljung-Box", fitdf = fitdf)
    lb24 <- Box.test(r, lag = 24L, type = "Ljung-Box", fitdf = fitdf)
    z <- (r - mean(r)) / sd(r)
    figure(paste0("05_residuals_", slug(m)), function() {
      par(mfrow = c(2, 2), mar = c(4.5, 4.5, 3, 1), oma = c(0, 0, 2.5, 0))
      plot(train_dates, r,
        type = "l", col = MODEL_COLORS[m], lwd = 1.2,
        main = "Residuals over time", xlab = "Month", ylab = "Residual ($/dozen)"
      )
      abline(h = 0, lty = 2)
      hist(r,
        breaks = "FD", freq = FALSE, col = "#bfdbfe", border = "white",
        main = "Residual histogram", xlab = "Residual ($/dozen)", ylab = "Density"
      )
      curve(dnorm(x, mean(r), sd(r)), add = TRUE, col = ACTUAL_COLOR, lwd = 2)
      legend("topright", "Normal density", col = ACTUAL_COLOR, lwd = 2, bty = "n", cex = .75)
      draw_acf(r, "Residual ACF", 36L, MODEL_COLORS[m])
      qqnorm(r,
        col = MODEL_COLORS[m], pch = 16, cex = .6, main = "Normal Q-Q plot",
        xlab = "Theoretical normal quantile", ylab = "Residual quantile ($/dozen)"
      )
      qqline(r, col = ACTUAL_COLOR, lwd = 2)
      mtext(m, side = 3, outer = TRUE, line = .8, font = 2, col = HISTORY_COLOR)
    }, height = 1200L)
    data.frame(
      model = m, structure = describe_fit(fit), months = length(r), mean = mean(r),
      sd = sd(r), skewness = mean(z^3), excess_kurtosis = mean(z^4) - 3,
      largest_abs_residual = max(abs(r)), largest_abs_month = format(train_dates[which.max(abs(r))], "%b %Y"),
      acf_lag1 = r_acf[2], acf_lag12 = r_acf[13], acf_lag24 = r_acf[25],
      acf_95pct_bound = 1.96 / sqrt(length(r)), fitdf = fitdf,
      ljung_box_lag12_stat = unname(lb12$statistic), ljung_box_lag12_df = unname(lb12$parameter),
      ljung_box_lag12_p = lb12$p.value, ljung_box_lag24_stat = unname(lb24$statistic),
      ljung_box_lag24_df = unname(lb24$parameter), ljung_box_lag24_p = lb24$p.value
    )
  }))
  save_csv(diagnostics, "residual_diagnostics")
  residual_sd_by_decade <- do.call(rbind, lapply(MODELS, function(m) {
    r <- as.numeric(residuals(test_fits[[m]]))
    data.frame(
      model = m, period = names(decades),
      residual_sd = vapply(decades, function(window) {
        sd(r[train_dates >= as.Date(window[1]) & train_dates <= as.Date(window[2])])
      }, numeric(1)), row.names = NULL
    )
  }))
  save_csv(residual_sd_by_decade, "residual_sd_by_decade")

  # ---- Plot both 2014 test forecasts -------------------------------------
  # Fan chart: history, forecast mean, 80%/95% bands joined to the last observed month,
  # and optional actuals drawn after the forecast origin.
  test_actual_df <- data.frame(date = test_dates, price = test_actual)
  for (m in MODELS) {
    figure(paste0("06_test_forecast_", slug(m)), function() {
      draw_fan(
        test_fc[[m]], model_data, N_TRAIN, N_TEST, MODEL_COLORS[m], paste(m, "forecast"),
        paste(m, "test forecast, 2014"), "2011-01-01", test_actual_df
      )
    })
  }

  # ---- Plot the model comparison -----------------------------------------
  figure("07_test_comparison", function() {
    layout(matrix(1:2, 2), heights = c(3, 2))
    par(mar = c(2.5, 5, 3, 1))
    past <- which(model_data$date >= as.Date("2013-01-01") & seq_len(nrow(model_data)) <= N_TRAIN)
    origin <- model_data$date[N_TRAIN]
    y_range <- range(model_data$price[c(past, test_id)], sapply(test_fc, function(fc) as.numeric(fc$mean)))
    y_range[2] <- y_range[2] + .1 * diff(y_range)
    plot(range(model_data$date[past], test_dates), y_range,
      type = "n", xlab = "",
      ylab = "U.S. dollars per dozen", main = "Forecasts and actual prices, 2014"
    )
    lines(model_data$date[c(past, test_id)], model_data$price[c(past, test_id)], col = HISTORY_COLOR, lwd = 2)
    points(test_dates, test_actual, pch = 16, col = HISTORY_COLOR)
    abline(v = origin, col = "#64748b", lty = 2)
    for (m in MODELS) {
      lines(c(origin, test_dates), c(model_data$price[N_TRAIN], test_fc[[m]]$mean),
        col = MODEL_COLORS[m], lwd = 2.5, lty = MODEL_LTY[m]
      )
    }
    legend("topleft", c("Observed", paste(MODELS, "forecast")),
      col = c(HISTORY_COLOR, MODEL_COLORS[MODELS]), lty = c(1, MODEL_LTY[MODELS]), lwd = 2.5,
      bg = "white", box.col = "white", inset = .01, cex = .8, ncol = 3
    )
    par(mar = c(4.5, 5, 3, 1))
    err <- sapply(MODELS, function(m) test_predictions$error[test_predictions$model == m])
    plot(range(test_dates), range(err, 0),
      type = "n", xlab = "Month",
      ylab = "Actual minus forecast ($)", main = "Forecast error, 2014"
    )
    abline(h = 0, col = "#334155")
    for (m in MODELS) {
      lines(test_dates, err[, m], col = MODEL_COLORS[m], lwd = 2, lty = MODEL_LTY[m])
      points(test_dates, err[, m], col = MODEL_COLORS[m], pch = if (m == MODELS[1]) 17 else 16)
    }
    legend("topleft", MODELS,
      col = MODEL_COLORS[MODELS], lty = MODEL_LTY[MODELS], lwd = 2,
      pch = c(17, 16), bty = "n", cex = .8, ncol = 2
    )
  }, height = 1300L)
  figure("08_accuracy_comparison", function() {
    par(mfrow = c(1, 3), mar = c(2.5, 5, 3, 1))
    s <- test_scores[match(MODELS, test_scores$model), ]
    panels <- list(
      list(cols = c("ME", "MAE", "RMSE"), ylab = "U.S. dollars per dozen", fmt = "%.4f"),
      list(cols = "MAPE", ylab = "Percent", fmt = "%.2f"), list(cols = "MASE", ylab = "Ratio (no units)", fmt = "%.3f")
    )
    for (p in panels) {
      # Rows = models (bars), columns = measures (groups).
      v <- as.matrix(s[, p$cols, drop = FALSE])
      rownames(v) <- MODELS
      lim <- range(0, v) * 1.25
      bars <- barplot(v,
        beside = TRUE, col = MODEL_COLORS[MODELS], border = NA, ylim = lim,
        ylab = p$ylab, main = paste(p$cols, collapse = ", ")
      )
      abline(h = 0, col = "#334155")
      text(bars, v, sprintf(p$fmt, v), pos = ifelse(v >= 0, 3, 1), cex = .75)
    }
    legend("topright", MODELS, fill = MODEL_COLORS[MODELS], border = NA, bty = "n", cex = .85)
  }, height = 900L, width = 1800L)

  # ---- Refit through December 2014 and forecast --------------------------
  final_fits <- list(
    "Damped Holt" = fit_damped_holt(series),
    "Seasonal ARIMA" = refit_arima(series)
  )
  # Check only (not used): would a fresh search on data through Dec 2014 pick the same order?
  research <- search_arima(series)
  fc_long <- forecast_model(final_fits[[better]], h = H_LONG)
  for (h in c(H_SHORT, H_YEAR)) {
    # The 6- and 12-month forecasts are the first rows of the same forecast path.
    fc_h <- forecast_model(final_fits[[better]], h = h)
    stopifnot(
      isTRUE(all.equal(as.numeric(fc_h$mean), as.numeric(fc_long$mean)[seq_len(h)])),
      isTRUE(all.equal(as.numeric(fc_h$lower), as.numeric(fc_long$lower[seq_len(h), ]))),
      isTRUE(all.equal(as.numeric(fc_h$upper), as.numeric(fc_long$upper[seq_len(h), ])))
    )
  }
  fc_dates <- seq(as.Date("2015-01-01"), by = "month", length.out = H_LONG)

  # Main Task 5 output: a forecast issued from Dec 2014, before seeing 2015.
  # Keep this separate from the 2014 test forecasts and the post-hoc comparisons.
  report_forecast <- data.frame(
    model = better, structure = describe_fit(final_fits[[better]]),
    fit_start = min(model_data$date), fit_end = DATA_END, forecast_origin = DATA_END,
    date = fc_dates[seq_len(H_YEAR)], horizon = seq_len(H_YEAR),
    mean = as.numeric(fc_long$mean)[seq_len(H_YEAR)],
    lower80 = as.numeric(fc_long$lower[, "80%"])[seq_len(H_YEAR)],
    upper80 = as.numeric(fc_long$upper[, "80%"])[seq_len(H_YEAR)],
    lower95 = as.numeric(fc_long$lower[, "95%"])[seq_len(H_YEAR)],
    upper95 = as.numeric(fc_long$upper[, "95%"])[seq_len(H_YEAR)]
  )
  save_csv(report_forecast, "report_final_forecast_2015")
  figure("13_final_forecast_2015", function() {
    draw_fan(
      fc_long, model_data, nrow(model_data), H_YEAR, MODEL_COLORS[better], paste(better, "forecast"),
      paste(better, "final forecast, Jan-Dec 2015"), "2011-01-01"
    )
  })

  # ---- Compare with later actual prices (post-hoc only) ------------------
  # First and only use of post-2014 prices. Nothing below feeds back into a fit or the choice.
  posthoc <- full[full$date > DATA_END, ]
  forecast_table <- data.frame(
    model = better, date = fc_dates, horizon = seq_len(H_LONG),
    mean = as.numeric(fc_long$mean), lower80 = as.numeric(fc_long$lower[, "80%"]),
    upper80 = as.numeric(fc_long$upper[, "80%"]), lower95 = as.numeric(fc_long$lower[, "95%"]),
    upper95 = as.numeric(fc_long$upper[, "95%"]),
    actual_posthoc = posthoc$price[match(fc_dates, posthoc$date)]
  )
  forecast_table$scored <- !is.na(forecast_table$actual_posthoc)
  forecast_table$error <- forecast_table$actual_posthoc - forecast_table$mean
  forecast_table$pct_error <- 100 * forecast_table$error / forecast_table$actual_posthoc
  forecast_table$in80 <- with(forecast_table, actual_posthoc >= lower80 & actual_posthoc <= upper80)
  forecast_table$in95 <- with(forecast_table, actual_posthoc >= lower95 & actual_posthoc <= upper95)
  n_scored <- sum(forecast_table$scored)
  stopifnot(
    nrow(posthoc) == 124L, n_scored == 124L, all(forecast_table$scored[1:124]),
    !any(forecast_table$scored[125:H_LONG]), max(fc_dates) == as.Date("2026-12-01"),
    all(is.finite(as.matrix(forecast_table[, 4:8]))),
    all(forecast_table$lower95 <= forecast_table$lower80), all(forecast_table$lower80 <= forecast_table$mean),
    all(forecast_table$mean <= forecast_table$upper80), all(forecast_table$upper80 <= forecast_table$upper95)
  )
  save_csv(forecast_table[1:H_SHORT, ], "better_forecast_6_months")
  save_csv(forecast_table[1:H_YEAR, ], "better_forecast_12_months")
  save_csv(forecast_table, "better_forecast_144_months")
  gap_rows <- function(k, label) {
    z <- forecast_table[forecast_table$horizon <= k & forecast_table$scored, ]
    data.frame(
      window = label, model = better, months_scored = nrow(z),
      ME = mean(z$error), MAE = mean(abs(z$error)), RMSE = sqrt(mean(z$error^2)),
      MAPE = mean(abs(z$pct_error)), Coverage80 = mean(z$in80), Coverage95 = mean(z$in95),
      months_actual_above_forecast = sum(z$error > 0), mean_actual = mean(z$actual_posthoc),
      mean_forecast = mean(z$mean), note = "Post-hoc: actuals not used for fitting or choice"
    )
  }
  gap_summary <- rbind(
    gap_rows(H_SHORT, "6 months: Jan-Jun 2015"),
    gap_rows(H_YEAR, "12 months: Jan-Dec 2015"),
    gap_rows(n_scored, "124 months: Jan 2015-Apr 2025 (all available actuals)"),
    data.frame(
      window = "Months 125-144: May 2025-Dec 2026", model = better, months_scored = 0L,
      ME = NA, MAE = NA, RMSE = NA, MAPE = NA, Coverage80 = NA, Coverage95 = NA,
      months_actual_above_forecast = NA, mean_actual = NA,
      mean_forecast = mean(forecast_table$mean[!forecast_table$scored]),
      note = "Unscored extrapolation: no actual prices exist for these months"
    )
  )
  save_csv(gap_summary, "gap_summary")
  scored <- forecast_table[forecast_table$scored, ]
  scored$year <- as.integer(format(scored$date, "%Y"))
  gap_by_year <- do.call(rbind, lapply(split(scored, scored$year), function(z) {
    data.frame(
      year = z$year[1], months = nrow(z), mean_actual = mean(z$actual_posthoc),
      mean_forecast = mean(z$mean), ME = mean(z$error), MAE = mean(abs(z$error)),
      RMSE = sqrt(mean(z$error^2)), months_actual_above_forecast = sum(z$error > 0),
      Coverage80 = mean(z$in80), Coverage95 = mean(z$in95)
    )
  }))
  save_csv(gap_by_year, "gap_by_year")
  horizon_plots <- list(
    list(name = "09_better_forecast_6_months", h = H_SHORT, from = "2010-01-01"),
    list(name = "10_better_forecast_12_months", h = H_YEAR, from = "2010-01-01"),
    list(name = "11_better_forecast_144_months", h = H_LONG, from = "2000-01-01")
  )
  for (p in horizon_plots) {
    rows <- forecast_table[seq_len(p$h), ]
    shown <- rows[rows$scored, c("date", "actual_posthoc")]
    names(shown) <- c("date", "price")
    unscored <- if (p$h > n_scored) fc_dates[n_scored + 1L] else NULL
    heading <- paste0(better, " forecast, ", month_label(rows$date))
    figure(paste0(p$name, "_clean"), function() {
      draw_fan(fc_long, model_data, nrow(model_data), p$h, MODEL_COLORS[better], paste(better, "forecast"), heading, p$from)
    })
    figure(p$name, function() {
      draw_fan(
        fc_long, model_data, nrow(model_data), p$h, MODEL_COLORS[better], paste(better, "forecast"),
        heading, p$from, shown, unscored
      )
    })
  }
  figure("12_gap_by_year", function() {
    gap_span <- diff(range(0, gap_by_year$ME)) # padding so the value labels are not clipped
    bars <- barplot(gap_by_year$ME,
      names.arg = ifelse(gap_by_year$months < 12,
        paste0(gap_by_year$year, "*"), gap_by_year$year
      ), border = NA,
      col = ifelse(gap_by_year$ME >= 0, ACTUAL_COLOR, "#2563eb"),
      ylim = range(0, gap_by_year$ME) + c(-.1, .1) * gap_span, xlab = "Calendar year (* = Jan-Apr only)",
      ylab = "Mean actual minus forecast ($/dozen)",
      main = "Actual minus forecast by year"
    )
    abline(h = 0, col = "#334155")
    text(bars, gap_by_year$ME, sprintf("%.2f", gap_by_year$ME), pos = ifelse(gap_by_year$ME >= 0, 3, 1), cex = .75)
    legend("topleft", c("Actual above forecast", "Actual below forecast"),
      fill = c(ACTUAL_COLOR, "#2563eb"), border = NA, bty = "n", cex = .8
    )
  })

  # ---- Export model structures and parameters ----------------------------
  stages <- list(
    list(stage = "Test fit", fits = test_fits, end = TRAIN_END, n = N_TRAIN),
    list(stage = "Final fit", fits = final_fits, end = DATA_END, n = nrow(model_data))
  )
  how_chosen <- c(
    "Damped Holt" = "ETS(A,Ad,N) set by the team; parameters by maximum likelihood",
    "Seasonal ARIMA" = "auto.arima seasonal search (AICc, stepwise, exact ML) on the training data"
  )
  structures <- do.call(rbind, lapply(stages, function(s) {
    do.call(rbind, lapply(MODELS, function(m) {
      fit <- s$fits[[m]]
      how <- if (m == "Seasonal ARIMA" && s$stage == "Final fit") {
        paste("Order fixed from the training search; coefficients re-estimated by ML")
      } else {
        how_chosen[[m]]
      }
      data.frame(
        stage = s$stage, model = m, structure = describe_fit(fit), how_chosen = how,
        fit_start = "1980-01-01", fit_end = format(s$end), months = length(fit$x),
        log_likelihood = fit$loglik, AIC = fit$aic, AICc = fit$aicc, BIC = fit$bic,
        sigma = sqrt(fit$sigma2), row.names = NULL
      )
    }))
  }))
  structures <- rbind(structures, data.frame(
    stage = "Check only (not used)", model = "Seasonal ARIMA",
    structure = describe_fit(research),
    how_chosen = "Fresh auto.arima search on Jan 1980-Dec 2014, to see if the fixed order still wins",
    fit_start = "1980-01-01", fit_end = format(DATA_END), months = length(research$x),
    log_likelihood = research$loglik, AIC = research$aic, AICc = research$aicc, BIC = research$bic,
    sigma = sqrt(research$sigma2)
  ))
  save_csv(structures, "model_structures")
  meaning <- c(
    alpha = "Level smoothing weight", beta = "Slope smoothing weight",
    phi = "Damping factor applied to the slope each month", l = "Initial level, Jan 1980 ($/dozen)",
    b = "Initial slope ($/dozen per month)", ar1 = "AR(1) coefficient on the monthly price change",
    sar1 = "Seasonal AR coefficient at lag 12 months", sar2 = "Seasonal AR coefficient at lag 24 months",
    drift = "Drift ($/dozen per month)", intercept = "Mean"
  )
  parameters <- do.call(rbind, lapply(stages, function(s) {
    do.call(rbind, lapply(MODELS, function(m) {
      fit <- s$fits[[m]]
      if (inherits(fit, "Arima")) {
        est <- fit$coef
        se <- sqrt(diag(fit$var.coef))[names(est)]
        flag <- ifelse(abs(est) > 1.96 * se, "about 2+ standard errors from 0", "within 2 standard errors of 0")
      } else {
        est <- fit$par
        se <- rep(NA_real_, length(est))
        flag <- rep("", length(est))
        flag[names(est) %in% c("alpha", "beta") & abs(est - 1e-4) < 1e-6] <- "at the 0.0001 lower bound"
        flag[names(est) == "phi" & abs(est - 0.8) < 1e-6] <- "at the 0.8 lower bound"
        flag[names(est) == "phi" & abs(est - 0.98) < 1e-6] <- "at the 0.98 upper bound"
      }
      data.frame(
        stage = s$stage, model = m, parameter = c(names(est), "sigma"),
        estimate = c(as.numeric(est), sqrt(fit$sigma2)), std_error = c(as.numeric(se), NA),
        meaning = c(unname(meaning[names(est)]), "Residual standard deviation ($/dozen)"),
        note = c(flag, ""), row.names = NULL
      )
    }))
  }))
  save_csv(parameters, "model_parameters")

  # A compact parameter table for the report: both test-stage models, then the
  # selected model's final refit. Initial states and sigma stay in the full table.
  report_parameters <- parameters[parameters$parameter %in%
    c("alpha", "beta", "phi", "ar1", "sar1", "sar2", "drift", "intercept") &
    (parameters$stage == "Test fit" | parameters$model == better), ]
  report_parameters$fit_end <- ifelse(report_parameters$stage == "Test fit",
    format(TRAIN_END), format(DATA_END)
  )
  report_parameters$structure <- vapply(seq_len(nrow(report_parameters)), function(i) {
    stage_fits <- if (report_parameters$stage[i] == "Test fit") test_fits else final_fits
    describe_fit(stage_fits[[report_parameters$model[i]]])
  }, character(1))
  save_csv(report_parameters, "report_model_parameters")

  # Descriptive purchasing-power comparison only. CPI never enters a model fit,
  # the choice rule or the 2014 scores. The current-year CPI benchmark is a
  # published monthly observation, NOT a completed annual average for 2026.
  cpi <- read.csv(file.path(root, "data", "inflation_benchmarks.csv"), stringsAsFactors = FALSE)
  inflation_comparison <- compare_inflation(full, forecast_table, cpi, better)
  save_csv(inflation_comparison, "inflation_comparison")
  figure("14_inflation_comparison", function() {
    values <- c(
      inflation_comparison$actual_1980_in_benchmark_dollars,
      inflation_comparison$forecast_nominal_mean
    )
    bars <- barplot(values,
      names.arg = c("1980 actual\nadjusted", "2026 average\nforecast"),
      col = c(HISTORY_COLOR, MODEL_COLORS[better]), border = NA,
      ylim = c(0, 1.2 * max(values)), ylab = "Dollars per dozen",
      main = "1980 egg price and 2026 forecast, inflation adjusted"
    )
    text(bars, values, sprintf("$%.2f", values), pos = 3)
    mtext("1980 price in Sep 2026 dollars; monthly CPI benchmark, provisional comparison",
      side = 3, line = .3, cex = .8
    )
  })

  # ---- Verify fitting and scoring boundaries -----------------------------
  saw_exactly <- function(fit, n) {
    x <- fit$x
    end_month <- c(as.integer(format(model_data$date[n], "%Y")), as.integer(format(model_data$date[n], "%m")))
    length(x) == n && identical(as.numeric(x), model_data$price[seq_len(n)]) &&
      all(end(x) == end_month)
  }
  leakage <- data.frame(
    check = c(
      "Damped Holt test fit saw exactly Jan 1980-Dec 2013 (408 months, no 2014 values)",
      "Seasonal ARIMA test fit saw exactly Jan 1980-Dec 2013 (408 months, no 2014 values)",
      "Seasonal ARIMA order search ran on Jan 1980-Dec 2013 only",
      "Damped Holt final fit saw exactly Jan 1980-Dec 2014 (420 months, nothing after 2014)",
      "Seasonal ARIMA final fit saw exactly Jan 1980-Dec 2014 (420 months, nothing after 2014)",
      "Check-only research fit saw exactly Jan 1980-Dec 2014",
      "Every model input series ends on or before Dec 2014",
      "Test scores (and so the model choice) use only Jan-Dec 2014 actuals, 12 per model",
      "Sensitivity fits each end on or before Dec 2013"
    ),
    passed = c(
      saw_exactly(test_fits[["Damped Holt"]], N_TRAIN),
      saw_exactly(test_fits[["Seasonal ARIMA"]], N_TRAIN),
      length(test_fits[["Seasonal ARIMA"]]$x) == N_TRAIN,
      saw_exactly(final_fits[["Damped Holt"]], nrow(model_data)),
      saw_exactly(final_fits[["Seasonal ARIMA"]], nrow(model_data)),
      saw_exactly(research, nrow(model_data)), max(model_data$date) == DATA_END,
      nrow(test_predictions) == 2L * N_TEST && all(test_predictions$date %in% test_dates), NA
    )
  )

  # ---- Check other test years (context only) -----------------------------
  # Same procedure as the main test, repeated for each calendar year 2005-2014:
  # fit through the previous December, forecast 12 months, score both models.
  other_years <- do.call(rbind, lapply(2005:2014, function(year) {
    n_fit <- which(model_data$date == as.Date(sprintf("%d-12-01", year - 1L)))
    y <- ts(model_data$price[seq_len(n_fit)], start = c(1980, 1), frequency = 12)
    actual <- model_data$price[n_fit + seq_len(12L)]
    dh <- fit_damped_holt(y)
    sa <- search_arima(y)
    stopifnot(length(dh$x) == n_fit, length(sa$x) == n_fit, n_fit <= N_TRAIN)
    e_dh <- accuracy_measures(actual, as.numeric(forecast_model(dh, h = 12L)$mean), mase_scale)
    e_sa <- accuracy_measures(actual, as.numeric(forecast_model(sa, h = 12L)$mean), mase_scale)
    data.frame(
      test_year = year, fit_end = format(model_data$date[n_fit]),
      arima_order_found = describe_fit(sa), damped_holt_phi = unname(dh$par["phi"]),
      RMSE_damped_holt = e_dh$RMSE, RMSE_seasonal_arima = e_sa$RMSE,
      MAE_damped_holt = e_dh$MAE, MAE_seasonal_arima = e_sa$MAE,
      lower_RMSE = if (e_sa$RMSE < e_dh$RMSE) "Seasonal ARIMA" else "Damped Holt"
    )
  }))
  # The 2014 row repeats the main test exactly.
  stopifnot(
    isTRUE(all.equal(
      other_years$RMSE_seasonal_arima[other_years$test_year == 2014],
      test_scores$RMSE[test_scores$model == "Seasonal ARIMA"]
    )),
    isTRUE(all.equal(
      other_years$RMSE_damped_holt[other_years$test_year == 2014],
      test_scores$RMSE[test_scores$model == "Damped Holt"]
    ))
  )
  save_csv(other_years, "sensitivity_other_test_years")
  leakage$passed[nrow(leakage)] <- all(as.Date(other_years$fit_end) <= TRAIN_END)
  save_csv(leakage, "leakage_checks")
  stopifnot(all(leakage$passed))

  # ---- Save reproducibility records and output catalog -------------------
  saveRDS(
    list(
      test_fits = test_fits, test_forecasts = test_fc, final_fits = final_fits,
      better = better, arima_order = arima_order, forecast_144 = fc_long
    ),
    file.path(out, "fitted_models.rds")
  )
  writeLines(trimws(capture.output(sessionInfo()), which = "right"), file.path(out, "session_info.txt"))
  show <- function(x, digits = 4) print(x, row.names = FALSE, digits = digits)
  capture.output(
    {
      cat("FINAL TWO-MODEL STUDY: DAMPED HOLT AND SEASONAL ARIMA\n")
      cat("Training Jan 1980-Dec 2013 (408 months); test Jan-Dec 2014 (12 months); no validation set.\n\n")
      cat("Seasonal ARIMA order from the training search:", arima_found, "\n")
      cat("Fresh search on data through Dec 2014 (check only):", describe_fit(research), "\n\n")
      cat("2014 TEST ACCURACY\n")
      show(test_scores[, -2])
      cat("\nTRAINING FIT (one-step-ahead, in-sample)\n")
      show(train_scores[, -2])
      cat("\nBY HALF OF THE TEST YEAR (same forecasts)\n")
      show(by_half)
      cat("\nBETTER MODEL:", better, "| decided by", decided_by, "| rule:", better_table$rule, "\n")
      cat("\nRESIDUAL DIAGNOSTICS (training fits)\n")
      show(diagnostics[, c(
        "model", "sd", "acf_lag1",
        "acf_lag12", "acf_lag24", "ljung_box_lag12_p", "ljung_box_lag24_p"
      )])
      cat("\nPARAMETERS\n")
      show(parameters[, c("stage", "model", "parameter", "estimate", "std_error")])
      cat("\nMAIN FINAL FORECAST: JAN-DEC 2015 (refit through Dec 2014; no later actuals)\n")
      show(report_forecast[, c("date", "mean", "lower80", "upper80", "lower95", "upper95")])
      cat("\nINFLATION COMPARISON (provisional Sep 2026 CPI benchmark)\n")
      show(inflation_comparison)
      cat("\nPOST-HOC GAP SUMMARY (", better, ")\n", sep = "")
      show(gap_summary[, -c(2, 13)])
      cat("\nGAP BY YEAR\n")
      show(gap_by_year)
      cat("\nSENSITIVITY: OTHER SINGLE TEST YEARS (context only)\n")
      show(other_years)
      cat("\nLEAKAGE CHECKS\n")
      show(leakage)
      cat("\nLowest 95% bound over 144 months:", sprintf("%.3f", min(forecast_table$lower95)), "\n")
    },
    file = file.path(out, "results.txt")
  )
  file_guide <- final_output_catalog()
  save_csv(file_guide, "file_guide")
  produced <- list.files(out, recursive = TRUE)
  stopifnot(all(file.exists(file.path(out, file_guide$file))), all(produced %in% file_guide$file))
  cat("\n2014 TEST:\n")
  show(test_scores[, -2])
  cat("\nBetter model:", better, "\nGAP:\n")
  show(gap_summary[, c(1, 3:9)])
  cat("\nSaved to", out, "\n")
}

run_final_two_models()
