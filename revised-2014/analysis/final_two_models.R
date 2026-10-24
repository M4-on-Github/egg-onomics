# FINAL STUDY for the report: Damped Holt and Seasonal ARIMA on monthly egg prices.
# Training Jan 1980-Dec 2013 (408 months). Test Jan-Dec 2014 (12 months). No validation set.
# The model with the lower 2014 test RMSE is refitted through Dec 2014 and projected
# 6, 12 and 180 months ahead (Jan 2015-Dec 2029). Actual prices after Dec 2014 are used
# ONLY in the post-hoc gap tables and plots, never for fitting or for choosing a model.
# All models work on original dollar prices (no log transform).
# Run from revised-2014/:  Rscript analysis/final_two_models.R   (or Source it in RStudio)
# Writes tables to results/final_two_models/ and figures to results/final_two_models/figures/.

run_final_two_models <- function() {
  # ---- Locate the project and load the shared helpers ------------------------
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
  # helpers.R writes wherever EGG_FORECAST_OUTPUT points. Point it at this study's
  # own folder for the run, then restore the caller's value (forecast.R is untouched).
  old_out <- Sys.getenv("EGG_FORECAST_OUTPUT", unset = NA_character_)
  on.exit({
    if (is.na(old_out)) Sys.unsetenv("EGG_FORECAST_OUTPUT") else {
      Sys.setenv(EGG_FORECAST_OUTPUT = old_out)
    }
  }, add = TRUE)
  out <- Sys.getenv("EGG_FINAL_OUTPUT", unset = file.path(root, "results", "final_two_models"))
  Sys.setenv(EGG_FORECAST_OUTPUT = out)
  # Gives save_csv(), figure(), fit_one(), predict_one(), draw_acf(), LEVELS and colors.
  source(file.path(root, "analysis", "helpers.R"), local = TRUE)

  # ---- Study settings -----------------------------------------------------------
  TRAIN_END <- as.Date("2013-12-01")   # last month the test-stage fits may see
  DATA_END <- as.Date("2014-12-01")    # last month ANY fit may see
  N_TRAIN <- 408L
  N_TEST <- 12L
  H_SHORT <- 6L
  H_YEAR <- 12L
  H_LONG <- 180L                       # "15 years": Jan 2015-Dec 2029
  MODELS <- c("Damped Holt", "Seasonal ARIMA")
  MODEL_COLORS <- c("Damped Holt" = "#0d9488", "Seasonal ARIMA" = "#7c3aed")
  MODEL_LTY <- c("Damped Holt" = 2, "Seasonal ARIMA" = 1)
  ACTUAL_COLOR <- "#c2410c"
  EXPECTED_ORDER <- "ARIMA(1,1,0)(2,0,0)[12]"   # what earlier runs found; checked below
  slug <- function(model) gsub(" ", "_", tolower(model))
  month_label <- function(dates) paste(format(min(dates), "%b %Y"), "to", format(max(dates), "%b %Y"))

  # ---- Task 2: import and check the data ----------------------------------------
  raw <- read.csv(INPUT, stringsAsFactors = FALSE)
  stopifnot(identical(names(raw), c("observation_date", "APU0000708111")))
  full <- data.frame(date = as.Date(raw$observation_date), price = as.numeric(raw$APU0000708111))
  expected_months <- seq(as.Date("1980-01-01"), as.Date("2025-04-01"), by = "month")
  stopifnot(nrow(full) == 544L, !anyNA(full), !anyDuplicated(full$date),
    all(is.finite(full$price)), all(full$price > 0), identical(full$date, expected_months))
  # Only these 420 months (Jan 1980-Dec 2014) are ever passed to a model.
  # The later months stay in `full` for the history plot and the post-hoc gap section.
  model_data <- full[full$date <= DATA_END, ]
  series <- ts(model_data$price, start = c(1980, 1), frequency = 12)
  train_y <- window(series, end = c(2013, 12))
  train_dates <- model_data$date[seq_len(N_TRAIN)]
  test_id <- seq.int(N_TRAIN + 1L, N_TRAIN + N_TEST)
  test_dates <- model_data$date[test_id]
  test_actual <- model_data$price[test_id]
  stopifnot(nrow(model_data) == 420L, length(train_y) == N_TRAIN, max(train_dates) == TRAIN_END,
    identical(test_dates, seq(as.Date("2014-01-01"), DATA_END, by = "month")))
  in_window <- function(lo, hi) model_data$date >= as.Date(lo) & model_data$date <= as.Date(hi)
  data_check <- data.frame(item = c("Series", "Units", "Rows in source file", "First month",
      "Last month", "Missing months in the monthly sequence", "Missing or non-numeric prices",
      "Duplicate dates", "Non-positive prices", "Imputed or filled values",
      "Months available to models (Jan 1980-Dec 2014)", "Training months (Jan 1980-Dec 2013)",
      "Test months (Jan-Dec 2014)", "Months kept for post-hoc comparison only (Jan 2015-Apr 2025)",
      "Training price range ($)", "Test-year price range ($)", "Post-hoc price range ($)",
      "Source file MD5"),
    value = c("BLS average price APU0000708111: eggs, grade A, large, per dozen, U.S. city average",
      "U.S. dollars per dozen, monthly", nrow(full), format(min(full$date)), format(max(full$date)),
      length(setdiff(expected_months, full$date)), sum(is.na(raw$APU0000708111)),
      sum(duplicated(full$date)), sum(full$price <= 0), 0, nrow(model_data), N_TRAIN, N_TEST,
      sum(full$date > DATA_END),
      paste(sprintf("%.3f", range(train_y)), collapse = " to "),
      paste(sprintf("%.3f", range(test_actual)), collapse = " to "),
      paste(sprintf("%.3f", range(full$price[full$date > DATA_END])), collapse = " to "),
      unname(tools::md5sum(INPUT))))
  save_csv(data_check, "data_check")

  # ---- Task 2: exploration (training data only, Jan 1980-Dec 2013) ------------------
  # One full-history plot keeps the later prices visible for context, with the cuts marked.
  test_start <- as.Date("2014-01-01")
  posthoc_start <- as.Date("2015-01-01")
  figure("01_history_with_cuts", function() {
    plot(full$date, full$price, type = "n", xlab = "Month", ylab = "U.S. dollars per dozen",
      main = "U.S. average price of a dozen large Grade A eggs, Jan 1980-Apr 2025")
    u <- par("usr")
    rect(test_start, u[3], posthoc_start, u[4], col = "#ccfbf1", border = NA)
    rect(posthoc_start, u[3], u[2], u[4], col = "#f1f5f9", border = NA)
    lines(full$date, full$price, col = HISTORY_COLOR, lwd = 2)
    abline(v = c(test_start, posthoc_start), col = c("#0f766e", "#dc2626"), lty = c(3, 4), lwd = 2)
    legend("topleft", c("Observed monthly price", "Test year starts: Jan 2014",
      "Post-hoc comparison only: Jan 2015 onward"), col = c(HISTORY_COLOR, "#0f766e", "#dc2626"),
      lty = c(1, 3, 4), lwd = 2, bty = "n", cex = .85)
    mtext(paste("Training: Jan 1980-Dec 2013 (408 months) | Test: Jan-Dec 2014 (12)",
      "| Jan 2015-Apr 2025 (124): never used for fitting or choosing"), side = 3, line = .35, cex = .8)
  })
  draw_pacf <- function(y, heading, max_lag = 48L, color = "#2563eb") {
    pacf(as.numeric(y), lag.max = max_lag, main = heading, xlab = "Lag in months",
      ylab = "Partial ACF", col = color, lwd = 2)
  }
  train_change <- diff(train_y)
  figure("02_correlogram", function() {
    par(mfrow = c(2, 2), mar = c(4.5, 4.5, 3, 1))
    draw_acf(train_y, "ACF of price, Jan 1980-Dec 2013", 48L)
    draw_pacf(train_y, "PACF of price")
    draw_acf(train_change, "ACF of monthly price change", 48L, "#0f766e")
    draw_pacf(train_change, "PACF of monthly price change", 48L, "#0f766e")
  }, height = 1200L)
  stl_fit <- stl(train_y, s.window = "periodic", robust = TRUE)
  parts <- stl_fit$time.series
  seasonal_strength <- max(0, 1 - var(parts[, "remainder"]) / var(parts[, "seasonal"] + parts[, "remainder"]))
  trend_strength <- max(0, 1 - var(parts[, "remainder"]) / var(parts[, "trend"] + parts[, "remainder"]))
  # A periodic seasonal is identical every year; training starts in January.
  seasonal_by_month <- setNames(as.numeric(parts[1:12, "seasonal"]), month.abb)
  figure("03_stl_decomposition", function() {
    par(mfrow = c(4, 1), mar = c(2, 5, 2, 1), oma = c(3, 0, 2.5, 0))
    plot(train_dates, as.numeric(train_y), type = "l", col = HISTORY_COLOR, lwd = 1.5,
      xlab = "", ylab = "Price ($/dozen)", main = "Observed price")
    plot(train_dates, as.numeric(parts[, "trend"]), type = "l", col = "#2563eb", lwd = 2,
      xlab = "", ylab = "Trend ($/dozen)", main = "Trend")
    plot(train_dates, as.numeric(parts[, "seasonal"]), type = "l", col = "#0f766e", lwd = 1.5,
      xlab = "", ylab = "Seasonal ($/dozen)", main = "Seasonal component (same each year)")
    abline(h = 0, lty = 2, col = "#64748b")
    plot(train_dates, as.numeric(parts[, "remainder"]), type = "h", col = "#64748b",
      xlab = "", ylab = "Remainder ($/dozen)", main = "Remainder")
    abline(h = 0)
    mtext("Month", side = 1, outer = TRUE, line = 1.2, col = HISTORY_COLOR)
    mtext("STL decomposition of training prices, Jan 1980-Dec 2013 (robust, periodic seasonal)",
      side = 3, outer = TRUE, line = .8, font = 2, col = HISTORY_COLOR)
  }, height = 1500L)
  figure("04_seasonal_by_month", function() {
    par(mfrow = c(1, 2), mar = c(4.5, 5, 4, 1))
    # monthplot() mishandles col/main passed through `...`; set the line color with par()
    # and add the titles separately.
    par(col = HISTORY_COLOR)
    monthplot(train_y, labels = month.abb, ylab = "U.S. dollars per dozen",
      col.base = ACTUAL_COLOR, lwd.base = 2)
    par(col = "#334155")
    title(main = "Price by calendar month, 1980-2013",
      xlab = "Calendar month (thin lines: years; bar: mean)")
    bars <- barplot(100 * seasonal_by_month, names.arg = month.abb, border = NA, las = 2,
      col = ifelse(seasonal_by_month >= 0, BAND_80, "#fdba74"),
      ylim = 100 * range(seasonal_by_month) * 1.25, xlab = "Calendar month",
      ylab = "Seasonal effect (cents per dozen)", main = "Average seasonal effect (STL)")
    abline(h = 0, col = "#334155")
    text(bars, 100 * seasonal_by_month, sprintf("%.1f", 100 * seasonal_by_month),
      pos = ifelse(seasonal_by_month >= 0, 3, 1), cex = .7)
  })
  # Price level and monthly-change spread by decade: the dollar spread grows with the level.
  decades <- list("1980-1989" = c("1980-01-01", "1989-12-01"), "1990-1999" = c("1990-01-01", "1999-12-01"),
    "2000-2009" = c("2000-01-01", "2009-12-01"), "2010-2013" = c("2010-01-01", "2013-12-01"))
  change_all <- c(NA, diff(model_data$price))
  by_decade <- do.call(rbind, lapply(names(decades), function(k) {
    keep <- in_window(decades[[k]][1], decades[[k]][2]) & !is.na(change_all)
    data.frame(period = k, months = sum(in_window(decades[[k]][1], decades[[k]][2])),
      mean_price = mean(model_data$price[in_window(decades[[k]][1], decades[[k]][2])]),
      sd_monthly_change = sd(change_all[keep]),
      sd_change_as_pct_of_mean_price = 100 * sd(change_all[keep]) /
        mean(model_data$price[in_window(decades[[k]][1], decades[[k]][2])]))
  }))
  save_csv(by_decade, "exploration_by_decade")
  acf_level <- as.numeric(acf(as.numeric(train_y), lag.max = 48L, plot = FALSE)$acf)
  acf_change <- as.numeric(acf(as.numeric(train_change), lag.max = 48L, plot = FALSE)$acf)
  pacf_change <- as.numeric(pacf(as.numeric(train_change), lag.max = 48L, plot = FALSE)$acf)
  exploration <- data.frame(measure = c("training_months", "training_mean_price", "training_min_price",
      "training_min_month", "training_max_price", "training_max_month",
      "acf_price_lag1", "acf_price_lag12", "acf_price_lag24", "acf_price_lag48",
      "acf_change_lag1", "acf_change_lag12", "acf_change_lag24", "pacf_change_lag1",
      "pacf_change_lag12", "pacf_change_lag24", "acf_95pct_bound_change",
      "stl_seasonal_strength", "stl_trend_strength", "stl_seasonal_range_cents",
      "stl_peak_month", "stl_trough_month", "kpss_ndiffs", "seasonal_nsdiffs"),
    value = c(N_TRAIN, mean(train_y), min(train_y), format(train_dates[which.min(train_y)], "%b %Y"),
      max(train_y), format(train_dates[which.max(train_y)], "%b %Y"),
      acf_level[c(2, 13, 25, 49)], acf_change[c(2, 13, 25)], pacf_change[c(1, 12, 24)],
      1.96 / sqrt(length(train_change)), seasonal_strength, trend_strength,
      100 * diff(range(seasonal_by_month)), names(which.max(seasonal_by_month)),
      names(which.min(seasonal_by_month)), forecast::ndiffs(train_y), forecast::nsdiffs(train_y)),
    note = c("Jan 1980-Dec 2013", "$ per dozen", "$ per dozen", "", "$ per dozen", "",
      "slow decay = trend / non-stationary level", "", "", "",
      "after first differencing", "seasonal spike check", "seasonal spike check",
      "", "", "", "approximate +/- bound for one ACF lag",
      "1 - var(R)/var(S+R); 0 = none, 1 = strong", "1 - var(R)/var(T+R)",
      "peak-to-trough of the average seasonal effect", "", "",
      "number of first differences suggested by KPSS (used by auto.arima)",
      "number of seasonal differences suggested (used by auto.arima)"))
  save_csv(exploration, "exploration_summary")

  # ---- Task 3: fit both models on the training data only -------------------------
  search_arima <- function(y) {
    forecast::auto.arima(y, seasonal = TRUE, ic = "aicc", stepwise = TRUE,
      approximation = FALSE, method = "ML", trace = FALSE)
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
  test_fits <- list("Damped Holt" = fit_one(train_y, "Damped Holt"),
                    "Seasonal ARIMA" = search_arima(train_y))
  # Fix the order the search found on the training data. Later refits re-estimate the
  # coefficients for this order but do not search again.
  arima_found <- describe_fit(test_fits[["Seasonal ARIMA"]])
  arima_order <- forecast::arimaorder(test_fits[["Seasonal ARIMA"]])
  arima_seasonal <- if (length(arima_order) > 3L) arima_order[4:6] else c(0L, 0L, 0L)
  arima_drift <- "drift" %in% names(coef(test_fits[["Seasonal ARIMA"]]))
  arima_mean <- "intercept" %in% names(coef(test_fits[["Seasonal ARIMA"]]))
  if (arima_found != EXPECTED_ORDER) {
    warning("Training search found ", arima_found, " (earlier runs: ", EXPECTED_ORDER,
      "). Re-check the guide's numbers.", call. = FALSE)
  }
  refit_arima <- function(y) {
    forecast::Arima(y, order = arima_order[1:3], seasonal = list(order = arima_seasonal, period = 12),
      include.mean = arima_mean, include.drift = arima_drift, method = "ML")
  }
  cat("Seasonal ARIMA order fixed from the training search:", arima_found, "\n")
  test_fc <- lapply(test_fits, predict_one, h = N_TEST)

  # ---- Task 3: accuracy on the 2014 test year --------------------------------------
  # MASE scale: in-sample mean absolute seasonal-naive error on the training data.
  mase_scale <- mean(abs(diff(as.numeric(train_y), lag = 12L)))
  measures <- function(actual, predicted) {
    e <- actual - predicted
    data.frame(ME = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
      MAPE = 100 * mean(abs(e / actual)), MASE = mean(abs(e)) / mase_scale)
  }
  test_predictions <- do.call(rbind, lapply(MODELS, function(m) {
    fc <- test_fc[[m]]
    data.frame(model = m, date = test_dates, horizon = seq_len(N_TEST), actual = test_actual,
      forecast = as.numeric(fc$mean), error = test_actual - as.numeric(fc$mean),
      pct_error = 100 * (test_actual - as.numeric(fc$mean)) / test_actual,
      lower80 = as.numeric(fc$lower[, "80%"]), upper80 = as.numeric(fc$upper[, "80%"]),
      lower95 = as.numeric(fc$lower[, "95%"]), upper95 = as.numeric(fc$upper[, "95%"]),
      row.names = NULL)
  }))
  test_predictions$in80 <- with(test_predictions, actual >= lower80 & actual <= upper80)
  test_predictions$in95 <- with(test_predictions, actual >= lower95 & actual <= upper95)
  save_csv(test_predictions, "test_predictions_2014")
  test_scores <- do.call(rbind, lapply(MODELS, function(m) {
    z <- test_predictions[test_predictions$model == m, ]
    cbind(data.frame(model = m, set = "Test: Jan-Dec 2014 (12 months ahead from Dec 2013)"),
      measures(z$actual, z$forecast), Coverage80 = mean(z$in80), Coverage95 = mean(z$in95),
      months = nrow(z))
  }))
  train_scores <- do.call(rbind, lapply(MODELS, function(m) {
    cbind(data.frame(model = m, set = "Training: one-step-ahead fit, Jan 1980-Dec 2013"),
      measures(as.numeric(train_y), as.numeric(fitted(test_fits[[m]]))),
      Coverage80 = NA_real_, Coverage95 = NA_real_, months = N_TRAIN)
  }))
  save_csv(rbind(test_scores, train_scores), "accuracy_table")
  halves <- list("Jan-Jun 2014 (horizons 1-6)" = 1:6, "Jul-Dec 2014 (horizons 7-12)" = 7:12,
    "Full year 2014 (horizons 1-12)" = 1:12)
  by_half <- do.call(rbind, lapply(names(halves), function(k) {
    do.call(rbind, lapply(MODELS, function(m) {
      z <- test_predictions[test_predictions$model == m & test_predictions$horizon %in% halves[[k]], ]
      cbind(data.frame(window = k, model = m), measures(z$actual, z$forecast), months = nrow(z))
    }))
  }))
  save_csv(by_half, "test_accuracy_by_half_year")

  # ---- Task 4: choose the better model with a stated rule ---------------------------
  # Rule: lower 2014 test RMSE wins. RMSEs equal to the nearest $0.001 (a tenth of a
  # cent per dozen) count as a tie; a tie goes to the lower MAE (also to $0.001), and a
  # remaining tie to the smaller absolute ME. Only 2014 test errors enter the rule.
  ranked <- test_scores[order(round(test_scores$RMSE, 3), round(test_scores$MAE, 3), abs(test_scores$ME)), ]
  better <- ranked$model[1]
  runner_up <- ranked$model[2]
  decided_by <- if (round(ranked$RMSE[1], 3) != round(ranked$RMSE[2], 3)) "RMSE" else
    if (round(ranked$MAE[1], 3) != round(ranked$MAE[2], 3)) "MAE (RMSE tied)" else "|ME| (RMSE and MAE tied)"
  wins <- sapply(c("MAE", "RMSE", "MAPE", "MASE"), function(k) {
    ranked$model[which.min(ranked[[k]])]
  })
  wins <- c(wins, "|ME|" = ranked$model[which.min(abs(ranked$ME))])
  better_table <- data.frame(better_model = better, runner_up = runner_up, decided_by = decided_by,
    better_RMSE = ranked$RMSE[1], runner_up_RMSE = ranked$RMSE[2],
    RMSE_difference = ranked$RMSE[2] - ranked$RMSE[1],
    RMSE_difference_pct = 100 * (ranked$RMSE[2] - ranked$RMSE[1]) / ranked$RMSE[2],
    better_MAE = ranked$MAE[1], runner_up_MAE = ranked$MAE[2],
    measures_won_by_better = paste(names(wins)[wins == better], collapse = " "),
    measures_won_by_runner_up = paste(names(wins)[wins == runner_up], collapse = " "),
    rule = paste("Lower 2014 test RMSE; tie = equal to $0.001; then lower MAE (to $0.001);",
      "then smaller |ME|"))
  save_csv(better_table, "better_model")
  cat("Better model on the 2014 test:", better, "(decided by", decided_by, ")\n")

  # ---- Task 3 and 4: residual diagnostics of the training fits -----------------------
  residual_sd_by_decade <- list()
  diagnostics <- do.call(rbind, lapply(MODELS, function(m) {
    fit <- test_fits[[m]]
    r <- as.numeric(residuals(fit))
    stopifnot(length(r) == N_TRAIN, all(is.finite(r)))
    fitdf <- if (inherits(fit, "Arima")) sum(fit$arma[1:4]) else {
      sum(names(fit$par) %in% c("alpha", "beta", "gamma", "phi"))
    }
    r_acf <- as.numeric(acf(r, lag.max = 36L, plot = FALSE)$acf)
    lb12 <- Box.test(r, lag = 12L, type = "Ljung-Box", fitdf = fitdf)
    lb24 <- Box.test(r, lag = 24L, type = "Ljung-Box", fitdf = fitdf)
    z <- (r - mean(r)) / sd(r)
    residual_sd_by_decade[[m]] <<- data.frame(model = m, period = names(decades),
      residual_sd = sapply(decades, function(w) {
        sd(r[train_dates >= as.Date(w[1]) & train_dates <= as.Date(w[2])])
      }), row.names = NULL)
    figure(paste0("05_residuals_", slug(m)), function() {
      par(mfrow = c(2, 2), mar = c(4.5, 4.5, 3, 1), oma = c(0, 0, 2.5, 0))
      plot(train_dates, r, type = "l", col = MODEL_COLORS[m], lwd = 1.2,
        main = "Residuals over time", xlab = "Month", ylab = "Residual ($/dozen)")
      abline(h = 0, lty = 2)
      hist(r, breaks = "FD", freq = FALSE, col = "#bfdbfe", border = "white",
        main = "Residual histogram", xlab = "Residual ($/dozen)", ylab = "Density")
      curve(dnorm(x, mean(r), sd(r)), add = TRUE, col = ACTUAL_COLOR, lwd = 2)
      legend("topright", "Normal curve, same mean and sd", col = ACTUAL_COLOR, lwd = 2, bty = "n", cex = .75)
      draw_acf(r, "Residual ACF", 36L, MODEL_COLORS[m])
      qqnorm(r, col = MODEL_COLORS[m], pch = 16, cex = .6, main = "Normal Q-Q plot",
        xlab = "Theoretical normal quantile", ylab = "Residual quantile ($/dozen)")
      qqline(r, col = ACTUAL_COLOR, lwd = 2)
      # A p-value that rounds to 0 is shown as "< 0.0001" rather than "= 0".
      p_text <- if (lb24$p.value < 1e-4) "< 0.0001" else sprintf("= %.2g", lb24$p.value)
      mtext(sprintf("%s (%s): training residuals, Jan 1980-Dec 2013 | lag-12 ACF %.2f | Ljung-Box lag 24 p %s",
        m, describe_fit(fit), r_acf[13], p_text), side = 3, outer = TRUE, line = .8, font = 2,
        col = HISTORY_COLOR)
    }, height = 1200L)
    data.frame(model = m, structure = describe_fit(fit), months = length(r), mean = mean(r),
      sd = sd(r), skewness = mean(z^3), excess_kurtosis = mean(z^4) - 3,
      largest_abs_residual = max(abs(r)), largest_abs_month = format(train_dates[which.max(abs(r))], "%b %Y"),
      acf_lag1 = r_acf[2], acf_lag12 = r_acf[13], acf_lag24 = r_acf[25],
      acf_95pct_bound = 1.96 / sqrt(length(r)), fitdf = fitdf,
      ljung_box_lag12_stat = unname(lb12$statistic), ljung_box_lag12_df = unname(lb12$parameter),
      ljung_box_lag12_p = lb12$p.value, ljung_box_lag24_stat = unname(lb24$statistic),
      ljung_box_lag24_df = unname(lb24$parameter), ljung_box_lag24_p = lb24$p.value)
  }))
  save_csv(diagnostics, "residual_diagnostics")
  save_csv(do.call(rbind, residual_sd_by_decade), "residual_sd_by_decade")

  # ---- Task 3: test-forecast plots, one per model --------------------------------------
  # Fan chart: history, forecast mean, 80%/95% bands joined to the last observed month,
  # and optional actuals drawn after the forecast origin.
  draw_fan <- function(fc, origin_n, h, color, heading, subheading, history_from,
                       actual = NULL, actual_label = "", unscored_from = NULL) {
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
    y_range[2] <- y_range[2] + .12 * diff(y_range)   # room for the legend
    plot(range(model_data$date[past], dates), y_range, type = "n", xlab = "Month",
      ylab = "U.S. dollars per dozen", main = heading)
    if (!is.null(unscored_from)) {
      u <- par("usr")
      rect(unscored_from, u[3], u[2], u[4], col = "#f1f5f9", border = NA)
      text(unscored_from, u[4] - .07 * diff(u[3:4]), "No actuals:\nunscored extrapolation",
        pos = 4, cex = .75, col = "#475569")
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
    legend("topleft", c("Observed price used for fitting", "Forecast mean", "80% prediction interval",
      "95% prediction interval", if (!is.null(actual)) actual_label),
      col = c(HISTORY_COLOR, color, BAND_80, BAND_95, if (!is.null(actual)) ACTUAL_COLOR),
      lwd = c(2, 2.5, 8, 8, if (!is.null(actual)) 2), bty = "n", cex = .8,
      ncol = if (h > 24L) 1 else 2)
    mtext(subheading, side = 3, line = .35, cex = .8)
  }
  test_actual_df <- data.frame(date = test_dates, price = test_actual)
  for (m in MODELS) {
    s <- test_scores[test_scores$model == m, ]
    figure(paste0("06_test_forecast_", slug(m)), function() {
      draw_fan(test_fc[[m]], N_TRAIN, N_TEST, MODEL_COLORS[m],
        paste0(m, " (", describe_fit(test_fits[[m]]), "): test forecast for 2014"),
        sprintf("Fitted on Jan 1980-Dec 2013 only | 2014 test: RMSE $%.4f, MAE $%.4f, MAPE %.2f%%, MASE %.3f",
          s$RMSE, s$MAE, s$MAPE, s$MASE),
        "2011-01-01", test_actual_df, "Held-out 2014 actual (test data)")
    })
  }

  # ---- Task 4: comparison figures -----------------------------------------------------
  figure("07_test_comparison", function() {
    layout(matrix(1:2, 2), heights = c(3, 2))
    par(mar = c(2.5, 5, 4, 1))
    past <- which(model_data$date >= as.Date("2013-01-01") & seq_len(nrow(model_data)) <= N_TRAIN)
    origin <- model_data$date[N_TRAIN]
    y_range <- range(model_data$price[c(past, test_id)], sapply(test_fc, function(fc) as.numeric(fc$mean)))
    y_range[2] <- y_range[2] + .1 * diff(y_range)
    plot(range(model_data$date[past], test_dates), y_range, type = "n", xlab = "",
      ylab = "U.S. dollars per dozen", main = "Both models against the 2014 test data")
    lines(model_data$date[c(past, test_id)], model_data$price[c(past, test_id)], col = HISTORY_COLOR, lwd = 2)
    points(test_dates, test_actual, pch = 16, col = HISTORY_COLOR)
    abline(v = origin, col = "#64748b", lty = 2)
    for (m in MODELS) {
      lines(c(origin, test_dates), c(model_data$price[N_TRAIN], test_fc[[m]]$mean),
        col = MODEL_COLORS[m], lwd = 2.5, lty = MODEL_LTY[m])
    }
    legend("topleft", c("Observed (2014 = test data)", paste(MODELS, "forecast")),
      col = c(HISTORY_COLOR, MODEL_COLORS[MODELS]), lty = c(1, MODEL_LTY[MODELS]), lwd = 2.5,
      bg = "white", box.col = "white", inset = .01, cex = .8, ncol = 3)
    par(mar = c(4.5, 5, 2.5, 1))
    err <- sapply(MODELS, function(m) test_predictions$error[test_predictions$model == m])
    plot(range(test_dates), range(err, 0), type = "n", xlab = "Month",
      ylab = "Actual minus forecast ($)", main = "Monthly test error (positive = forecast too low)")
    abline(h = 0, col = "#334155")
    for (m in MODELS) {
      lines(test_dates, err[, m], col = MODEL_COLORS[m], lwd = 2, lty = MODEL_LTY[m])
      points(test_dates, err[, m], col = MODEL_COLORS[m], pch = if (m == MODELS[1]) 17 else 16)
    }
    legend("topleft", MODELS, col = MODEL_COLORS[MODELS], lty = MODEL_LTY[MODELS], lwd = 2,
      pch = c(17, 16), bty = "n", cex = .8, ncol = 2)
  }, height = 1300L)
  figure("08_accuracy_comparison", function() {
    par(mfrow = c(1, 3), mar = c(4.5, 5, 4, 1), oma = c(0, 0, 2, 0))
    s <- test_scores[match(MODELS, test_scores$model), ]
    panels <- list(list(cols = c("ME", "MAE", "RMSE"), ylab = "U.S. dollars per dozen", fmt = "%.4f"),
      list(cols = "MAPE", ylab = "Percent", fmt = "%.2f"), list(cols = "MASE", ylab = "Ratio (no units)", fmt = "%.3f"))
    for (p in panels) {
      # Rows = models (bars), columns = measures (groups).
      v <- as.matrix(s[, p$cols, drop = FALSE])
      rownames(v) <- MODELS
      lim <- range(0, v) * 1.25
      bars <- barplot(v, beside = TRUE, col = MODEL_COLORS[MODELS], border = NA, ylim = lim,
        ylab = p$ylab, main = paste(p$cols, collapse = ", "), xlab = "Error measure")
      abline(h = 0, col = "#334155")
      text(bars, v, sprintf(p$fmt, v), pos = ifelse(v >= 0, 3, 1), cex = .75)
    }
    legend("topright", MODELS, fill = MODEL_COLORS[MODELS], border = NA, bty = "n", cex = .85)
    mtext("2014 test-year error measures (12 forecasts from a Dec 2013 origin): lower is better; for ME, closer to 0", side = 3,
      outer = TRUE, line = .3, font = 2, col = HISTORY_COLOR)
  }, height = 900L, width = 1800L)

  # ---- Task 5: refit through Dec 2014 and forecast with the better model ----------------
  final_fits <- list("Damped Holt" = fit_one(series, "Damped Holt"),
                     "Seasonal ARIMA" = refit_arima(series))
  # Check only (not used): would a fresh search on data through Dec 2014 pick the same order?
  research <- search_arima(series)
  fc_long <- predict_one(final_fits[[better]], h = H_LONG)
  for (h in c(H_SHORT, H_YEAR)) {
    # The 6- and 12-month forecasts are the first rows of the same forecast path.
    fc_h <- predict_one(final_fits[[better]], h = h)
    stopifnot(isTRUE(all.equal(as.numeric(fc_h$mean), as.numeric(fc_long$mean)[seq_len(h)])),
      isTRUE(all.equal(as.numeric(fc_h$lower), as.numeric(fc_long$lower[seq_len(h), ]))),
      isTRUE(all.equal(as.numeric(fc_h$upper), as.numeric(fc_long$upper[seq_len(h), ]))))
  }
  fc_dates <- seq(as.Date("2015-01-01"), by = "month", length.out = H_LONG)

  # ---- Post-hoc only: compare the forecast with actual prices from Jan 2015 --------------
  # First and only use of post-2014 prices. Nothing below feeds back into a fit or the choice.
  posthoc <- full[full$date > DATA_END, ]
  forecast_table <- data.frame(model = better, date = fc_dates, horizon = seq_len(H_LONG),
    mean = as.numeric(fc_long$mean), lower80 = as.numeric(fc_long$lower[, "80%"]),
    upper80 = as.numeric(fc_long$upper[, "80%"]), lower95 = as.numeric(fc_long$lower[, "95%"]),
    upper95 = as.numeric(fc_long$upper[, "95%"]),
    actual_posthoc = posthoc$price[match(fc_dates, posthoc$date)])
  forecast_table$scored <- !is.na(forecast_table$actual_posthoc)
  forecast_table$error <- forecast_table$actual_posthoc - forecast_table$mean
  forecast_table$pct_error <- 100 * forecast_table$error / forecast_table$actual_posthoc
  forecast_table$in80 <- with(forecast_table, actual_posthoc >= lower80 & actual_posthoc <= upper80)
  forecast_table$in95 <- with(forecast_table, actual_posthoc >= lower95 & actual_posthoc <= upper95)
  n_scored <- sum(forecast_table$scored)
  stopifnot(nrow(posthoc) == 124L, n_scored == 124L, all(forecast_table$scored[1:124]),
    !any(forecast_table$scored[125:H_LONG]), max(fc_dates) == as.Date("2029-12-01"),
    all(is.finite(as.matrix(forecast_table[, 4:8]))),
    all(forecast_table$lower95 <= forecast_table$lower80), all(forecast_table$lower80 <= forecast_table$mean),
    all(forecast_table$mean <= forecast_table$upper80), all(forecast_table$upper80 <= forecast_table$upper95))
  save_csv(forecast_table[1:H_SHORT, ], "better_forecast_6_months")
  save_csv(forecast_table[1:H_YEAR, ], "better_forecast_12_months")
  save_csv(forecast_table, "better_forecast_180_months")
  gap_rows <- function(k, label) {
    z <- forecast_table[forecast_table$horizon <= k & forecast_table$scored, ]
    data.frame(window = label, model = better, months_scored = nrow(z),
      ME = mean(z$error), MAE = mean(abs(z$error)), RMSE = sqrt(mean(z$error^2)),
      MAPE = mean(abs(z$pct_error)), Coverage80 = mean(z$in80), Coverage95 = mean(z$in95),
      months_actual_above_forecast = sum(z$error > 0), mean_actual = mean(z$actual_posthoc),
      mean_forecast = mean(z$mean), note = "Post-hoc: actuals not used for fitting or choice")
  }
  gap_summary <- rbind(gap_rows(H_SHORT, "6 months: Jan-Jun 2015"),
    gap_rows(H_YEAR, "12 months: Jan-Dec 2015"),
    gap_rows(n_scored, "124 months: Jan 2015-Apr 2025 (all available actuals)"),
    data.frame(window = "Months 125-180: May 2025-Dec 2029", model = better, months_scored = 0L,
      ME = NA, MAE = NA, RMSE = NA, MAPE = NA, Coverage80 = NA, Coverage95 = NA,
      months_actual_above_forecast = NA, mean_actual = NA,
      mean_forecast = mean(forecast_table$mean[!forecast_table$scored]),
      note = "Unscored extrapolation: no actual prices exist for these months"))
  save_csv(gap_summary, "gap_summary")
  scored <- forecast_table[forecast_table$scored, ]
  scored$year <- as.integer(format(scored$date, "%Y"))
  gap_by_year <- do.call(rbind, lapply(split(scored, scored$year), function(z) {
    data.frame(year = z$year[1], months = nrow(z), mean_actual = mean(z$actual_posthoc),
      mean_forecast = mean(z$mean), ME = mean(z$error), MAE = mean(abs(z$error)),
      RMSE = sqrt(mean(z$error^2)), months_actual_above_forecast = sum(z$error > 0),
      Coverage80 = mean(z$in80), Coverage95 = mean(z$in95))
  }))
  save_csv(gap_by_year, "gap_by_year")
  final_label <- describe_fit(final_fits[[better]])
  horizon_plots <- list(
    list(name = "09_better_forecast_6_months", h = H_SHORT, from = "2010-01-01", what = "6-month"),
    list(name = "10_better_forecast_12_months", h = H_YEAR, from = "2010-01-01", what = "12-month"),
    list(name = "11_better_forecast_180_months", h = H_LONG, from = "2000-01-01", what = "180-month (15-year)"))
  for (p in horizon_plots) {
    rows <- forecast_table[seq_len(p$h), ]
    shown <- rows[rows$scored, c("date", "actual_posthoc")]
    names(shown) <- c("date", "price")
    g <- gap_rows(p$h, "")
    unscored <- if (p$h > n_scored) fc_dates[n_scored + 1L] else NULL
    heading <- paste0(better, " ", p$what, " forecast from Dec 2014: ", month_label(rows$date))
    figure(paste0(p$name, "_clean"), function() {
      draw_fan(fc_long, nrow(model_data), p$h, MODEL_COLORS[better], heading,
        paste0(final_label, " fitted on Jan 1980-Dec 2014 | point forecast with 80% and 95% prediction intervals"),
        p$from)
    })
    figure(p$name, function() {
      draw_fan(fc_long, nrow(model_data), p$h, MODEL_COLORS[better], heading,
        sprintf("Post-hoc check on %d months with actuals: RMSE $%.3f, MAE $%.3f, 95%% coverage %.0f%%%s",
          g$months_scored, g$RMSE, g$MAE, 100 * g$Coverage95,
          if (is.null(unscored)) "" else "; May 2025-Dec 2029 unscored"),
        p$from, shown, "Actual price (post-hoc only, never used in fitting)", unscored)
    })
  }
  figure("12_gap_by_year", function() {
    gap_span <- diff(range(0, gap_by_year$ME))   # padding so the value labels are not clipped
    bars <- barplot(gap_by_year$ME, names.arg = ifelse(gap_by_year$months < 12,
      paste0(gap_by_year$year, "*"), gap_by_year$year), border = NA,
      col = ifelse(gap_by_year$ME >= 0, ACTUAL_COLOR, "#2563eb"),
      ylim = range(0, gap_by_year$ME) + c(-.1, .1) * gap_span, xlab = "Calendar year",
      ylab = "Mean of actual minus forecast ($/dozen)",
      main = paste0("Post-hoc gap by year: actual price minus the ", better, " projection"))
    abline(h = 0, col = "#334155")
    text(bars, gap_by_year$ME, sprintf("%.2f", gap_by_year$ME), pos = ifelse(gap_by_year$ME >= 0, 3, 1), cex = .75)
    legend("topleft", c("Actual above projection", "Actual below projection"),
      fill = c(ACTUAL_COLOR, "#2563eb"), border = NA, bty = "n", cex = .8)
    mtext("Forecast error of a pre-2015 model (outbreaks, inflation, feed costs, cage-free rules), not a causal estimate | * 2025 = Jan-Apr only",
      side = 3, line = .35, cex = .72)
  })

  # ---- Fitted structures and parameters ---------------------------------------------
  stages <- list(
    list(stage = "Test fit", fits = test_fits, end = TRAIN_END, n = N_TRAIN),
    list(stage = "Final fit", fits = final_fits, end = DATA_END, n = nrow(model_data)))
  how_chosen <- c("Damped Holt" = "ETS(A,Ad,N) set by the team; parameters by maximum likelihood",
    "Seasonal ARIMA" = "auto.arima seasonal search (AICc, stepwise, exact ML) on the training data")
  structures <- do.call(rbind, lapply(stages, function(s) {
    do.call(rbind, lapply(MODELS, function(m) {
      fit <- s$fits[[m]]
      how <- if (m == "Seasonal ARIMA" && s$stage == "Final fit") {
        paste("Order fixed from the training search; coefficients re-estimated by ML")
      } else how_chosen[[m]]
      data.frame(stage = s$stage, model = m, structure = describe_fit(fit), how_chosen = how,
        fit_start = "1980-01-01", fit_end = format(s$end), months = length(fit$x),
        log_likelihood = fit$loglik, AIC = fit$aic, AICc = fit$aicc, BIC = fit$bic,
        sigma = sqrt(fit$sigma2), row.names = NULL)
    }))
  }))
  structures <- rbind(structures, data.frame(stage = "Check only (not used)", model = "Seasonal ARIMA",
    structure = describe_fit(research),
    how_chosen = "Fresh auto.arima search on Jan 1980-Dec 2014, to see if the fixed order still wins",
    fit_start = "1980-01-01", fit_end = format(DATA_END), months = length(research$x),
    log_likelihood = research$loglik, AIC = research$aic, AICc = research$aicc, BIC = research$bic,
    sigma = sqrt(research$sigma2)))
  save_csv(structures, "model_structures")
  meaning <- c(alpha = "Level smoothing weight", beta = "Slope smoothing weight",
    phi = "Damping factor applied to the slope each month", l = "Initial level, Jan 1980 ($/dozen)",
    b = "Initial slope ($/dozen per month)", ar1 = "AR(1) coefficient on the monthly price change",
    sar1 = "Seasonal AR coefficient at lag 12 months", sar2 = "Seasonal AR coefficient at lag 24 months",
    drift = "Drift ($/dozen per month)", intercept = "Mean")
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
      data.frame(stage = s$stage, model = m, parameter = c(names(est), "sigma"),
        estimate = c(as.numeric(est), sqrt(fit$sigma2)), std_error = c(as.numeric(se), NA),
        meaning = c(unname(meaning[names(est)]), "Residual standard deviation ($/dozen)"),
        note = c(flag, ""), row.names = NULL)
    }))
  }))
  save_csv(parameters, "model_parameters")

  # ---- Leakage checks: what each fit was allowed to see ----------------------------------
  saw_exactly <- function(fit, n) {
    x <- fit$x
    end_month <- c(as.integer(format(model_data$date[n], "%Y")), as.integer(format(model_data$date[n], "%m")))
    length(x) == n && identical(as.numeric(x), model_data$price[seq_len(n)]) &&
      all(end(x) == end_month)
  }
  leakage <- data.frame(check = c(
      "Damped Holt test fit saw exactly Jan 1980-Dec 2013 (408 months, no 2014 values)",
      "Seasonal ARIMA test fit saw exactly Jan 1980-Dec 2013 (408 months, no 2014 values)",
      "Seasonal ARIMA order search ran on Jan 1980-Dec 2013 only",
      "Damped Holt final fit saw exactly Jan 1980-Dec 2014 (420 months, nothing after 2014)",
      "Seasonal ARIMA final fit saw exactly Jan 1980-Dec 2014 (420 months, nothing after 2014)",
      "Check-only research fit saw exactly Jan 1980-Dec 2014",
      "Every model input series ends on or before Dec 2014",
      "Test scores (and so the model choice) use only Jan-Dec 2014 actuals, 12 per model",
      "Sensitivity fits each end on or before Dec 2013"),
    passed = c(saw_exactly(test_fits[["Damped Holt"]], N_TRAIN),
      saw_exactly(test_fits[["Seasonal ARIMA"]], N_TRAIN),
      length(test_fits[["Seasonal ARIMA"]]$x) == N_TRAIN,
      saw_exactly(final_fits[["Damped Holt"]], nrow(model_data)),
      saw_exactly(final_fits[["Seasonal ARIMA"]], nrow(model_data)),
      saw_exactly(research, nrow(model_data)), max(model_data$date) == DATA_END,
      nrow(test_predictions) == 2L * N_TEST && all(test_predictions$date %in% test_dates), NA))

  # ---- Sensitivity check (context only, not used to choose) -------------------------------
  # Same procedure as the main test, repeated for each calendar year 2005-2014:
  # fit through the previous December, forecast 12 months, score both models.
  other_years <- do.call(rbind, lapply(2005:2014, function(year) {
    n_fit <- which(model_data$date == as.Date(sprintf("%d-12-01", year - 1L)))
    y <- ts(model_data$price[seq_len(n_fit)], start = c(1980, 1), frequency = 12)
    actual <- model_data$price[n_fit + seq_len(12L)]
    dh <- fit_one(y, "Damped Holt")
    sa <- search_arima(y)
    stopifnot(length(dh$x) == n_fit, length(sa$x) == n_fit, n_fit <= N_TRAIN)
    e_dh <- measures(actual, as.numeric(predict_one(dh, h = 12L)$mean))
    e_sa <- measures(actual, as.numeric(predict_one(sa, h = 12L)$mean))
    data.frame(test_year = year, fit_end = format(model_data$date[n_fit]),
      arima_order_found = describe_fit(sa), damped_holt_phi = unname(dh$par["phi"]),
      RMSE_damped_holt = e_dh$RMSE, RMSE_seasonal_arima = e_sa$RMSE,
      MAE_damped_holt = e_dh$MAE, MAE_seasonal_arima = e_sa$MAE,
      lower_RMSE = if (e_sa$RMSE < e_dh$RMSE) "Seasonal ARIMA" else "Damped Holt")
  }))
  # The 2014 row repeats the main test exactly.
  stopifnot(isTRUE(all.equal(other_years$RMSE_seasonal_arima[other_years$test_year == 2014],
      test_scores$RMSE[test_scores$model == "Seasonal ARIMA"])),
    isTRUE(all.equal(other_years$RMSE_damped_holt[other_years$test_year == 2014],
      test_scores$RMSE[test_scores$model == "Damped Holt"])))
  save_csv(other_years, "sensitivity_other_test_years")
  leakage$passed[nrow(leakage)] <- all(as.Date(other_years$fit_end) <= TRAIN_END)
  save_csv(leakage, "leakage_checks")
  stopifnot(all(leakage$passed))

  # ---- Reproducibility outputs and the file guide -------------------------------------------
  saveRDS(list(test_fits = test_fits, test_forecasts = test_fc, final_fits = final_fits,
    better = better, arima_order = arima_order, forecast_180 = fc_long),
    file.path(out, "fitted_models.rds"))
  writeLines(trimws(capture.output(sessionInfo()), which = "right"), file.path(out, "session_info.txt"))
  show <- function(x, digits = 4) print(x, row.names = FALSE, digits = digits)
  capture.output({
    cat("FINAL TWO-MODEL STUDY: DAMPED HOLT AND SEASONAL ARIMA\n")
    cat("Training Jan 1980-Dec 2013 (408 months); test Jan-Dec 2014 (12 months); no validation set.\n\n")
    cat("Seasonal ARIMA order from the training search:", arima_found, "\n")
    cat("Fresh search on data through Dec 2014 (check only):", describe_fit(research), "\n\n")
    cat("2014 TEST ACCURACY\n"); show(test_scores[, -2])
    cat("\nTRAINING FIT (one-step-ahead, in-sample)\n"); show(train_scores[, -2])
    cat("\nBY HALF OF THE TEST YEAR (same forecasts)\n"); show(by_half)
    cat("\nBETTER MODEL:", better, "| decided by", decided_by, "| rule:", better_table$rule, "\n")
    cat("\nRESIDUAL DIAGNOSTICS (training fits)\n"); show(diagnostics[, c("model", "sd", "acf_lag1",
      "acf_lag12", "acf_lag24", "ljung_box_lag12_p", "ljung_box_lag24_p")])
    cat("\nPARAMETERS\n"); show(parameters[, c("stage", "model", "parameter", "estimate", "std_error")])
    cat("\nPOST-HOC GAP SUMMARY (", better, ")\n", sep = ""); show(gap_summary[, -c(2, 13)])
    cat("\nGAP BY YEAR\n"); show(gap_by_year)
    cat("\nSENSITIVITY: OTHER SINGLE TEST YEARS (context only)\n"); show(other_years)
    cat("\nLEAKAGE CHECKS\n"); show(leakage)
    cat("\nLowest 95% bound over 180 months:", sprintf("%.3f", min(forecast_table$lower95)), "\n")
  }, file = file.path(out, "results.txt"))
  file_guide <- data.frame(file = c("data_check.csv", "exploration_summary.csv",
      "exploration_by_decade.csv", "accuracy_table.csv", "test_predictions_2014.csv",
      "test_accuracy_by_half_year.csv", "better_model.csv", "residual_diagnostics.csv",
      "residual_sd_by_decade.csv", "model_structures.csv", "model_parameters.csv",
      "better_forecast_6_months.csv", "better_forecast_12_months.csv", "better_forecast_180_months.csv",
      "gap_summary.csv", "gap_by_year.csv", "sensitivity_other_test_years.csv", "leakage_checks.csv",
      "results.txt", "session_info.txt", "fitted_models.rds", "file_guide.csv",
      "figures/01_history_with_cuts.png", "figures/02_correlogram.png",
      "figures/03_stl_decomposition.png", "figures/04_seasonal_by_month.png",
      paste0("figures/05_residuals_", slug(MODELS), ".png"),
      paste0("figures/06_test_forecast_", slug(MODELS), ".png"),
      "figures/07_test_comparison.png", "figures/08_accuracy_comparison.png",
      paste0("figures/", c("09_better_forecast_6_months", "10_better_forecast_12_months",
        "11_better_forecast_180_months"), rep(c("", "_clean"), each = 3), ".png"),
      "figures/12_gap_by_year.png"),
    contents = c("Completeness checks of the source file and the month counts per split",
      "Training-data exploration numbers: ACF/PACF values, STL strengths, peak and trough months, ndiffs",
      "Mean price and monthly-change spread by decade (training data)",
      "ME, MAE, RMSE, MAPE, MASE and interval coverage: 2014 test and one-step training fit",
      "Each 2014 test month: actual, both forecasts, errors and 80%/95% intervals",
      "Same 2014 test forecasts scored on Jan-Jun and Jul-Dec separately",
      "The better model, the stated tie rule and which measures each model won",
      "Residual mean, sd, skewness, kurtosis, ACF at lags 1/12/24 and Ljung-Box tests",
      "Residual sd by decade for each model (training fit)",
      "Model form, fit window, log-likelihood, AIC/AICc/BIC and sigma for each fit",
      "Estimated parameters (alpha, beta, phi; AR coefficients with standard errors)",
      "Better model, Jan-Jun 2015 forecast and intervals, with post-hoc actuals",
      "Better model, Jan-Dec 2015 forecast and intervals, with post-hoc actuals",
      "Better model, Jan 2015-Dec 2029; months after Apr 2025 are marked unscored",
      "Post-hoc gap at 6, 12 and 124 months (ME, MAE, RMSE, MAPE, coverage); 56 months unscored",
      "Post-hoc gap by calendar year 2015-2025 (2025 = Jan-Apr)",
      "Context only: both models re-run with test years 2005-2014 (not used to choose)",
      "Assertions that no 2014 value entered the test fits and no post-2014 value entered any fit",
      "Plain-text summary of the main tables", "R and package versions",
      "Saved model objects (readRDS)", "This file",
      "Full 1980-2025 price history with the test year and post-hoc period marked",
      "ACF and PACF of training prices and of monthly price changes",
      "STL decomposition of training prices", "Month-by-year view and average seasonal effect",
      paste(MODELS, "training residuals: time plot, histogram, ACF, Q-Q"),
      paste(MODELS, "2014 test forecast with intervals and the test data"),
      "Both 2014 test forecasts and monthly errors on one figure",
      "Bar chart of the 2014 error measures for both models",
      paste("Better model forecast with intervals and post-hoc actuals:", c("6", "12", "180"), "months"),
      paste("Better model forecast with intervals, no actuals:", c("6", "12", "180"), "months"),
      "Signed post-hoc gap by year"),
    pdf_task = c("Task 2", "Task 2", "Task 2 / Task 6 confidence", "Task 3 / Task 4", "Task 3",
      "Task 4", "Task 4", "Task 3 / Task 4", "Task 6 confidence", "Task 3 parameters",
      "Task 3 / Task 5 parameters", "Task 5", "Task 5", "Task 5", "Task 6 confidence", "Task 6 confidence",
      "Task 4 caveat", "Method integrity", "All", "Reproducibility", "Reproducibility", "Index",
      "Task 2", "Task 2", "Task 2", "Task 2", "Task 3", "Task 3", "Task 3", "Task 3",
      "Task 4", "Task 4", rep("Task 5 / Task 6", 6), "Task 6 confidence"))
  save_csv(file_guide, "file_guide")
  produced <- list.files(out, recursive = TRUE)
  stopifnot(all(file.exists(file.path(out, file_guide$file))), all(produced %in% file_guide$file))
  cat("\n2014 TEST:\n"); show(test_scores[, -2])
  cat("\nBetter model:", better, "\nGAP:\n"); show(gap_summary[, c(1, 3:9)])
  cat("\nSaved to", out, "\n")
}

run_final_two_models()
