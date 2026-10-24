# Six-month validation and testing in 2014, with all nine models.
# Model data ends in December 2014; the full 1980-2025 plot remains available.

run_forecast <- function() {
  # ---- Load the same reusable settings and modeling functions ----------------
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
  old_out <- Sys.getenv("EGG_FORECAST_OUTPUT", unset = NA_character_)
  on.exit({
    if (is.na(old_out)) Sys.unsetenv("EGG_FORECAST_OUTPUT") else {
      Sys.setenv(EGG_FORECAST_OUTPUT = old_out)
    }
  }, add = TRUE)
  out <- Sys.getenv("EGG_FORECAST_OUTPUT", unset = file.path(root, "results"))
  Sys.setenv(EGG_FORECAST_OUTPUT = out)
  source(file.path(root, "analysis", "helpers.R"), local = TRUE)
  H <- 6L
  N_VALIDATION <- 6L
  N_TEST <- 6L
  ANALYSIS_END <- as.Date("2014-12-01")
  ARIMA_METHODS <- c("ARIMA", "Seasonal ARIMA search")
  ALL_METHODS <- c(METHODS, ARIMA_METHODS)
  COLORS <- c(COLORS, "ARIMA" = "#0891b2", "Seasonal ARIMA search" = "#65a30d")

  # ---- Import the original complete snapshot ---------------------------------
  raw <- read.csv(INPUT, stringsAsFactors = FALSE)
  stopifnot(identical(names(raw), c("observation_date", "APU0000708111")))
  d <- data.frame(date = as.Date(raw$observation_date), price = as.numeric(raw$APU0000708111))
  stopifnot(!anyNA(d), !anyDuplicated(d$date), all(is.finite(d$price)),
    all(d$price > 0), !is.unsorted(d$date), nrow(d) == 544L,
    min(d$date) == as.Date("1980-01-01"), max(d$date) == as.Date("2025-04-01"),
    identical(d$date, seq(min(d$date), max(d$date), by = "month")))
  d$observed <- TRUE
  full_data <- d
  # Keep later observations for the full-history graph only. Every fit,
  # selection score, diagnostic and evaluation below uses the truncated data.
  d <- full_data[full_data$date <= ANALYSIS_END, ]
  n <- nrow(d)
  train_n <- n - N_VALIDATION - N_TEST
  dev_n <- n - N_TEST
  val_id <- seq.int(train_n + 1L, dev_n)
  test_id <- seq.int(dev_n + 1L, n)
  series <- ts(d$price, start = c(1980, 1), frequency = 12)
  splits <- data.frame(split = c("Training", "Validation", "Test"),
    start = d$date[c(1, train_n + 1L, dev_n + 1L)], end = d$date[c(train_n, dev_n, n)],
    calendar_months = c(train_n, N_VALIDATION, N_TEST),
    observed_months = c(train_n, N_VALIDATION, N_TEST))
  stopifnot(n == 420L, train_n == 408L, dev_n == 414L,
    identical(d$date[val_id], seq(as.Date("2014-01-01"), as.Date("2014-06-01"), by = "month")),
    identical(d$date[test_id], seq(as.Date("2014-07-01"), as.Date("2014-12-01"), by = "month")))
  data_quality <- data.frame(observations = n, first_date = min(d$date), last_date = max(d$date),
    missing_months = 0, missing_prices = 0, duplicate_dates = 0, imputed_values = 0,
    source_observations = nrow(full_data), source_last_date = max(full_data$date),
    excluded_after_cutoff = sum(full_data$date > ANALYSIS_END),
    source_md5 = unname(tools::md5sum(INPUT)))
  save_csv(splits, "data_splits")
  save_csv(data_quality, "data_quality")
  save_csv(d, "monthly_calendar")
  save_csv(full_data, "full_monthly_calendar")
  save_csv(data.frame(boundary = c("Validation begins", "Test begins", "Excluded data begins"),
    date = c(min(d$date[val_id]), min(d$date[test_id]), as.Date("2015-01-01"))), "plot_cut_dates")
  # One full-history graph contains all three cut lines; no separate zoom.
  figure("00_history", function() draw_data_split(full_data, splits, ANALYSIS_END))
  if (Sys.getenv("EGG_PLOTS_ONLY", "0") == "1") {
    cat("Saved full-history graph with 2014 cut lines to", FIG, "\n")
    return(invisible(splits))
  }
  fit_history <- function(end) ts(as.numeric(series)[seq_len(end)], start = start(series), frequency = 12)
  date_label <- function(dates) paste(format(min(dates), "%b %Y"), "to", format(max(dates), "%b %Y"))

  # ---- Model fitting: six-step forecasts with no post-2014 observations -------
  fit_any <- function(y, method) {
    if (method %in% ARIMA_METHODS) {
      forecast::auto.arima(y, seasonal = method == "Seasonal ARIMA search",
        ic = "aicc", stepwise = TRUE, approximation = FALSE, method = "ML",
        lambda = 0, biasadj = TRUE, trace = FALSE)
    } else fit_one(y, method, H)
  }
  fit_stage <- function(end, label) {
    setNames(lapply(ALL_METHODS, function(method) {
      cat("Fitting", label, "/", method, "...\n")
      y <- fit_history(end)
      fit_any(y, method)
    }), ALL_METHODS)
  }
  # Scale MASE by the historical seasonal-naive error in this fitting window.
  seasonal_scale <- function(end) {
    y <- as.numeric(series)[seq_len(end)]
    mean(abs(y[13:length(y)] - y[seq_len(length(y) - 12L)]), na.rm = TRUE)
  }
  accuracy <- function(fcs, ids, fitting_end) {
    actual <- d$price[ids]
    rows <- lapply(names(fcs), function(method) {
      fc <- fcs[[method]]
      error <- actual - as.numeric(fc$mean)
      mae <- mean(abs(error))
      data.frame(model = method, ME = mean(error), MAE = mae,
        RMSE = sqrt(mean(error^2)), MAPE = 100 * mean(abs(error / actual)),
        MASE = mae / seasonal_scale(fitting_end),
        Coverage80 = mean(actual >= fc$lower[, "80%"] & actual <= fc$upper[, "80%"]),
        Coverage95 = mean(actual >= fc$lower[, "95%"] & actual <= fc$upper[, "95%"]),
        observed_months = length(ids), horizon_months = H, row.names = NULL)
    })
    tab <- do.call(rbind, rows)
    tab[order(tab$RMSE), ]
  }
  train_models <- fit_stage(train_n, paste("training through", format(d$date[train_n], "%B %Y")))
  validation <- lapply(train_models, predict_one, h = H)
  validation_scores <- accuracy(validation, val_id, train_n)
  selected <- validation_scores$model[1]
  cat("Locked validation choice:", selected, "\n")
  test_models <- fit_stage(dev_n, paste("test origin", format(d$date[dev_n], "%B %Y")))
  test <- lapply(test_models, predict_one, h = H)
  test_scores <- accuracy(test, test_id, dev_n)
  # Every method is refitted for its own January-June 2015 forecast, not just
  # the validation winner. The winner remains a clearly separate statement.
  final_models <- fit_stage(n, paste("final origin", format(max(d$date), "%B %Y")))
  final <- lapply(final_models, predict_one, h = H)
  save_csv(validation_scores, "validation_accuracy")
  save_csv(test_scores, "test_accuracy")
  evaluation <- rbind(prediction_rows(validation, val_id, "Validation", d),
                       prediction_rows(test, test_id, "Test", d))
  evaluation$horizon <- rep(seq_len(H), length(ALL_METHODS) * 2L)
  save_csv(evaluation, "evaluation_predictions")
  future <- seq(max(d$date), by = "month", length.out = H + 1L)[-1L]
  forecast_table <- do.call(rbind, lapply(ALL_METHODS, function(method) {
    fc <- final[[method]]
    data.frame(model = method, date = future, horizon = seq_len(H),
      mean = as.numeric(fc$mean), lower80 = as.numeric(fc$lower[, "80%"]),
      upper80 = as.numeric(fc$upper[, "80%"]), lower95 = as.numeric(fc$lower[, "95%"]),
      upper95 = as.numeric(fc$upper[, "95%"]), row.names = NULL)
  }))
  stopifnot(nrow(forecast_table) == length(ALL_METHODS) * H,
    nrow(evaluation) == length(ALL_METHODS) * (N_VALIDATION + N_TEST),
    max(evaluation$date) <= ANALYSIS_END,
    all(is.finite(as.matrix(forecast_table[, 4:8]))),
    all(forecast_table$lower95 <= forecast_table$lower80),
    all(forecast_table$lower80 <= forecast_table$upper80),
    all(forecast_table$upper80 <= forecast_table$upper95))
  save_csv(forecast_table, "forecast_6_months_all_models")
  wide <- data.frame(model = ALL_METHODS)
  for (date in future) {
    z <- forecast_table[forecast_table$date == as.Date(date, origin = "1970-01-01"), ]
    wide[[format(as.Date(date, origin = "1970-01-01"), "%b_%Y")]] <- z$mean[match(ALL_METHODS, z$model)]
  }
  save_csv(wide, "forecast_means_by_model")

  # ---- Added: 12-month forecast, long projection and gap analysis -------------
  # Same final models (fit through Dec 2014). Naive/Seasonal naive fix h at fit
  # time, so they are refitted per horizon. Post-2014 actuals are used only for
  # the after-the-fact gap table, never for fitting, selection or scoring.
  H_LONG <- sum(full_data$date > ANALYSIS_END)  # Jan 2015 - Apr 2025 = 124
  forecast_horizon <- function(h) {
    dates <- seq(max(d$date), by = "month", length.out = h + 1L)[-1L]
    do.call(rbind, lapply(ALL_METHODS, function(method) {
      fc <- if (method %in% c("Naive", "Seasonal naive")) fit_one(fit_history(n), method, h)
            else predict_one(final_models[[method]], h = h)
      data.frame(model = method, date = dates, horizon = seq_len(h),
        mean = as.numeric(fc$mean), lower80 = as.numeric(fc$lower[, "80%"]),
        upper80 = as.numeric(fc$upper[, "80%"]), lower95 = as.numeric(fc$lower[, "95%"]),
        upper95 = as.numeric(fc$upper[, "95%"]), row.names = NULL)
    }))
  }
  forecast_12 <- forecast_horizon(12L)
  projection <- forecast_horizon(H_LONG)
  stopifnot(nrow(forecast_12) == length(ALL_METHODS) * 12L,
    nrow(projection) == length(ALL_METHODS) * H_LONG,
    all(is.finite(as.matrix(projection[, 4:8]))),
    all(projection$lower95 <= projection$upper95))
  save_csv(forecast_12, "forecast_12_months_all_models")
  save_csv(projection, "projection_2015_2025_all_models")
  gap_of <- function(tab) {
    g <- merge(tab, full_data[, c("date", "price")], by = "date")
    g$error <- g$price - g$mean
    g$pct_error <- 100 * g$error / g$price
    g$in80 <- g$price >= g$lower80 & g$price <= g$upper80
    g$in95 <- g$price >= g$lower95 & g$price <= g$upper95
    g[order(g$model, g$date), ]
  }
  gap <- gap_of(projection)
  gap_summary <- do.call(rbind, lapply(
    list(`6 months` = 6L, `12 months` = 12L, `Full 2015-2025` = H_LONG), function(k) {
    z <- gap[gap$horizon <= k, ]
    do.call(rbind, lapply(ALL_METHODS, function(m) {
      s <- z[z$model == m, ]
      data.frame(window = NA, model = m, months = nrow(s), ME = mean(s$error),
        MAE = mean(abs(s$error)), RMSE = sqrt(mean(s$error^2)),
        MAPE = mean(abs(s$pct_error)), Coverage80 = mean(s$in80),
        Coverage95 = mean(s$in95), row.names = NULL)
    }))
  }))
  gap_summary$window <- rep(c("6 months", "12 months", "Full 2015-2025"), each = length(ALL_METHODS))
  save_csv(gap, "gap_vs_actual_by_month")
  save_csv(gap_summary, "gap_vs_actual_summary")
  cat("\nGAP VS ACTUAL (post-hoc, not used for selection)\n")
  print(gap_summary, row.names = FALSE)

  # ---- Fitted structures and parameter audit --------------------------------
  describe_fit <- function(fit) {
    if (inherits(fit, "Arima")) {
      a <- fit$arma
      label <- paste0("ARIMA(", a[1], ",", a[6], ",", a[2], ")")
      if (any(a[c(3, 4, 7)] > 0)) label <- paste0(label, "(", a[3], ",", a[7], ",", a[4], ")[", a[5], "]")
      if ("drift" %in% names(fit$coef)) label <- paste(label, "with drift")
      if ("intercept" %in% names(fit$coef)) label <- paste(label, "with mean")
      return(label)
    }
    if (inherits(fit, "forecast")) return(fit$method)
    fit$method
  }
  stages <- list(Training = train_models, Test = test_models, Final = final_models)
  structures <- do.call(rbind, lapply(names(stages), function(stage) {
    do.call(rbind, lapply(ALL_METHODS, function(method) {
      fit <- stages[[stage]][[method]]
      data.frame(stage = stage, model = method, structure = describe_fit(fit),
        AICc = if (is.null(fit$aicc)) NA_real_ else fit$aicc,
        convergence_code = if (inherits(fit, "Arima")) fit$code else NA_integer_,
        missing_treatment = "None required; complete observed data")
    }))
  }))
  save_csv(structures, "model_structures")
  parameters <- do.call(rbind, lapply(names(stages), function(stage) {
    do.call(rbind, lapply(ALL_METHODS, function(method) {
      fit <- stages[[stage]][[method]]
      values <- if (inherits(fit, "Arima")) fit$coef else if (inherits(fit, "ets")) fit$par else numeric(0)
      if (!length(values)) return(NULL)
      data.frame(stage = stage, model = method, parameter = names(values), estimate = as.numeric(values))
    }))
  }))
  save_csv(parameters, "model_parameters")

  # ---- Reusable plots in the established project colors ----------------------
  slug <- function(method) gsub(" ", "_", tolower(method))
  draw_one <- function(fc, origin, heading, actual_id = integer()) {
    dates <- seq(d$date[origin], by = "month", length.out = H + 1L)[-1L]
    past <- seq.int(max(1L, origin - 5L), origin)
    limits <- range(d$price[c(past, actual_id)], fc$lower, fc$upper, na.rm = TRUE)
    plot(c(d$date[past], dates), c(d$price[past], rep(NA_real_, H)), type = "n", ylim = limits,
      xlab = "Month", ylab = "U.S. dollars per dozen", main = heading)
    # The known origin has zero uncertainty; join each band to that anchor.
    band_dates <- c(d$date[origin], dates)
    for (level in c("95%", "80%")) {
      lower <- c(d$price[origin], fc$lower[, level])
      upper <- c(d$price[origin], fc$upper[, level])
      polygon(c(band_dates, rev(band_dates)), c(lower, rev(upper)),
        col = if (level == "95%") BAND_95 else BAND_80, border = NA)
    }
    lines(d$date[past], d$price[past], col = HISTORY_COLOR, lwd = 2)
    lines(c(d$date[origin], dates), c(d$price[origin], fc$mean), col = "#2563eb", lwd = 2.5)
    abline(v = d$date[origin], col = "#64748b", lty = 2)
    if (length(actual_id)) {
      # Connect the last training observation to the first held-out observation.
      observed_id <- c(origin, actual_id)
      lines(d$date[observed_id], d$price[observed_id], col = "#b45309", lwd = 2)
      points(d$date[actual_id], d$price[actual_id], pch = 16, col = "#b45309")
    }
    legend("topleft", c("Observed history", "Forecast mean", "80% prediction interval", "95% prediction interval",
      if (length(actual_id)) "Held-out actual"),
      col = c(HISTORY_COLOR, "#2563eb", BAND_80, BAND_95, if (length(actual_id)) "#b45309"),
      lwd = c(2, 2.5, 8, 8, if (length(actual_id)) 2), bty = "n", cex = .8)
  }
  draw_all <- function(fcs, origin, heading, actual_id = integer()) {
    dates <- seq(d$date[origin], by = "month", length.out = H + 1L)[-1L]
    past <- seq.int(max(1L, origin - 11L), origin)
    limits <- range(d$price[c(past, actual_id)], unlist(lapply(fcs, function(fc) as.numeric(fc$mean))), na.rm = TRUE)
    plot(c(d$date[past], dates), c(d$price[past], rep(NA_real_, H)), type = "l", col = HISTORY_COLOR,
      lwd = 2, ylim = limits, main = heading, xlab = "Month", ylab = "U.S. dollars per dozen")
    abline(v = d$date[origin], col = "#64748b", lty = 2)
    for (method in ALL_METHODS) {
      # Anchor forecasts at the last observed price; markers show forecast months only.
      lines(c(d$date[origin], dates), c(d$price[origin], fcs[[method]]$mean),
        col = COLORS[method], lwd = 2)
      points(dates, fcs[[method]]$mean, col = COLORS[method], pch = 16, cex = .5)
    }
    if (length(actual_id)) {
      observed_id <- c(origin, actual_id)
      lines(d$date[observed_id], d$price[observed_id], col = HISTORY_COLOR, lwd = 2.5)
      points(d$date[actual_id], d$price[actual_id], pch = 16, col = HISTORY_COLOR)
    }
    legend("topleft", c("Observed", ALL_METHODS), col = c(HISTORY_COLOR, COLORS[ALL_METHODS]),
      lty = 1, lwd = 2, bty = "n", ncol = 2, cex = .7)
  }
  figure("01_validation_all", function() draw_all(validation, train_n,
    paste("Six-month validation:", date_label(d$date[val_id])), val_id))
  figure("02_test_all", function() draw_all(test, dev_n,
    paste("Six-month test:", date_label(d$date[test_id])), test_id))
  figure("03_future_all", function() draw_all(final, n,
    paste("All nine models:", date_label(future))))
  # Added: long projection vs actual prices (post-hoc gap, not a no-outbreak claim).
  draw_gap <- function(method, heading) {
    p <- projection[projection$model == method, ]
    actual <- full_data[full_data$date > ANALYSIS_END, ]
    past <- d[d$date >= as.Date("2005-01-01"), ]
    plot(c(past$date, p$date), c(past$price, rep(NA_real_, nrow(p))), type = "n",
      ylim = range(past$price, actual$price, p$lower95, p$upper95),
      xlab = "Month", ylab = "U.S. dollars per dozen", main = heading)
    polygon(c(p$date, rev(p$date)), c(p$lower95, rev(p$upper95)), col = BAND_95, border = NA)
    polygon(c(p$date, rev(p$date)), c(p$lower80, rev(p$upper80)), col = BAND_80, border = NA)
    lines(past$date, past$price, col = HISTORY_COLOR, lwd = 2)
    lines(p$date, p$mean, col = "#2563eb", lwd = 2.5)
    lines(actual$date, actual$price, col = "#b45309", lwd = 2)
    abline(v = ANALYSIS_END, col = "#64748b", lty = 2)
    legend("topleft", c("History to Dec 2014", "Projection mean", "80% interval",
      "95% interval", "Actual (not used in fitting)"),
      col = c(HISTORY_COLOR, "#2563eb", BAND_80, BAND_95, "#b45309"),
      lwd = c(2, 2.5, 8, 8, 2), bty = "n", cex = .8)
  }
  figure("05_projection_selected", function() draw_gap(selected,
    paste0("Projection from Jan 2015 vs actual: ", selected,
      " (gap includes outbreaks and other post-2014 changes)")))
  figure("06_projection_naive", function() draw_gap("Naive",
    "Projection from Jan 2015 vs actual: Naive"))
  figure("04_accuracy_comparison", function() {
    par(mfrow = c(1, 2), mar = c(10, 5, 4, 1))
    for (stage in c("Validation", "Test")) {
      z <- if (stage == "Validation") validation_scores else test_scores
      bars <- barplot(z$RMSE, names.arg = z$model, col = COLORS[z$model], las = 2,
        cex.names = .7, ylim = c(0, max(z$RMSE) * 1.2),
        ylab = "RMSE (U.S. dollars per dozen)", main = paste(stage, "six-month RMSE"))
      text(bars, z$RMSE, sprintf("%.3f", z$RMSE), pos = 3, cex = .7)
    }
  })
  for (method in ALL_METHODS) {
    figure(paste0("validation_", slug(method)), function() draw_one(validation[[method]], train_n,
      paste(method, "validation:", date_label(d$date[val_id])), val_id))
    figure(paste0("test_", slug(method)), function() draw_one(test[[method]], dev_n,
      paste(method, "test:", date_label(d$date[test_id])), test_id))
    figure(paste0("future_", slug(method)), function() draw_one(final[[method]], n,
      paste(method, "forecast:", date_label(future))))
  }

  # ---- Exploration and residual diagnostics for the active report ------------
  training <- fit_history(train_n)
  figure("00_training_acf", function() {
    par(mfrow = c(1, 2))
    draw_acf(log(training), "Training log-price ACF", 48L)
    draw_acf(diff(log(training)), "Monthly log-change ACF", 48L, "#0f766e")
  })
  decomposition <- stl(log(training), s.window = "periodic", robust = TRUE)
  seasonal_strength <- max(0, 1 - var(decomposition$time.series[, "remainder"]) /
    var(decomposition$time.series[, "seasonal"] + decomposition$time.series[, "remainder"]))
  figure("00_training_stl", function() {
    plot(decomposition, main = "Training log-price STL decomposition", col = "#2563eb")
  }, height = 1200L)
  diagnostics <- do.call(rbind, lapply(ALL_METHODS, function(method) {
    fit <- train_models[[method]]
    residual <- as.numeric(residuals(fit))
    finite <- is.finite(residual)
    good <- residual[finite]
    unit <- if (method %in% c("Naive", "Seasonal naive")) "Dollar residual" else "Log-price innovation"
    df <- if (inherits(fit, "Arima")) sum(fit$arma[1:4]) else if (inherits(fit, "ets")) {
      sum(names(fit$par) %in% c("alpha", "beta", "gamma", "phi"))
    } else 0
    lb <- Box.test(good, lag = 24L, type = "Ljung-Box", fitdf = df)
    figure(paste0("residuals_", slug(method)), function() {
      par(mfrow = c(2, 2), mar = c(4.5, 4.5, 3, 1))
      plot(d$date[seq_len(train_n)][finite], good, type = "l", col = COLORS[method], lwd = 2,
        main = paste(method, "training residuals"), xlab = "Month", ylab = unit)
      abline(h = 0, lty = 2)
      hist(good, breaks = "FD", col = "#bfdbfe", border = "white", main = "Residual histogram", xlab = unit)
      draw_acf(good, "Residual ACF", color = COLORS[method])
      qqnorm(good, col = COLORS[method], pch = 16, cex = .6, main = "Normal Q-Q plot")
      qqline(good, col = "#b45309", lwd = 2)
    }, height = 1200L)
    data.frame(model = method, residual_scale = unit, mean = mean(good), sd = sd(good),
      lag = 24L, fitdf = df, ljung_box_p = lb$p.value)
  }))
  save_csv(diagnostics, "residual_diagnostics")
  # A manifest keeps the model appendix and exported images in the same order.
  plot_stages <- c("validation", "test", "future", "residuals")
  plot_labels <- c("Validation forecast", "Test forecast", "Historical future forecast",
    "Training residual diagnostics")
  individual_plots <- do.call(rbind, lapply(ALL_METHODS, function(method) {
    data.frame(model = method, stage = plot_stages, description = plot_labels,
      file = paste0("figures/", plot_stages, "_", slug(method), ".png"))
  }))
  stopifnot(all(file.exists(file.path(out, individual_plots$file))))
  save_csv(individual_plots, "individual_plot_manifest")
  save_csv(data.frame(seasonal_strength = seasonal_strength,
    log_acf_lag1 = as.numeric(acf(log(training), lag.max = 12, plot = FALSE)$acf)[2],
    log_acf_lag12 = as.numeric(acf(log(training), lag.max = 12, plot = FALSE)$acf)[13]), "exploration_summary")

  # ---- Evidence viewer and reproducibility outputs ---------------------------
  source(file.path(root, "analysis", "viewer.R"), local = TRUE)
  write_results_viewer(d, splits, data_quality, selected, validation_scores, test_scores,
    wide, ALL_METHODS, structures, diagnostics, seasonal_strength, FIG, out,
    val_id, test_id, future)
  saveRDS(list(splits = splits, training = train_models, validation = validation,
    test_models = test_models, test = test, selected = selected,
    final_models = final_models, final = final), file.path(out, "fitted_models.rds"))
  writeLines(trimws(capture.output(sessionInfo()), which = "right"), file.path(out, "session_info.txt"))
  capture.output({
    cat("2014 SIX-MONTH FORECAST EXPERIMENT: ALL NINE MODELS\n\n")
    print(splits, row.names = FALSE)
    cat("\nVALIDATION ACCURACY\n"); print(validation_scores, row.names = FALSE)
    cat("\nSelected by validation RMSE:", selected, "\n")
    cat("\nTEST ACCURACY\n"); print(test_scores, row.names = FALSE)
    cat("\nSIX-MONTH HISTORICAL FORECAST MEANS\n"); print(wide, row.names = FALSE)
    cat("\nDATA QUALITY\n"); print(data_quality, row.names = FALSE)
    cat("\nSix observations per evaluation window. All fitting and scoring data ends in December 2014.\n")
    cat("The full 1980-April 2025 graph is context only. Post-2014 actuals are not used.\n")
    cat("The January 2015 boundary is a study choice, not an estimated shock date.\n")
    cat("Original complete snapshot only. No missing or imputed prices.\n")
  }, file = file.path(out, "results.txt"))
  cat("\nVALIDATION:\n"); print(validation_scores, row.names = FALSE)
  cat("\nSelected:", selected, "\nTEST:\n"); print(test_scores, row.names = FALSE)
  cat("\nFUTURE MEANS:\n"); print(wide, row.names = FALSE)
  cat("\nSaved to", out, "\n")
}

run_forecast()
