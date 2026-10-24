# Egg prices: Damped Holt vs Seasonal ARIMA
# Train Jan 1980 - Dec 2013, test Jan - Dec 2014, no validation set.

library(forecast)

data_file <- "APU0000708111.csv"

#read data
eggs <- read.csv(data_file)
names(eggs) <- c("date", "price")
eggs$date <- as.Date(eggs$date)
stopifnot(nrow(eggs) == 544, !anyNA(eggs$price))

# split everything after 2014
usable <- eggs[eggs$date <= as.Date("2014-12-01"), ]
later <- eggs[eggs$date > as.Date("2014-12-01"), ]

series <- ts(usable$price, start = c(1980, 1), frequency = 12)
train <- window(series, end = c(2013, 12))
test <- window(series, start = c(2014, 1))
stopifnot(length(train) == 408, length(test) == 12)

train_dates <- usable$date[1:408]
test_dates <- usable$date[409:420]

#just a plot
plot(eggs$date, eggs$price,
  type = "l", lwd = 2, col = "navy", xlab = "Month",
  ylab = "U.S. dollars per dozen", main = "Egg price, Jan 1980-Apr 2025"
)
abline(v = as.Date(c("2014-01-01", "2015-01-01")), lty = 2, lwd = 2, col = c("darkgreen", "red"))
legend("topleft", c("Observed price", "Jan 2014", "Jan 2015"),
  col = c("navy", "darkgreen", "red"), lty = c(1, 2, 2), lwd = 2, bty = "n"
)

# lag in months
price_change <- diff(as.numeric(train))
op <- par(mfrow = c(2, 2))
acf(as.numeric(train), lag.max = 48, main = "ACF of price", xlab = "Lag in months")
pacf(as.numeric(train), lag.max = 48, main = "PACF of price", xlab = "Lag in months")
acf(price_change, lag.max = 48, main = "ACF of price change", xlab = "Lag in months")
pacf(price_change, lag.max = 48, main = "PACF of price change", xlab = "Lag in months")
par(op)

#fit models
dh <- ets(train, model = "AAN", damped = TRUE)
sa <- auto.arima(train,
  seasonal = TRUE, ic = "aicc", stepwise = TRUE,
  approximation = FALSE, method = "ML"
)
print(dh)
print(sa)

# residual check
residual_check <- function(fit, name, fitdf) {
  r <- as.numeric(residuals(fit))
  op <- par(mfrow = c(2, 2), oma = c(0, 0, 2, 0))
  plot(train_dates, r, type = "l", xlab = "Month", ylab = "Residual ($/dozen)", main = "Residuals over time")
  abline(h = 0, lty = 2)
  hist(r, breaks = "FD", freq = FALSE, xlab = "Residual ($/dozen)", main = "Residual histogram")
  curve(dnorm(x, mean(r), sd(r)), add = TRUE, col = "red", lwd = 2)
  acf(r, lag.max = 36, main = "Residual ACF", xlab = "Lag in months")
  qqnorm(r, main = "Normal Q-Q plot")
  qqline(r, col = "red", lwd = 2)
  mtext(name, outer = TRUE, font = 2)
  par(op)
  data.frame(
    model = name, sd = sd(r), acf_lag12 = acf(r, lag.max = 36, plot = FALSE)$acf[13],
    ljung_box_p_lag12 = Box.test(r, lag = 12, type = "Ljung-Box", fitdf = fitdf)$p.value,
    ljung_box_p_lag24 = Box.test(r, lag = 24, type = "Ljung-Box", fitdf = fitdf)$p.value
  )
}
diagnostics <- rbind(
  residual_check(dh, "Damped Holt", 3),
  residual_check(sa, "Seasonal ARIMA", sum(sa$arma[1:4]))
)
print(diagnostics, digits = 3)

# forecast 2014 and score
dh_fc <- forecast(dh, h = 12, level = c(80, 95))
sa_fc <- forecast(sa, h = 12, level = c(80, 95))

scores <- function(actual, predicted, scale) {
  e <- as.numeric(actual) - as.numeric(predicted)
  c(
    ME = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
    MAPE = 100 * mean(abs(e / as.numeric(actual))), MASE = mean(abs(e)) / scale
  )
}
# MASE
mase_scale <- mean(abs(diff(train, lag = 12)))
test_scores <- rbind(
  "Damped Holt" = scores(test, dh_fc$mean, mase_scale),
  "Seasonal ARIMA" = scores(test, sa_fc$mean, mase_scale)
)
print(round(test_scores, 4))

# 12 test months
coverage <- function(actual, fc, level) {
  mean(actual >= fc$lower[, level] & actual <= fc$upper[, level])
}
cat("Damped Holt coverage 80/95:", coverage(test, dh_fc, "80%"), coverage(test, dh_fc, "95%"), "\n")
cat("Seasonal ARIMA coverage 80/95:", coverage(test, sa_fc, "80%"), coverage(test, sa_fc, "95%"), "\n")

# forecast
fan_plot <- function(fc, past_dates, past_prices, fc_dates, main, color, actual = NULL) {
  h <- length(fc_dates)
  x <- c(past_dates[length(past_dates)], fc_dates)
  last <- past_prices[length(past_prices)]
  lo95 <- c(last, fc$lower[1:h, "95%"])
  hi95 <- c(last, fc$upper[1:h, "95%"])
  lo80 <- c(last, fc$lower[1:h, "80%"])
  hi80 <- c(last, fc$upper[1:h, "80%"])
  plot(range(past_dates, fc_dates), range(past_prices, lo95, hi95, actual),
    type = "n",
    xlab = "Month", ylab = "U.S. dollars per dozen", main = main
  )
  polygon(c(x, rev(x)), c(lo95, rev(hi95)), col = "lightblue1", border = NA)
  polygon(c(x, rev(x)), c(lo80, rev(hi80)), col = "lightskyblue", border = NA)
  lines(past_dates, past_prices, lwd = 2, col = "navy")
  lines(x, c(last, fc$mean[1:h]), lwd = 2, col = color)
  abline(v = x[1], lty = 2, col = "gray50")
  labels <- c("Observed", "Forecast", "80% interval", "95% interval")
  cols <- c("navy", color, "lightskyblue", "lightblue1")
  if (!is.null(actual)) {
    lines(fc_dates[seq_along(actual)], actual, lwd = 2, col = "orangered")
    if (length(actual) <= 24) points(fc_dates[seq_along(actual)], actual, pch = 16, col = "orangered")
    labels <- c(labels, "Actual")
    cols <- c(cols, "orangered")
  }
  legend("topleft", labels, col = cols, lwd = c(2, 2, 8, 8, 2)[seq_along(labels)], bty = "n")
}

recent <- usable$date >= as.Date("2011-01-01") & usable$date <= as.Date("2013-12-01")
fan_plot(dh_fc, usable$date[recent], usable$price[recent], test_dates,
  "Damped Holt test forecast, 2014", "darkcyan", test
)
fan_plot(sa_fc, usable$date[recent], usable$price[recent], test_dates,
  "Seasonal ARIMA test forecast, 2014", "purple", test
)

#the 2 forecasts and their error monthly
op <- par(mfrow = c(2, 1))
past <- usable$date >= as.Date("2013-01-01") & usable$date <= as.Date("2014-12-01")
plot(usable$date[past], usable$price[past],
  type = "l", lwd = 2, col = "navy", ylim = range(usable$price[past], dh_fc$mean, sa_fc$mean),
  xlab = "Month", ylab = "U.S. dollars per dozen", main = "Forecasts and actual prices, 2014"
)
lines(test_dates, dh_fc$mean, lwd = 2, lty = 2, col = "darkcyan")
lines(test_dates, sa_fc$mean, lwd = 2, col = "purple")
legend("topleft", c("Observed", "Damped Holt forecast", "Seasonal ARIMA forecast"),
  col = c("navy", "darkcyan", "purple"), lty = c(1, 2, 1), lwd = 2, bty = "n"
)
errors <- cbind(as.numeric(test - dh_fc$mean), as.numeric(test - sa_fc$mean))
matplot(test_dates, errors,
  type = "b", pch = c(17, 16), lty = c(2, 1), col = c("darkcyan", "purple"),
  xlab = "Month", ylab = "Actual minus forecast ($)", main = "Forecast error, 2014"
)
abline(h = 0)
legend("topleft", c("Damped Holt", "Seasonal ARIMA"),
  col = c("darkcyan", "purple"), lty = c(2, 1), pch = c(17, 16), bty = "n"
)
par(op)

# error measures of the two methods
op <- par(mfrow = c(1, 3))
for (cols in list(c("ME", "MAE", "RMSE"), "MAPE", "MASE")) {
  barplot(test_scores[, cols, drop = FALSE],
    beside = TRUE, col = c("darkcyan", "purple"),
    main = paste(cols, collapse = ", ")
  )
}
legend("topright", rownames(test_scores), fill = c("darkcyan", "purple"), bty = "n")
par(op)

# pick better model to retrain
best <- rownames(test_scores)[which.min(test_scores[, "RMSE"])]
cat("Better model on the 2014 test:", best, "\n")

# ARIMA on longer data
ord <- arimaorder(sa)
final_fit <- if (best == "Seasonal ARIMA") {
  Arima(series, order = ord[1:3], seasonal = list(order = ord[4:6], period = 12), method = "ML")
} else {
  ets(series, model = "AAN", damped = TRUE)
}
print(final_fit)

# 2015 to 2016 forecast
fc <- forecast(final_fit, h = 144, level = c(80, 95))
fc_dates <- seq(as.Date("2015-01-01"), by = "month", length.out = 144)
fc_table <- data.frame(
  date = fc_dates, mean = as.numeric(fc$mean),
  lower80 = fc$lower[, "80%"], upper80 = fc$upper[, "80%"],
  lower95 = fc$lower[, "95%"], upper95 = fc$upper[, "95%"]
)
print(head(fc_table, 12), digits = 4, row.names = FALSE)

fan_plot(fc, usable$date[usable$date >= as.Date("2011-01-01")],
  usable$price[usable$date >= as.Date("2011-01-01")], fc_dates[1:12],
  paste(best, "forecast, Jan-Dec 2015"), "purple"
)

# check/compare results
n_later <- nrow(later)
gap <- function(k) {
  actual <- later$price[1:k]
  e <- actual - fc_table$mean[1:k]
  c(
    months = k, ME = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
    MAPE = 100 * mean(abs(e / actual)),
    cover80 = mean(actual >= fc_table$lower80[1:k] & actual <= fc_table$upper80[1:k]),
    cover95 = mean(actual >= fc_table$lower95[1:k] & actual <= fc_table$upper95[1:k])
  )
}
gap_summary <- rbind("6 months" = gap(6), "12 months" = gap(12), "124 months" = gap(n_later))
print(round(gap_summary, 3))

# check with actual prices
fan_plot(fc, usable$date[usable$date >= as.Date("2000-01-01")],
  usable$price[usable$date >= as.Date("2000-01-01")], fc_dates,
  paste(best, "forecast, Jan 2015-Dec 2026"), "purple", later$price
)

# yearly avg miss
miss <- later$price - fc_table$mean[1:n_later]
year <- format(later$date, "%Y")
by_year <- tapply(miss, year, mean)
labels <- ifelse(as.numeric(table(year)) < 12, paste0(names(by_year), "*"), names(by_year))
barplot(by_year,
  names.arg = labels, col = ifelse(by_year >= 0, "orangered", "steelblue"),
  xlab = "Calendar year", ylab = "Mean actual minus forecast ($/dozen)",
  main = "Actual minus forecast by year"
)
abline(h = 0)
