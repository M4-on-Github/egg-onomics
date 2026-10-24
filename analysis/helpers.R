# MTH305 STUDY: forecasting monthly U.S. retail egg prices.
# Training estimates models. Validation chooses the method. Test evaluates it.
# Shared modeling and plotting helpers for the complete April 2025 snapshot.
# Run with RStudio Source or Rscript; the working directory can be anywhere.

# ---- Packages and project paths ---------------------------------------------
required <- c("forecast", "jsonlite")
for (pkg in required) if (!requireNamespace(pkg, quietly = TRUE)) {
  stop("Run install.packages(c('forecast', 'jsonlite')) first.", call. = FALSE)
}

# Like forecast_movement.R, prefer the file being sourced over a caller's
# command-line path. RStudio may have analysis/ as its working directory.
locate_project <- function() {
  source_files <- unlist(lapply(sys.frames(), function(fr) {
    if (!is.null(fr$ofile)) as.character(fr$ofile) else character()
  }))
  cli <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  candidates <- c(rev(source_files), cli)
  candidates <- candidates[file.exists(candidates)]
  starts <- c(dirname(candidates), getwd())
  for (start in starts) {
    path <- normalizePath(start, winslash = "/")
    for (step in seq_len(3L)) {
      if (file.exists(file.path(path, "egg-onomics.Rproj")) &&
          file.exists(file.path(path, "analysis", "forecast.R"))) return(path)
      path <- dirname(path)
    }
  }
  stop("Use Source on the saved forecast.R script, or run it with Rscript.", call. = FALSE)
}

PROJECT_DIR <- locate_project()
INPUT <- Sys.getenv("EGG_DATA_FILE", unset = file.path(PROJECT_DIR, "data", "APU0000708111.csv"))
OUT <- Sys.getenv("EGG_FORECAST_OUTPUT", unset = file.path(PROJECT_DIR, "results"))
FIG <- file.path(OUT, "figures")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

# ---- Settings and colors ----------------------------------------------------
N_VALIDATION <- 3L
N_TEST <- 3L
H <- 3L
LEVELS <- c(80, 95)
METHODS <- c("SES", "Holt", "Damped Holt", "Holt-Winters", "Auto ETS",
             "Naive", "Seasonal naive")
COLORS <- c("SES" = "#7c3aed", "Holt" = "#2563eb", "Damped Holt" = "#0f766e",
            "Holt-Winters" = "#db2777", "Auto ETS" = "#4f46e5",
            "Naive" = "#b45309", "Seasonal naive" = "#64748b")
HISTORY_COLOR <- "#172554"
BAND_80 <- "#93c5fd"
BAND_95 <- "#dbeafe"

# ---- Reusable output and modeling functions --------------------------------
save_csv <- function(d, name) {
  write.csv(d, file.path(OUT, paste0(name, ".csv")), row.names = FALSE)
}

figure <- function(name, draw, height = 1000L, width = 1600L) {
  png(file.path(FIG, paste0(name, ".png")), width = width, height = height, res = 150)
  on.exit(dev.off())
  par(mar = c(5, 5, 4, 1), las = 1, family = "sans", col.main = HISTORY_COLOR,
      col.axis = "#334155", col.lab = HISTORY_COLOR, fg = "#334155", bg = "white")
  draw()
}

# Smoothing models use additive errors on log prices (lambda = 0).
# Bias adjustment returns approximate dollar-scale means rather than medians.
# Baselines use original dollar prices. All accuracy scores are in dollars.
fit_one <- function(y, method, h = H) {
  if (method == "Naive") return(forecast::naive(y, h = h, level = LEVELS))
  if (method == "Seasonal naive") return(forecast::snaive(y, h = h, level = LEVELS))
  switch(method,
    "SES" = forecast::ets(y, model = "ANN", damped = FALSE, lambda = 0, biasadj = TRUE),
    "Holt" = forecast::ets(y, model = "AAN", damped = FALSE, lambda = 0, biasadj = TRUE),
    "Damped Holt" = forecast::ets(y, model = "AAN", damped = TRUE, lambda = 0, biasadj = TRUE),
    "Holt-Winters" = forecast::ets(y, model = "AAA", damped = FALSE, lambda = 0, biasadj = TRUE),
    "Auto ETS" = forecast::ets(y, model = "ZZZ", additive.only = TRUE,
                                lambda = 0, biasadj = TRUE),
    stop("Unknown method: ", method, call. = FALSE))
}

predict_one <- function(fit, h = H) {
  if (inherits(fit, "forecast")) fit else {
    forecast::forecast(fit, h = h, level = LEVELS, biasadj = TRUE)
  }
}

prediction_rows <- function(fits, ids, split, data) {
  do.call(rbind, lapply(names(fits), function(m) {
    fc <- fits[[m]]
    data.frame(split = split, model = m, date = data$date[ids], actual = data$price[ids],
      forecast = as.numeric(fc$mean), lower80 = as.numeric(fc$lower[, "80%"]),
      upper80 = as.numeric(fc$upper[, "80%"]), lower95 = as.numeric(fc$lower[, "95%"]),
      upper95 = as.numeric(fc$upper[, "95%"]), row.names = NULL)
  }))
}

# Convert to numeric so every ACF uses explicit MONTH lags, not ts year units.
draw_acf <- function(y, heading, max_lag = 36L, color = "#2563eb") {
  acf(as.numeric(y), lag.max = max_lag, main = heading, xlab = "Lag in months",
      col = color, lwd = 2)
}

# Keep all source observations visible, with the modeling cuts on the same graph.
draw_data_split <- function(data, splits, cutoff) {
  validation_start <- splits$start[splits$split == "Validation"]
  test_start <- splits$start[splits$split == "Test"]
  excluded_start <- seq(cutoff, by = "month", length.out = 2L)[2L]
  plot(data$date, data$price, type = "n", xlab = "Month",
    ylab = "U.S. dollars per dozen", main = "Full egg-price history with data cuts: 1980-2025")
  limits <- par("usr")
  rect(validation_start, limits[3], test_start, limits[4], col = "#dbeafe", border = NA)
  rect(test_start, limits[3], excluded_start, limits[4], col = "#ccfbf1", border = NA)
  rect(excluded_start, limits[3], limits[2], limits[4], col = "#f1f5f9", border = NA)
  lines(data$date, data$price, col = HISTORY_COLOR, lwd = 2)
  abline(v = c(validation_start, test_start, excluded_start),
    col = c("#2563eb", "#0f766e", "#dc2626"), lty = c(2, 3, 4), lwd = 2)
  legend("topleft", c("Observed price (full history)",
    paste("Validation starts:", format(validation_start, "%b %Y")),
    paste("Test starts:", format(test_start, "%b %Y")),
    paste("Excluded from analysis:", format(excluded_start, "%b %Y"), "onward")),
    col = c(HISTORY_COLOR, "#2563eb", "#0f766e", "#dc2626"),
    lty = c(1, 2, 3, 4), lwd = 2, bty = "n", cex = .85)
  mtext(paste0("Training: ", format(splits$start[1], "%b %Y"), "-",
    format(splits$end[1], "%b %Y"), " | Validation: ", format(validation_start, "%b %Y"), "-",
    format(splits$end[2], "%b %Y"), " | Test: ", format(test_start, "%b %Y"), "-",
    format(cutoff, "%b %Y")), side = 3, line = .35, cex = .8)
}

