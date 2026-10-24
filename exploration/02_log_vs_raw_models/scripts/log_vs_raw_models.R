# Same nine models as analysis/forecast.R, trained on the RAW dollar series vs the LOG series.
# Naive and Seasonal naive are always fit on dollars (as in the team pipeline), so they are the
# fixed reference in both columns. Everything is scored in dollars.
#
#   A) the team's own validation and test windows (3 months each; very few points)
#   B) rolling origins every 3 months from 2015-01 (3-month forecasts, refit at every origin)
#
# Run from the project root:  Rscript exploration/02_log_vs_raw_models/scripts/log_vs_raw_models.R
suppressPackageStartupMessages(library(forecast))

H <- 3L
LEVELS <- c(80, 95)
FIRST_ROLLING_ORIGIN <- "2015-01-01"
ROLLING_STEP <- 3L
N_WORKERS <- 8L
METHODS <- c("SES", "Holt", "Damped Holt", "Holt-Winters", "Auto ETS",
             "Naive", "Seasonal naive", "ARIMA", "Seasonal ARIMA search")
BASELINES <- c("Naive", "Seasonal naive")
TRANSFORMS <- c(raw = NA, log = 0)  # lambda: NA = no transform, 0 = log

raw <- read.csv("data/APU0000708111.csv")
dates <- as.Date(raw$observation_date)
price <- raw$APU0000708111
n <- length(price)

# Same specifications as analysis/helpers.R and forecast.R, with lambda made a parameter.
fit_forecast <- function(y, method, lambda) {
  lam <- if (is.na(lambda)) NULL else lambda
  if (method == "Naive") return(forecast::naive(y, h = 3L, level = c(80, 95)))
  if (method == "Seasonal naive") return(forecast::snaive(y, h = 3L, level = c(80, 95)))
  fit <- switch(method,
    "SES" = forecast::ets(y, model = "ANN", damped = FALSE, lambda = lam, biasadj = TRUE),
    "Holt" = forecast::ets(y, model = "AAN", damped = FALSE, lambda = lam, biasadj = TRUE),
    "Damped Holt" = forecast::ets(y, model = "AAN", damped = TRUE, lambda = lam, biasadj = TRUE),
    "Holt-Winters" = forecast::ets(y, model = "AAA", damped = FALSE, lambda = lam, biasadj = TRUE),
    "Auto ETS" = forecast::ets(y, model = "ZZZ", additive.only = TRUE, lambda = lam, biasadj = TRUE),
    "ARIMA" = forecast::auto.arima(y, seasonal = FALSE, ic = "aicc", stepwise = TRUE,
      approximation = FALSE, method = "ML", lambda = lam, biasadj = TRUE),
    "Seasonal ARIMA search" = forecast::auto.arima(y, seasonal = TRUE, ic = "aicc", stepwise = TRUE,
      approximation = FALSE, method = "ML", lambda = lam, biasadj = TRUE))
  forecast::forecast(fit, h = 3L, level = c(80, 95), biasadj = TRUE)
}

# One origin = fit on data up to index `end`, forecast the next 3 months, return a tidy table.
run_origin <- function(end) {
  y <- ts(price[seq_len(end)], start = c(1980, 1), frequency = 12)
  ids <- end + seq_len(3L)
  ids <- ids[ids <= length(price)]
  rows <- list()
  for (method in METHODS) for (tr in names(TRANSFORMS)) {
    if (method %in% c("Naive", "Seasonal naive") && tr == "log") next  # identical to raw
    fc <- tryCatch(fit_forecast(y, method, TRANSFORMS[[tr]]), error = function(e) NULL)
    if (is.null(fc)) next
    k <- seq_along(ids)
    for (tr_out in if (method %in% c("Naive", "Seasonal naive")) names(TRANSFORMS) else tr) {
      rows[[length(rows) + 1L]] <- data.frame(
        origin = dates[end], model = method, transform = tr_out, horizon = k, date = dates[ids],
        actual = price[ids], forecast = as.numeric(fc$mean)[k],
        lower80 = as.numeric(fc$lower[k, "80%"]), upper80 = as.numeric(fc$upper[k, "80%"]),
        lower95 = as.numeric(fc$lower[k, "95%"]), upper95 = as.numeric(fc$upper[k, "95%"]))
    }
  }
  do.call(rbind, rows)
}

score <- function(p) {
  by <- paste(p$model, p$transform)
  out <- do.call(rbind, lapply(split(p, by), function(z) {
    e <- z$actual - z$forecast
    data.frame(model = z$model[1], transform = z$transform[1], n = nrow(z), ME = mean(e),
      MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)), MAPE = 100 * mean(abs(e / z$actual)),
      Coverage80 = mean(z$actual >= z$lower80 & z$actual <= z$upper80),
      Coverage95 = mean(z$actual >= z$lower95 & z$actual <= z$upper95), row.names = NULL)
  }))
  out[order(match(out$model, METHODS), out$transform), ]
}

# ---- A) team windows: validation origin = n-6, test origin = n-3 ---------------------------
team_origins <- c(Validation = n - 6L, Test = n - 3L)
team <- do.call(rbind, lapply(names(team_origins), function(s) {
  cat("Team window:", s, "\n"); cbind(split = s, run_origin(team_origins[[s]]))
}))
team_scores <- do.call(rbind, lapply(split(team, team$split), function(z) cbind(split = z$split[1], score(z))))

# ---- B) rolling origins (parallel) ---------------------------------------------------------
first <- which(dates == as.Date(FIRST_ROLLING_ORIGIN))
origins <- seq(first, n - 1L, by = ROLLING_STEP)
cat("Rolling origins:", length(origins), "| workers:", N_WORKERS, "\n")
t0 <- Sys.time()
cl <- parallel::makeCluster(N_WORKERS)
parallel::clusterExport(cl, c("price", "dates", "METHODS", "TRANSFORMS", "fit_forecast", "run_origin"))
invisible(parallel::clusterEvalQ(cl, suppressPackageStartupMessages(library(forecast))))
rolling <- do.call(rbind, parallel::parLapplyLB(cl, origins, run_origin))
parallel::stopCluster(cl)
cat(sprintf("Rolling fits took %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

rolling_scores <- score(rolling)
shock_scores <- score(rolling[rolling$origin >= as.Date("2022-01-01"), ])  # origins from 2022 on

write.csv(team, "exploration/02_log_vs_raw_models/results/csv/log_vs_raw_team_predictions.csv", row.names = FALSE)
write.csv(rolling, "exploration/02_log_vs_raw_models/results/csv/log_vs_raw_rolling_predictions.csv", row.names = FALSE)
write.csv(rolling_scores, "exploration/02_log_vs_raw_models/results/csv/log_vs_raw_rolling_scores.csv", row.names = FALSE)
write.csv(team_scores, "exploration/02_log_vs_raw_models/results/csv/log_vs_raw_team_scores.csv", row.names = FALSE)

fmt <- function(s) print(transform(s, ME = round(ME, 3), MAE = round(MAE, 3), RMSE = round(RMSE, 3),
  MAPE = round(MAPE, 2), Coverage80 = round(Coverage80, 2), Coverage95 = round(Coverage95, 2)), row.names = FALSE)
cat("\n=== A) Team windows (3 observations each) ===\n"); fmt(team_scores)
cat("\n=== B) Rolling origins, all (", length(origins), " origins) ===\n", sep = ""); fmt(rolling_scores)
cat("\n=== B) Rolling origins from 2022 on ===\n"); fmt(shock_scores)

# ---- Plot: RMSE and 80% coverage, raw vs log, rolling evaluation ---------------------------
png("exploration/02_log_vs_raw_models/results/plots/log_vs_raw_models.png", width = 1700, height = 900, res = 150)
par(mfrow = c(1, 2), mar = c(11, 4.5, 3, 1), las = 2)
cols <- c(raw = "#2a78d6", log = "#eb6834")
w <- reshape(rolling_scores[, c("model", "transform", "RMSE", "Coverage80")], idvar = "model",
  timevar = "transform", direction = "wide")
w <- w[match(METHODS, w$model), ]
w[is.na(w$RMSE.log), c("RMSE.log", "Coverage80.log")] <- w[is.na(w$RMSE.log), c("RMSE.raw", "Coverage80.raw")]
barplot(rbind(w$RMSE.raw, w$RMSE.log), beside = TRUE, names.arg = w$model, col = cols, ylab = "RMSE (USD per dozen)",
  main = "3-month RMSE, rolling origins 2015-2025")
legend("topleft", c("Trained on raw dollars", "Trained on log"), fill = cols, bty = "n")
barplot(rbind(w$Coverage80.raw, w$Coverage80.log), beside = TRUE, names.arg = w$model, col = cols, ylim = c(0, 1),
  ylab = "Share of actuals inside 80% interval", main = "80% interval coverage")
abline(h = 0.8, lty = 3)
dev.off()
