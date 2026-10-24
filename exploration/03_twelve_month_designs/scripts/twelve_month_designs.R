# Two 12-month designs for the nine models. The team pipeline in analysis/ is untouched.
#
#   A) "val_only": train | 12-month validation | 12-month forecast  (no test set)
#   B) "val_test": train | 12-month validation | 12-month test | 12-month forecast
#
# In both, validation RMSE picks the method, then every model is refit on all data and forecasts
# May 2025 - Apr 2026. In B the picked model is also scored on the test year.
# Reuses the model specs from analysis/helpers.R (ETS and ARIMA on logs, biasadj = TRUE).
#
# Run from the project root:  Rscript exploration/03_twelve_month_designs/scripts/twelve_month_designs.R
OUT_DIR <- file.path(getwd(), "exploration", "03_twelve_month_designs", "results", "csv")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(EGG_FORECAST_OUTPUT = OUT_DIR)
source(file.path("analysis", "helpers.R"), local = TRUE)  # fit_one, predict_one, prediction_rows, figure
H <- 12L  # after sourcing: helpers.R sets its own H <- 3L

ARIMA_METHODS <- c("ARIMA", "Seasonal ARIMA search")
ALL_METHODS <- c(METHODS, ARIMA_METHODS)
COLORS <- c(COLORS, "ARIMA" = "#0891b2", "Seasonal ARIMA search" = "#65a30d")

raw <- read.csv(INPUT)
d <- data.frame(date = as.Date(raw$observation_date), price = raw$APU0000708111)
n <- nrow(d)
series <- ts(d$price, start = c(1980, 1), frequency = 12)
fit_history <- function(end) ts(as.numeric(series)[seq_len(end)], start = c(1980, 1), frequency = 12)

fit_any <- function(y, method) {
  if (method %in% ARIMA_METHODS) {
    forecast::auto.arima(y, seasonal = method == "Seasonal ARIMA search", ic = "aicc", stepwise = TRUE,
      approximation = FALSE, method = "ML", lambda = 0, biasadj = TRUE)
  } else fit_one(y, method, H)
}
forecast_all <- function(end) {
  y <- fit_history(end)
  setNames(lapply(ALL_METHODS, function(m) predict_one(fit_any(y, m), h = H)), ALL_METHODS)
}
seasonal_scale <- function(end) {  # MASE scale: in-sample seasonal-naive MAE
  y <- as.numeric(series)[seq_len(end)]
  mean(abs(y[13:length(y)] - y[seq_len(length(y) - 12L)]))
}
score <- function(fcs, ids, fitting_end) {
  actual <- d$price[ids]
  tab <- do.call(rbind, lapply(names(fcs), function(m) {
    fc <- fcs[[m]]
    e <- actual - as.numeric(fc$mean)
    data.frame(model = m, ME = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
      MAPE = 100 * mean(abs(e / actual)), MASE = mean(abs(e)) / seasonal_scale(fitting_end),
      Coverage80 = mean(actual >= fc$lower[, "80%"] & actual <= fc$upper[, "80%"]),
      Coverage95 = mean(actual >= fc$lower[, "95%"] & actual <= fc$upper[, "95%"]))
  }))
  tab[order(tab$RMSE), ]
}
future_rows <- function(fcs) {
  dates <- seq(max(d$date), by = "month", length.out = H + 1L)[-1L]
  do.call(rbind, lapply(names(fcs), function(m) data.frame(model = m, date = dates, horizon = seq_len(H),
    mean = as.numeric(fcs[[m]]$mean), lower80 = as.numeric(fcs[[m]]$lower[, "80%"]),
    upper80 = as.numeric(fcs[[m]]$upper[, "80%"]), lower95 = as.numeric(fcs[[m]]$lower[, "95%"]),
    upper95 = as.numeric(fcs[[m]]$upper[, "95%"]))))
}

final <- forecast_all(n)                       # same for both designs
future <- future_rows(final)

run_design <- function(name, train_n, val_ids, test_ids = NULL) {
  cat("\n=====", name, "=====\n")
  dir <- file.path(OUT_DIR, name); dir.create(dir, showWarnings = FALSE)
  cat("train:", format(d$date[1]), "to", format(d$date[train_n]), "| validation:",
      format(d$date[min(val_ids)]), "to", format(d$date[max(val_ids)]), "\n")
  val_fc <- forecast_all(train_n)
  val <- score(val_fc, val_ids, train_n)
  cat("\nVALIDATION (sorted by RMSE)\n"); print(val, row.names = FALSE, digits = 3)
  write.csv(val, file.path(dir, "validation_accuracy.csv"), row.names = FALSE)
  cat("Picked by validation RMSE:", val$model[1], "\n")
  preds <- prediction_rows(val_fc, val_ids, "Validation", d)
  if (!is.null(test_ids)) {
    dev_n <- max(val_ids)
    test_fc <- forecast_all(dev_n)
    test <- score(test_fc, test_ids, dev_n)
    cat("\nTEST (sorted by RMSE; picked model =", val$model[1], ")\n"); print(test, row.names = FALSE, digits = 3)
    write.csv(test, file.path(dir, "test_accuracy.csv"), row.names = FALSE)
    preds <- rbind(preds, prediction_rows(test_fc, test_ids, "Test", d))
  }
  write.csv(preds, file.path(dir, "evaluation_predictions.csv"), row.names = FALSE)
  write.csv(future, file.path(dir, "forecast_12_months_all_models.csv"), row.names = FALSE)
}

run_design("A_val_only", train_n = n - 12L, val_ids = (n - 11L):n)
run_design("B_val_test", train_n = n - 24L, val_ids = (n - 23L):(n - 12L), test_ids = (n - 11L):n)

cat("\nFINAL 12-MONTH FORECAST MEANS (refit on all data)\n")
print(reshape(future[, c("model", "date", "mean")], idvar = "model", timevar = "date", direction = "wide"),
      row.names = FALSE, digits = 3)
cat("\nSaved to", OUT_DIR, "\n")
