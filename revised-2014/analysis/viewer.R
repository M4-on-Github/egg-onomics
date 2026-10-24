# Presentation layer for the active original-data analysis.
write_results_viewer <- function(d, splits, data_quality, selected, validation_scores,
    test_scores, wide, ALL_METHODS, structures, diagnostics, seasonal_strength,
    FIG, out, val_id, test_id, future) {
  date_label <- function(dates) paste(format(min(dates), "%b %Y"), "to", format(max(dates), "%b %Y"))
  slug <- function(method) gsub(" ", "_", tolower(method))
  table_html <- function(x) {
    for (k in names(x)) if (is.numeric(x[[k]])) x[[k]] <- formatC(x[[k]], digits = 4, format = "f")
    paste0('<div class="scroll"><table><thead><tr>', paste0('<th>', names(x), '</th>', collapse = ''),
      '</tr></thead><tbody>', paste(apply(x, 1, function(z) paste0('<tr>',
      paste0('<td>', z, '</td>', collapse = ''), '</tr>')), collapse = ''), '</tbody></table></div>')
  }
  img <- function(name, alt) {
    path <- file.path(FIG, paste0(name, ".png"))
    paste0('<img alt="', alt, '" src="data:image/png;base64,',
      jsonlite::base64_enc(readBin(path, "raw", n = file.info(path)$size)), '">')
  }
  html <- c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Egg prices: six-month validation and test in 2014</title>',
    '<style>body{margin:0;background:#f8fafc;color:#172554;font:16px/1.6 system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:40px 24px}h1{font-size:42px;line-height:1.15}h2{margin-top:40px}img{width:100%;height:auto;margin:20px 0;border:1px solid #cbd5e1;border-radius:8px}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:13px;background:white}td,th{padding:10px;border:1px solid #cbd5e1;text-align:left;white-space:nowrap}th{background:#dbeafe}.note{padding:18px;background:#fffbeb;border-left:4px solid #b45309}summary{cursor:pointer;padding:12px 0;font-weight:600}</style></head><body><main>',
    '<p>EGG-ONOMICS / DATA THROUGH DECEMBER 2014</p><h1>Six-month validation and test in 2014.</h1>',
    paste0('<p class="note">Validation selects <strong>', selected,
      '</strong>. Lowest observed test RMSE belongs to <strong>', test_scores$model[1],
      '</strong>. Validation: ', date_label(d$date[val_id]), '; test: ', date_label(d$date[test_id]), '. Each forecast is issued once from its origin and is not updated within the six-month window.</p>'),
    '<h2>1 / Original data and calendar splits</h2>', table_html(data_quality), table_html(splits),
    '<p>The original BLS/FRED snapshot contains 544 monthly observations from January 1980 to April 2025. The active analysis uses only the 420 observations through December 2014: 408 training months through December 2013, six validation months in January-June 2014, and six test months in July-December 2014. Later prices appear only in the full-history graph. No prices are filled or interpolated.</p>',
    img("00_history", "Full 1980-2025 egg-price history with vertical cuts at January 2014, July 2014 and January 2015"),
    '<p>This single history graph keeps all observations visible. The blue line marks January 2014, when validation begins; the green line marks July 2014, when testing begins. The red line marks January 2015: prices in the grey area remain visible for context but are excluded from the analysis.</p>',
    img("00_training_acf", "Training ACF of log-price levels and monthly log changes"),
    img("00_training_stl", "Training STL decomposition on log prices"),
    paste0('<p>Training STL seasonal strength: ', sprintf('%.3f', seasonal_strength), '. All ACF lags are months.</p>'),
    '<h2>2 / Validation accuracy</h2>', table_html(validation_scores), img("01_validation_all", "All models in the six-month validation period"),
    '<h2>3 / Test accuracy</h2>', table_html(test_scores), img("02_test_all", "All models in the six-month test period"),
    img("04_accuracy_comparison", "Validation and test RMSE for all nine models"),
    '<p>MAE and RMSE are dollars per dozen; MAPE is percent; Coverage80 and Coverage95 are fractions. There are six outcomes in each evaluation window, so each covered month changes coverage by 16.7 percentage points. These short windows provide limited evidence about performance in other periods.</p>',
    paste0('<h2>4 / Historical forecasts for ', date_label(future), '</h2>'), table_html(wide), img("03_future_all", "All nine six-month historical forecasts"),
    '<p>Every method is refitted through December 2014. The January-June 2015 forecasts are projections only: 2015 actual prices do not enter fitting, selection or evaluation. The table reports dollar-scale forecast means. Individual panels below include 80% and 95% prediction intervals; full-precision intervals are saved in forecast_6_months_all_models.csv.</p>',
    unlist(lapply(ALL_METHODS, function(method) paste0('<details><summary>', method, ' individual forecasts</summary>',
      img(paste0("validation_", slug(method)), paste(method, "six-month validation forecast and intervals")),
      img(paste0("test_", slug(method)), paste(method, "six-month test forecast and intervals")),
      img(paste0("future_", slug(method)), paste(method, "six-month future forecast and intervals")), '</details>'))),
    '<h2>5 / Structures and interpretation limits</h2>', table_html(structures),
    '<h3>Training residual diagnostics</h3>', table_html(diagnostics),
    '<p>Smoothing and ARIMA residuals are log-price innovations; naive residuals are dollars. Ljung-Box tests use lag 24 and the recorded parameter adjustment. Interpret p-values together with the plots.</p>',
    unlist(lapply(ALL_METHODS, function(method) paste0('<details><summary>', method, ' residual diagnostics</summary>',
      img(paste0("residuals_", slug(method)), paste(method, "training residual diagnostics")), '</details>'))),
    '<p class="note">The 2014 validation and test months were chosen retrospectively. This changes both the evaluation dates and the horizon from the older 2024-2025 experiment, so the scores should not be presented as a like-for-like accuracy improvement. This cutoff also does not remove earlier fluctuations or shocks from training history.</p>',
    '<p>Automatic ETS and ARIMA structures are selected using each fitting window only. ARIMA searches use AICc, exact maximum likelihood and stepwise search. The six-month forecast horizon does not change the monthly seasonal period of 12.</p>',
    '<p>Reproduce with analysis/forecast.R. Predictions, means, intervals, parameters, data-quality checks and fitted objects are saved in results.</p></main></body></html>')
  writeLines(html, file.path(out, "index.html"), useBytes = TRUE)
}
