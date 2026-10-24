# Quick alternative design: no validation window, one 12-month test (Jan-Dec 2014).
# Models are fitted on Jan 1980-Dec 2013 only; nothing after Dec 2014 is touched.
# Run from revised-2014/:  Rscript analysis/one_year_test.R
source(file.path("analysis", "helpers.R"))
d <- read.csv(file.path("data", "APU0000708111.csv"))
price <- d$APU0000708111; date <- as.Date(d$observation_date)
train_n <- 408L; h <- 12L
y <- ts(price[seq_len(train_n)], start = c(1980, 1), frequency = 12)
actual <- price[train_n + seq_len(h)]
stopifnot(all(date[train_n + seq_len(h)] == seq(as.Date("2014-01-01"), by = "month", length.out = h)))
scale <- mean(abs(price[13:train_n] - price[seq_len(train_n - 12L)]))
methods <- c("SES", "Holt", "Damped Holt", "Holt-Winters", "Auto ETS", "Naive", "Seasonal naive",
             "ARIMA", "Seasonal ARIMA search")
rows <- lapply(methods, function(m) {
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
})
tab <- do.call(rbind, rows)
dir.create(file.path("results", "one_year_test"), showWarnings = FALSE)
write.csv(tab[order(tab$RMSE), ], file.path("results", "one_year_test", "r_models_one_year_test.csv"),
  row.names = FALSE)
print(tab[order(tab$RMSE), ], row.names = FALSE, digits = 4)
