# Compare the original egg price series with its log: STL decomposition of each,
# plus a seasonal-strength number (Hyndman: 1 - Var(remainder) / Var(seasonal + remainder)).
# Run from the project root:  Rscript exploration/01_log_vs_original_stl/scripts/log_vs_original_stl.R

prices <- read.csv("data/APU0000708111.csv")
y <- ts(prices$APU0000708111, start = c(1980, 1), frequency = 12)

dec_orig <- stl(y, s.window = "periodic", robust = TRUE)
dec_log  <- stl(log(y), s.window = "periodic", robust = TRUE)

seasonal_strength <- function(d) {
  s <- d$time.series[, "seasonal"]; r <- d$time.series[, "remainder"]
  max(0, 1 - var(r) / var(s + r))
}
cat(sprintf("Seasonal strength, original: %.3f\n", seasonal_strength(dec_orig)))
cat(sprintf("Seasonal strength, log:      %.3f\n", seasonal_strength(dec_log)))

# Average seasonal effect by calendar month (original: USD, log: % relative to trend)
cat("\nSeasonal effect by month (original, USD):\n")
print(round(tapply(dec_orig$time.series[, "seasonal"], cycle(y), mean), 3))
cat("\nSeasonal effect by month (log, approx % of level):\n")
print(round(100 * (exp(tapply(dec_log$time.series[, "seasonal"], cycle(y), mean)) - 1), 2))

# Side-by-side plot: columns = original | log, rows = data, seasonal, trend, remainder
png("exploration/01_log_vs_original_stl/results/plots/log_vs_original_stl.png", width = 1600, height = 1300, res = 150)
par(mfrow = c(4, 2), mar = c(2, 4.5, 2, 1), oma = c(2, 0, 3, 0), las = 1)
comps <- list(
  data      = function(d, y0) y0,
  seasonal  = function(d, y0) d$time.series[, "seasonal"],
  trend     = function(d, y0) d$time.series[, "trend"],
  remainder = function(d, y0) d$time.series[, "remainder"]
)
for (nm in names(comps)) {
  for (v in c("orig", "log")) {
    d  <- if (v == "orig") dec_orig else dec_log
    y0 <- if (v == "orig") y else log(y)
    plot(comps[[nm]](d, y0), ylab = nm, xlab = "", col = if (v == "orig") "#2a78d6" else "#eb6834", lwd = 1.5,
         main = if (nm == "data") (if (v == "orig") "Original (USD per dozen)" else "Log(price)") else "")
    if (nm %in% c("seasonal", "remainder")) abline(h = 0, col = "grey60")
  }
}
mtext("STL decomposition: original vs log egg prices, 1980-2025", outer = TRUE, font = 2, cex = 1.1)
dev.off()
