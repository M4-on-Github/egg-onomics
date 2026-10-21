# Egg-onomics: reproducible monthly forecasting investigation.
# Run from any directory: Rscript path/to/egg-onomics/analysis/forecast.R
# Required package: forecast. No downloads or data updates occur in this script.
args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", args, value = TRUE)
root <- if (length(script_arg)) {
  dirname(dirname(normalizePath(sub("^--file=", "", script_arg[1]))))
} else {
  # When sourcing in RStudio, open egg-onomics.Rproj first.
  normalizePath(getwd())
}
if (!requireNamespace("forecast", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
  stop('Install dependencies first: install.packages(c("forecast", "jsonlite"))')
}
suppressPackageStartupMessages(library(forecast))
out <- file.path(root, "results")
fig <- file.path(out, "figures")
dir.create(fig, recursive = TRUE, showWarnings = FALSE)
input <- file.path(root, "APU0000708111.csv")
d <- read.csv(input, stringsAsFactors = FALSE, na.strings = c("", ".", "NA"))
stopifnot(identical(names(d), c("observation_date", "APU0000708111")))
d$date <- as.Date(d$observation_date, format = "%Y-%m-%d")
d$price <- as.numeric(d$APU0000708111)
stopifnot(!anyNA(d$date), !anyNA(d$price), all(is.finite(d$price)),
          all(d$price > 0), !anyDuplicated(d$date), !is.unsorted(d$date),
          identical(d$date, seq(min(d$date), max(d$date), by = "month")),
          all(format(d$date, "%d") == "01"), nrow(d) >= 60)
n <- nrow(d)
test_h <- 12L
validation_h <- 12L
horizon <- 10L
train_n <- n - validation_h - test_h
development_n <- n - test_h
train_id <- seq_len(train_n)
validation_id <- seq.int(train_n + 1L, development_n)
test_id <- seq.int(development_n + 1L, n)
series <- ts(d$price, start = c(as.integer(format(d$date[1], "%Y")),
                              as.integer(format(d$date[1], "%m"))), frequency = 12)
train <- window(series, end = time(series)[train_n])
development <- window(series, end = time(series)[development_n])
splits <- data.frame(split = c("Training", "Validation", "Test"),
                     start = d$date[c(1, train_n + 1, development_n + 1)],
                     end = d$date[c(train_n, development_n, n)],
                     observations = c(train_n, validation_h, test_h))
write.csv(splits, file.path(out, "data_splits.csv"), row.names = FALSE)
write.csv(data.frame(observations = n, missing_prices = sum(is.na(d$price)),
                     duplicate_dates = sum(duplicated(d$date)), missing_months = 0,
                     minimum = min(d$price), maximum = max(d$price),
                     first_date = min(d$date), last_date = max(d$date),
                     source_md5 = unname(tools::md5sum(input))),
          file.path(out, "data_quality.csv"), row.names = FALSE)

# All five smoothing models use additive errors on log prices (lambda = 0).
# Log modeling respects price positivity. biasadj converts forecast medians to
# approximate dollar-scale means. All accuracy scores use original dollar prices.
# ETS automatic structure selection uses only the data supplied to that fit.
methods <- c("SES", "Holt", "Damped Holt", "Holt-Winters", "Auto ETS",
             "Naive", "Seasonal naive")
fit_method <- function(y, method, h) {
  if (method == "Naive") return(naive(y, h = h, level = c(80, 95)))
  if (method == "Seasonal naive") return(snaive(y, h = h, level = c(80, 95)))
  fit <- switch(method,
    "SES" = ets(y, model = "ANN", damped = FALSE, lambda = 0, biasadj = TRUE),
    "Holt" = ets(y, model = "AAN", damped = FALSE, lambda = 0, biasadj = TRUE),
    "Damped Holt" = ets(y, model = "AAN", damped = TRUE, lambda = 0, biasadj = TRUE),
    "Holt-Winters" = ets(y, model = "AAA", damped = FALSE, lambda = 0, biasadj = TRUE),
    "Auto ETS" = ets(y, model = "ZZZ", additive.only = TRUE,
                     lambda = 0, biasadj = TRUE))
  forecast(fit, h = h, level = c(80, 95), biasadj = TRUE)
}
fit_all <- function(y, h) setNames(lapply(methods, function(m) fit_method(y, m, h)), methods)
score <- function(f, actual, history) {
  e <- actual - as.numeric(f$mean)
  scale <- mean(abs(diff(as.numeric(history), lag = 12)))
  c(ME = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
    MAPE = 100 * mean(abs(e / actual)), MASE = mean(abs(e)) / scale,
    Coverage80 = mean(actual >= f$lower[, "80%"] & actual <= f$upper[, "80%"]),
    Coverage95 = mean(actual >= f$lower[, "95%"] & actual <= f$upper[, "95%"]))
}
score_all <- function(fits, actual, history) {
  tab <- data.frame(model = names(fits),
                    do.call(rbind, lapply(fits, score, actual = actual, history = history)),
                    row.names = NULL)
  tab[order(tab$RMSE), ]
}
validation_fits <- fit_all(train, validation_h)
validation_scores <- score_all(validation_fits, d$price[validation_id], train)
# Lock the choice BEFORE fitting/evaluating the final test year.
# Smoothing methods are eligible; naive methods are transparent benchmarks.
eligible <- validation_scores[!validation_scores$model %in% c("Naive", "Seasonal naive"), ]
selected <- eligible$model[1]
test_fits <- fit_all(development, test_h)
test_scores <- score_all(test_fits, d$price[test_id], development)
write.csv(validation_scores, file.path(out, "validation_accuracy.csv"), row.names = FALSE)
write.csv(test_scores, file.path(out, "test_accuracy.csv"), row.names = FALSE)
prediction_rows <- function(fits, ids, split) do.call(rbind, lapply(names(fits), function(m) {
  f <- fits[[m]]
  data.frame(split = split, model = m, date = d$date[ids], actual = d$price[ids],
             forecast = as.numeric(f$mean), lower80 = as.numeric(f$lower[, "80%"]),
             upper80 = as.numeric(f$upper[, "80%"]), lower95 = as.numeric(f$lower[, "95%"]),
             upper95 = as.numeric(f$upper[, "95%"]), row.names = NULL)
}))
write.csv(rbind(prediction_rows(validation_fits, validation_id, "Validation"),
                prediction_rows(test_fits, test_id, "Test")),
          file.path(out, "evaluation_predictions.csv"), row.names = FALSE)

palette <- c("#176b63", "#a55a14", "#4265aa", "#b34d60", "#754ca3", "#61727c", "#a09a8c")
names(palette) <- methods
draw <- function(name, fun, width = 1500, height = 850) {
  png(file.path(fig, paste0(name, ".png")), width = width, height = height, res = 150)
  par(family = "sans", col = "#23352f", col.axis = "#485b54", col.lab = "#23352f",
      fg = "#23352f", bg = "#fbfcf9", mar = c(4.4, 4.4, 3.5, 1.5), las = 1)
  fun()
  invisible(dev.off())
}
draw("01_history", function() {
  plot(d$date, d$price, type = "l", col = "#176b63", lwd = 1.5,
       xlab = "Month", ylab = "U.S. dollars per dozen",
       main = "U.S. retail egg prices | monthly saved snapshot")
  abline(v = d$date[c(train_n + 1, development_n + 1)], lty = 3, col = "#a55a14")
  legend("topleft", c("Observed price", "Validation / test boundaries"),
         col = c("#176b63", "#a55a14"), lty = c(1, 3), bty = "n")
})
draw("02_correlograms", function() {
  par(mfrow = c(1, 2))
  acf(log(train), lag.max = 48, main = "Training log prices", xlab = "Lag (years)")
  acf(diff(log(train)), lag.max = 48, main = "Monthly log-price changes", xlab = "Lag (years)")
})
decomp <- stl(log(train), s.window = "periodic", robust = TRUE)
seasonal_strength <- max(0, 1 - var(decomp$time.series[, "remainder"]) /
                          var(decomp$time.series[, "seasonal"] + decomp$time.series[, "remainder"]))
draw("03_decomposition", function() {
  plot(decomp, main = "Training data | robust STL on log prices")
}, height = 1100)
plot_comparison <- function(fits, ids, title) {
  recent <- seq.int(max(1, min(ids) - 24), max(ids))
  limits <- range(d$price[recent], unlist(lapply(fits, function(f) as.numeric(f$mean))))
  plot(d$date[recent], d$price[recent], type = "l", col = "#182a24", lwd = 2,
       xlab = "Month", ylab = "U.S. dollars per dozen", main = title, ylim = limits)
  abline(v = d$date[min(ids)], lty = 3, col = "#88988e")
  for (m in methods) lines(d$date[ids], fits[[m]]$mean, col = palette[m], lwd = 1.6,
                           lty = if (m %in% c("Naive", "Seasonal naive")) 3 else 1)
  points(d$date[ids], d$price[ids], pch = 16, cex = 0.55)
  legend("topleft", c("Observed", methods), col = c("#182a24", palette),
         lty = c(1, rep(1, 5), 3, 3), lwd = 1.5, bty = "n", cex = 0.75, ncol = 2)
}
draw("04_validation", function() plot_comparison(validation_fits, validation_id,
     "Validation year | models selected using these errors"))
draw("05_test", function() plot_comparison(test_fits, test_id,
     "Final test year | selection was already locked"))

parameter_rows <- function(fits, stage) do.call(rbind, lapply(names(fits), function(m) {
  f <- fits[[m]]
  p <- if (inherits(f$model, "ets")) f$model$par else numeric(0)
  value <- function(k) if (k %in% names(p)) unname(p[k]) else NA_real_
  data.frame(stage = stage, model = m, fitted_structure = f$method,
             alpha = value("alpha"), beta = value("beta"),
             gamma = value("gamma"), phi = value("phi"),
             AICc = if (inherits(f$model, "ets")) f$model$aicc else NA_real_,
             row.names = NULL)
}))
diagnostics <- do.call(rbind, lapply(seq_along(methods), function(i) {
  m <- methods[i]
  f <- validation_fits[[m]]
  r <- as.numeric(residuals(f))
  finite <- is.finite(r)
  dates <- d$date[train_id]
  # ETS residuals are log-scale innovations, not dollar forecast errors.
  unit <- if (inherits(f$model, "ets")) "Log-price innovation" else "Dollar residual"
  r <- r[finite]
  dates <- dates[finite]
  draw(sprintf("%02d_residuals_%s", i + 5, gsub(" ", "_", tolower(m))), function() {
    par(mfrow = c(1, 3), mar = c(4.5, 4.3, 4.2, 1))
    plot(dates, r, type = "l", col = palette[m], main = paste(m, "| training residuals"),
         xlab = "Month", ylab = unit, cex.main = 0.85)
    abline(h = 0, lty = 3)
    hist(r, breaks = "FD", main = "Residual distribution", xlab = unit,
         col = "#bedbd1", border = "white")
    acf(r, lag.max = 36, main = "Residual ACF", xlab = "Lag (months)")
  }, width = 1800, height = 650)
  fitdf <- if (inherits(f$model, "ets")) sum(names(f$model$par) %in% c("alpha", "beta", "gamma", "phi")) else 0
  lb <- Box.test(r, lag = 24, type = "Ljung-Box", fitdf = fitdf)
  a <- as.numeric(acf(r, lag.max = 12, plot = FALSE)$acf)
  data.frame(model = m, residual_scale = unit, residual_mean = mean(r),
             residual_sd = sd(r), acf_lag1 = a[2], acf_lag12 = a[13],
             ljung_box_lag = 24, fitted_df_adjustment = fitdf,
             ljung_box_statistic = unname(lb$statistic), ljung_box_p = lb$p.value)
}))
write.csv(diagnostics, file.path(out, "residual_diagnostics.csv"), row.names = FALSE)

# Refit only the preselected smoothing specification to the full saved snapshot.
# Auto ETS may reselect its structure by AICc, without changing the selected rule.
final <- fit_method(series, selected, horizon)
future_dates <- seq(max(d$date), by = "month", length.out = horizon + 1)[-1]
forecast_table <- data.frame(date = future_dates, model = selected,
                            mean = as.numeric(final$mean),
                            lower80 = as.numeric(final$lower[, "80%"]), upper80 = as.numeric(final$upper[, "80%"]),
                            lower95 = as.numeric(final$lower[, "95%"]), upper95 = as.numeric(final$upper[, "95%"]),
                            row.names = NULL)
stopifnot(nrow(forecast_table) == 10, all(is.finite(as.matrix(forecast_table[, 3:7]))),
          all(forecast_table$lower95 <= forecast_table$lower80),
          all(forecast_table$lower80 <= forecast_table$upper80),
          all(forecast_table$upper80 <= forecast_table$upper95),
          all(forecast_table$lower95 > 0),
          all(forecast_table$mean >= forecast_table$lower95),
          all(forecast_table$mean <= forecast_table$upper95))
write.csv(forecast_table, file.path(out, "forecast_10_months.csv"), row.names = FALSE)
write.csv(rbind(parameter_rows(validation_fits, "Training"),
                parameter_rows(test_fits, "Training + validation"),
                parameter_rows(setNames(list(final), selected), "Full snapshot")),
          file.path(out, "model_parameters.csv"), row.names = FALSE)
draw("13_final_forecast", function() {
  recent <- seq.int(max(1, n - 59), n)
  x <- c(d$date[recent], future_dates)
  limits <- range(d$price[recent], final$lower, final$upper)
  plot(x, c(d$price[recent], rep(NA_real_, horizon)), type = "n", ylim = limits,
       xlab = "Month", ylab = "U.S. dollars per dozen",
       main = paste0("Historical 10-month forecast | ", selected))
  polygon(c(future_dates, rev(future_dates)), c(final$lower[, "95%"], rev(final$upper[, "95%"])),
          col = "#dce9e3", border = NA)
  polygon(c(future_dates, rev(future_dates)), c(final$lower[, "80%"], rev(final$upper[, "80%"])),
          col = "#a8cfc0", border = NA)
  lines(d$date[recent], d$price[recent], col = "#182a24", lwd = 2)
  lines(c(max(d$date), future_dates), c(tail(d$price, 1), final$mean), col = "#176b63", lwd = 2)
  abline(v = max(d$date), lty = 3, col = "#88988e")
  legend("topleft", c("Observed", "Forecast mean", "80% prediction interval", "95% prediction interval"),
         col = c("#182a24", "#176b63", "#a8cfc0", "#dce9e3"), lwd = c(2, 2, 8, 8), bty = "n", cex = 0.85)
})

capture.output(sessionInfo(), file = file.path(out, "session_info.txt"))
capture.output(list(selected_by_validation_RMSE = selected,
                    final_structure = final$method, final_parameters = final$model$par,
                    seasonal_strength_training_log_STL = seasonal_strength,
                    training_log_acf = as.numeric(acf(log(train), lag.max = 12, plot = FALSE)$acf)[c(2, 13)],
                    training_change_acf = as.numeric(acf(diff(log(train)), lag.max = 12, plot = FALSE)$acf)[c(2, 13)]),
               file = file.path(out, "analysis_summary.txt"))
saveRDS(list(splits = splits, validation = validation_fits, test = test_fits,
             selected = selected, final = final), file.path(out, "fitted_models.rds"))

# Evidence viewer: computed tables and figures, with prompts for the student's
# interpretation. This is an analysis output, not a completed written report.
esc <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
html_table <- function(x, digits = 3) {
  y <- x
  for (k in names(y)) if (is.numeric(y[[k]])) y[[k]] <- formatC(y[[k]], digits = digits, format = "f")
  paste0('<div class="table-wrap"><table><thead><tr>',
         paste0("<th>", esc(names(y)), "</th>", collapse = ""),
         "</tr></thead><tbody>",
         paste(apply(y, 1, function(row) paste0("<tr>", paste0("<td>", esc(row), "</td>", collapse = ""), "</tr>")), collapse = ""),
         "</tbody></table></div>")
}
image_tag <- function(name, alt) {
  # Inline the plots so the HTML remains usable when copied or emailed alone.
  path <- file.path(fig, paste0(name, ".png"))
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  paste0('<figure><img alt="', esc(alt), '" src="data:image/png;base64,',
         jsonlite::base64_enc(bytes), '"></figure>')
}
if (!requireNamespace("jsonlite", quietly = TRUE)) stop('Install jsonlite to build the viewer.')
best_test <- test_scores$model[1]
selected_test <- test_scores[test_scores$model == selected, ]
html <- c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
  '<title>Egg-onomics | Forecasting evidence</title><style>',
  ':root{color-scheme:light}*{box-sizing:border-box}body{margin:0;background:#f3f4ed;color:#23352f;font:16px/1.6 system-ui,sans-serif}main{max-width:1160px;margin:auto;padding:48px 24px}h1{font-size:clamp(38px,6vw,68px);line-height:1.05;letter-spacing:-2px;margin:8px 0 20px}h2{margin-top:45px;font-size:28px}h3{font-size:19px}.eyebrow{letter-spacing:3px;font-size:12px;text-transform:uppercase;color:#176b63;font-weight:700}.lede{max-width:800px;font-size:19px}.card{background:#fffdf7;border:1px solid #d9dfd3;border-radius:12px;padding:24px;margin:20px 0}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:15px}.stat{padding:20px;background:#e3ebe0;border-radius:10px}.stat strong{display:block;font-size:27px}.stat span{font-size:13px}.note{border-left:4px solid #a55a14;padding:12px 18px;background:#f9efdc}figure{margin:24px 0}img{display:block;width:100%;height:auto;border:1px solid #d9dfd3;border-radius:8px}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;font-size:13px}td,th{padding:10px;text-align:left;border-bottom:1px solid #e0e5db;white-space:nowrap}th{background:#e7eee2}a{color:#176b63}summary{cursor:pointer;font-weight:650;padding:12px 0}code{background:#e7eee2;padding:2px 5px}footer{margin-top:50px;font-size:13px;color:#617267}@media print{body{background:white}main{padding:0}figure,.card{break-inside:avoid}details{display:block}}</style></head><body><main>',
  '<div class="eyebrow">MTH305 / Forecasting evidence pack</div><h1>Egg-onomics.</h1>',
  '<p class="lede">A reproducible investigation of monthly U.S. egg prices. Computed evidence, model diagnostics and a historical forecast from the saved April 2025 endpoint.</p>',
  paste0('<div class="stats"><div class="stat"><strong>', n, '</strong><span>monthly observations / Jan 1980-Apr 2025</span></div><div class="stat"><strong>', selected, '</strong><span>chosen by validation RMSE among smoothing models</span></div><div class="stat"><strong>$', sprintf('%.3f', selected_test$RMSE), '</strong><span>selected model test RMSE / per dozen</span></div><div class="stat"><strong>10 months</strong><span>May 2025-Feb 2026 / historical horizon</span></div></div>'),
  '<p class="note">This is a frozen-snapshot historical experiment, not a current forecast. Model choice uses the validation year; the final test year is evaluated afterward. Use the evidence and prompts to write your own report and presentation.</p>',
  '<h2>1 / Data and exploration</h2><p>Source: U.S. Bureau of Labor Statistics, distributed by <a href="https://fred.stlouisfed.org/series/APU0000708111">FRED series APU0000708111</a>. U.S. dollars per dozen large Grade A eggs, U.S. city average, monthly and not seasonally adjusted. Dates identify months, not daily observations. Prices are nominal; this is a price-level forecast, not an inflation-index study. The original CSV is unchanged.</p>',
  html_table(splits), image_tag("01_history", "Full monthly price series and split boundaries"),
  image_tag("02_correlograms", "Training ACF of log prices and monthly log changes"),
  image_tag("03_decomposition", "Robust log-price STL decomposition using only training data"),
  paste0('<p>Computed training STL seasonal strength: <strong>', sprintf('%.3f', seasonal_strength), '</strong> (0 = weak, 1 = strong). The ACF panels use a monthly ts object, so 1 on their horizontal axes represents 12 months. STL assumes a recurring monthly pattern; its trend component does not establish a predictable multi-year cycle.</p>'),
  '<h2>2 / Model choice and validation</h2><div class="card"><p><strong>SES:</strong> evolving level. <strong>Holt:</strong> level plus unrestricted local trend. <strong>Damped Holt:</strong> local trend that fades with horizon. <strong>Holt-Winters:</strong> level, trend and recurring monthly seasonality. <strong>Auto ETS:</strong> chooses additive log-scale structure by training AICc. Naive and seasonal naive are benchmark forecasts.</p><p>All smoothing models fit log prices (lambda = 0); forecast means are bias-adjusted back to dollars. Naive benchmarks use original prices. Parameters are estimated by the forecast package. Compare every method on the same dollar-scale errors. Model choice is the lowest validation RMSE among the five smoothing methods; benchmarks remain visible, even when stronger.</p></div>',
  html_table(validation_scores), image_tag("04_validation", "Validation actual prices and model forecasts"),
  '<div class="card"><strong>Accuracy definitions</strong><p>Error = actual minus forecast. ME measures bias (positive means underprediction); MAE is average absolute dollar error; RMSE penalizes larger misses more; MAPE is average absolute percentage error; MASE divides MAE by the mean absolute seasonal-naive one-step error in the corresponding fitting period. MASE &lt; 1 beats that in-sample scale, not necessarily the held-out seasonal-naive forecast. Coverage80 / Coverage95 are observed interval coverage fractions across only 12 months, not guaranteed probabilities.</p></div>',
  '<h2>3 / Final test year</h2>', html_table(test_scores), image_tag("05_test", "Held-out test actual prices and model forecasts"),
  paste0('<p>Preselected smoothing method: <strong>', selected, '</strong>. Lowest observed test RMSE across all methods: <strong>', best_test, '</strong>. These can differ. Keep the selection rule fixed when interpreting the final test. If a benchmark wins, discuss that openly rather than claiming the smoothing method is universally best.</p>'),
  '<h2>4 / Training residual diagnostics</h2><p>Each model has a residual time plot, histogram and ACF. Smoothing-model residuals are log-price innovations; benchmark residuals are dollars. Do not compare residual SD across those scales. Ljung-Box tests use lag 24 and adjust degrees of freedom for estimated smoothing and damping parameters (not initial states); treat these approximate p-values as diagnostic evidence.</p>',
  html_table(diagnostics, digits = 5),
  unlist(lapply(seq_along(methods), function(i) paste0('<details><summary>', methods[i], '</summary>',
    image_tag(sprintf("%02d_residuals_%s", i + 5, gsub(" ", "_", tolower(methods[i]))), paste(methods[i], "residual diagnostics")), '</details>'))),
  '<h2>5 / Ten-month historical forecast</h2>', image_tag("13_final_forecast", "Historical ten-month forecast with 80 and 95 percent prediction intervals"),
  html_table(forecast_table),
  '<p class="note">The shaded bands are model-based prediction intervals for future monthly prices, not confidence intervals for a mean. They assume the fitted dynamics and error distribution continue. Sudden supply shocks, changing volatility and non-normal or autocorrelated residuals can make actual coverage worse. Positivity is ensured by log modeling; no intervals are clipped.</p>',
  '<h2>6 / Parameters and interpretation prompts</h2>',
  html_table(parameter_rows(validation_fits, "Training"), digits = 5),
  html_table(parameter_rows(setNames(list(final), selected), "Full snapshot"), digits = 5),
  '<div class="card"><p>Alpha controls the level update; beta controls the trend update; gamma controls the seasonal update; phi damps trend persistence. NA means the parameter is absent. Near-boundary estimates deserve discussion. The same model structure may have different parameters when refit to more data.</p><ol><li>What do the history, ACF and STL plots say about trend, seasonality and shocks?</li><li>Do residuals resemble white noise? Which visible features or ACF lags support your answer?</li><li>Do RMSE, MAE and MAPE agree on the strongest models? What does disagreement imply?</li><li>How did the locked choice perform on the test year and against naive benchmarks?</li><li>What does the forecast imply for budgeting, and what would make its intervals unreliable?</li><li>What extra data might improve forecasts: flock sizes, feed costs, disease outbreaks, supply volumes or inflation?</li></ol></div>',
  '<footer>Generated by analysis/forecast.R from the repository CSV. Tables retain full precision in results/*.csv. Model objects and session details are saved for reproducibility. No future prices or external regressors were used.</footer></main></body></html>')
writeLines(html, file.path(out, "index.html"), useBytes = TRUE)
cat("\nSelected smoothing method:", selected, "\n\nValidation accuracy:\n")
print(validation_scores, row.names = FALSE)
cat("\nTest accuracy:\n")
print(test_scores, row.names = FALSE)
cat("\nForecast:\n")
print(forecast_table, row.names = FALSE)
cat("\nEvidence viewer:", file.path(out, "index.html"), "\n")
