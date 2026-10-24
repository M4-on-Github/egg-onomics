# Alternative design: 12-month validation (Jan-Dec 2013) and 12-month test (Jan-Dec 2014).
# Validation: fit Jan 1980-Dec 2012, forecast 2013. Test: refit Jan 1980-Dec 2013, forecast 2014.
# Nothing after Dec 2014 is used. Run from revised-2014/:  Rscript analysis/val_test_12m.R
source(file.path("analysis", "helpers.R"))
d <- read.csv(file.path("data", "APU0000708111.csv"))
price <- d$APU0000708111; date <- as.Date(d$observation_date)
h <- 12L
methods <- c("SES", "Holt", "Damped Holt", "Holt-Winters", "Auto ETS", "Naive", "Seasonal naive",
             "ARIMA", "Seasonal ARIMA search")
score_stage <- function(origin_n, start_date) {
  y <- ts(price[seq_len(origin_n)], start = c(1980, 1), frequency = 12)
  actual <- price[origin_n + seq_len(h)]
  stopifnot(all(date[origin_n + seq_len(h)] == seq(as.Date(start_date), by = "month", length.out = h)))
  scale <- mean(abs(price[13:origin_n] - price[seq_len(origin_n - 12L)]))
  tab <- do.call(rbind, lapply(methods, function(m) {
    fit <- if (m %in% c("ARIMA", "Seasonal ARIMA search")) {
      forecast::auto.arima(y, seasonal = m == "Seasonal ARIMA search", ic = "aicc",
        stepwise = TRUE, approximation = FALSE, method = "ML", trace = FALSE)
    } else fit_one(y, m, h)
    fc <- predict_one(fit, h = h); e <- actual - as.numeric(fc$mean)
    data.frame(model = m, ME = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
      MAPE = 100 * mean(abs(e / actual)), MASE = mean(abs(e)) / scale,
      Coverage80 = mean(actual >= fc$lower[, "80%"] & actual <= fc$upper[, "80%"]),
      Coverage95 = mean(actual >= fc$lower[, "95%"] & actual <= fc$upper[, "95%"]),
      row.names = NULL)
  }))
  tab[order(tab$RMSE), ]
}
out <- file.path("results", "val_test_12m"); dir.create(out, showWarnings = FALSE)
val <- score_stage(396L, "2013-01-01"); test <- score_stage(408L, "2014-01-01")
write.csv(val, file.path(out, "r_validation_12m.csv"), row.names = FALSE)
write.csv(test, file.path(out, "r_test_12m.csv"), row.names = FALSE)
cat("VALIDATION 2013\n"); print(val[, 1:5], row.names = FALSE, digits = 4)
cat("TEST 2014\n"); print(test[, 1:5], row.names = FALSE, digits = 4)
