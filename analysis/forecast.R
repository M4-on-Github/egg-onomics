# Three-month validation, testing and future forecasts for all nine models.
# Original complete monthly data through April 2025. No filling or test-based retuning.

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
  H <- 3L
  N_VALIDATION <- 3L
  N_TEST <- 3L
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
  data_quality <- data.frame(observations = n, first_date = min(d$date), last_date = max(d$date),
    missing_months = 0, missing_prices = 0, duplicate_dates = 0, imputed_values = 0,
    source_md5 = unname(tools::md5sum(INPUT)))
  save_csv(splits, "data_splits")
  save_csv(data_quality, "data_quality")
  save_csv(d, "monthly_calendar")
  fit_history <- function(end) ts(as.numeric(series)[seq_len(end)], start = start(series), frequency = 12)
  date_label <- function(dates) paste(format(min(dates), "%b %Y"), "to", format(max(dates), "%b %Y"))

  # ---- Model fitting: same specifications, now using three-step forecasts ----
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
  # Every method is refitted for its own October-December forecast, not just
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
  stopifnot(nrow(forecast_table) == 27L, nrow(evaluation) == 54L,
    all(is.finite(as.matrix(forecast_table[, 4:8]))),
    all(forecast_table$lower95 <= forecast_table$lower80),
    all(forecast_table$lower80 <= forecast_table$upper80),
    all(forecast_table$upper80 <= forecast_table$upper95))
  save_csv(forecast_table, "forecast_3_months_all_models")
  wide <- data.frame(model = ALL_METHODS)
  for (date in future) {
    z <- forecast_table[forecast_table$date == as.Date(date, origin = "1970-01-01"), ]
    wide[[format(as.Date(date, origin = "1970-01-01"), "%b_%Y")]] <- z$mean[match(ALL_METHODS, z$model)]
  }
  save_csv(wide, "forecast_means_by_model")

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
    polygon(c(dates, rev(dates)), c(fc$lower[, "95%"], rev(fc$upper[, "95%"])), col = BAND_95, border = NA)
    polygon(c(dates, rev(dates)), c(fc$lower[, "80%"], rev(fc$upper[, "80%"])), col = BAND_80, border = NA)
    lines(d$date[past], d$price[past], col = HISTORY_COLOR, lwd = 2)
    lines(c(d$date[origin], dates), c(d$price[origin], fc$mean), col = "#2563eb", lwd = 2.5)
    abline(v = d$date[origin], col = "#64748b", lty = 2)
    if (length(actual_id)) lines(d$date[actual_id], d$price[actual_id], type = "o", pch = 16,
      col = "#b45309", lwd = 2)
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
    for (method in ALL_METHODS) lines(dates, fcs[[method]]$mean, col = COLORS[method], lwd = 2,
      type = "o", pch = 16, cex = .5)
    if (length(actual_id)) lines(d$date[actual_id], d$price[actual_id], col = HISTORY_COLOR,
      lwd = 2.5, type = "o", pch = 16)
    legend("topleft", c("Observed", ALL_METHODS), col = c(HISTORY_COLOR, COLORS[ALL_METHODS]),
      lty = 1, lwd = 2, bty = "n", ncol = 2, cex = .7)
  }
  figure("01_validation_all", function() draw_all(validation, train_n,
    paste("Three-month validation:", date_label(d$date[val_id])), val_id))
  figure("02_test_all", function() draw_all(test, dev_n,
    paste("Three-month test:", date_label(d$date[test_id])), test_id))
  figure("03_future_all", function() draw_all(final, n,
    paste("All nine models:", date_label(future))))
  figure("04_accuracy_comparison", function() {
    par(mfrow = c(1, 2), mar = c(10, 5, 4, 1))
    for (stage in c("Validation", "Test")) {
      z <- if (stage == "Validation") validation_scores else test_scores
      bars <- barplot(z$RMSE, names.arg = z$model, col = COLORS[z$model], las = 2,
        cex.names = .7, ylim = c(0, max(z$RMSE) * 1.2),
        ylab = "RMSE (U.S. dollars per dozen)", main = paste(stage, "three-month RMSE"))
      text(bars, z$RMSE, sprintf("%.3f", z$RMSE), pos = 3, cex = .7)
    }
  })
  for (method in ALL_METHODS) {
    figure(paste0("test_", slug(method)), function() draw_one(test[[method]], dev_n,
      paste(method, "test:", date_label(d$date[test_id])), test_id))
    figure(paste0("future_", slug(method)), function() draw_one(final[[method]], n,
      paste(method, "forecast:", date_label(future))))
  }

  # ---- Exploration and residual diagnostics for the active report ------------
  training <- fit_history(train_n)
  figure("00_history", function() {
    plot(d$date, d$price, type = "l", col = HISTORY_COLOR, lwd = 2,
      xlab = "Month", ylab = "U.S. dollars per dozen", main = "Original complete egg-price data through April 2025")
    abline(v = d$date[c(min(val_id), min(test_id))], col = c("#2563eb", "#0f766e"), lty = 2)
    legend("topleft", c("Observed", "Validation begins", "Test begins"),
      col = c(HISTORY_COLOR, "#2563eb", "#0f766e"), lty = c(1, 2, 2), bty = "n")
  })
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
    cat("THREE-MONTH FORECAST EXPERIMENT: ALL NINE MODELS\n\n")
    print(splits, row.names = FALSE)
    cat("\nVALIDATION ACCURACY\n"); print(validation_scores, row.names = FALSE)
    cat("\nSelected by validation RMSE:", selected, "\n")
    cat("\nTEST ACCURACY\n"); print(test_scores, row.names = FALSE)
    cat("\nTHREE-MONTH FUTURE FORECAST MEANS\n"); print(wide, row.names = FALSE)
    cat("\nDATA QUALITY\n"); print(data_quality, row.names = FALSE)
    cat("\nOnly three observations per evaluation window. Periods differ from earlier annual tests.\n")
    cat("Original complete snapshot only. No missing or imputed prices.\n")
  }, file = file.path(out, "results.txt"))
  cat("\nVALIDATION:\n"); print(validation_scores, row.names = FALSE)
  cat("\nSelected:", selected, "\nTEST:\n"); print(test_scores, row.names = FALSE)
  cat("\nFUTURE MEANS:\n"); print(wide, row.names = FALSE)
  cat("\nSaved to", out, "\n")
}

run_forecast()
