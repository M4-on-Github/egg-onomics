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
  html <- c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Egg prices three-month forecasts</title>',
    '<style>body{margin:0;background:#f8fafc;color:#172554;font:16px/1.6 system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:40px 24px}h1{font-size:42px;line-height:1.15}h2{margin-top:40px}img{width:100%;height:auto;margin:20px 0;border:1px solid #cbd5e1;border-radius:8px}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;font-size:13px;background:white}td,th{padding:10px;border:1px solid #cbd5e1;text-align:left;white-space:nowrap}th{background:#dbeafe}.note{padding:18px;background:#fffbeb;border-left:4px solid #b45309}summary{cursor:pointer;padding:12px 0;font-weight:600}</style></head><body><main>',
    '<p>EGG-ONOMICS / ORIGINAL COMPLETE DATA</p><h1>Three-month forecasts for all nine models.</h1>',
    paste0('<p class="note">Validation selects <strong>', selected,
      '</strong>. Lowest observed test RMSE belongs to <strong>', test_scores$model[1],
      '</strong>. Validation: ', date_label(d$date[val_id]), '; test: ', date_label(d$date[test_id]), '. Each forecast is issued once from its origin and is not updated within the three-month window.</p>'),
    '<h2>1 / Original data and calendar splits</h2>', table_html(data_quality), table_html(splits),
    '<p>The input is the original complete BLS/FRED egg-price snapshot, January 1980-April 2025: 544 monthly observations with no missing prices or months. All models use observed data without filling or interpolation. Forecasts are historical, starting after April 2025.</p>',
    img("00_history", "Original complete egg-price history and evaluation boundaries"),
    img("00_training_acf", "Training ACF of log-price levels and monthly log changes"),
    img("00_training_stl", "Training STL decomposition on log prices"),
    paste0('<p>Training STL seasonal strength: ', sprintf('%.3f', seasonal_strength), '. All ACF lags are months.</p>'),
    '<h2>2 / Validation accuracy</h2>', table_html(validation_scores), img("01_validation_all", "All models in the three-month validation period"),
    '<h2>3 / Test accuracy</h2>', table_html(test_scores), img("02_test_all", "All models in the three-month test period"),
    img("04_accuracy_comparison", "Validation and test RMSE for all nine models"),
    '<p>MAE and RMSE are dollars per dozen; MAPE is percent; Coverage80 and Coverage95 are fractions. There are only three outcomes in each evaluation window, so each covered month changes coverage by 33.3 percentage points. A high coverage percentage here is weak evidence about long-run calibration.</p>',
    paste0('<h2>4 / Historical forecasts for ', date_label(future), '</h2>'), table_html(wide), img("03_future_all", "All nine three-month future forecasts"),
    '<p>Every method is refitted through April 2025. The table reports dollar-scale forecast means. Individual panels below include 80% and 95% prediction intervals; full-precision intervals are also saved in forecast_3_months_all_models.csv.</p>',
    unlist(lapply(ALL_METHODS, function(method) paste0('<details><summary>', method, ' test and future forecast</summary>',
      img(paste0("test_", slug(method)), paste(method, "three-month test forecast and intervals")),
      img(paste0("future_", slug(method)), paste(method, "three-month future forecast and intervals")), '</details>'))),
    '<h2>5 / Structures and interpretation limits</h2>', table_html(structures),
    '<h3>Training residual diagnostics</h3>', table_html(diagnostics),
    '<p>Smoothing and ARIMA residuals are log-price innovations; naive residuals are dollars. Ljung-Box tests use lag 24 and the recorded parameter adjustment. Interpret p-values together with the plots.</p>',
    unlist(lapply(ALL_METHODS, function(method) paste0('<details><summary>', method, ' residual diagnostics</summary>',
      img(paste0("residuals_", slug(method)), paste(method, "training residual diagnostics")), '</details>'))),
    '<p class="note">Only three observations are scored in each evaluation period. The test includes the early-2025 price shock, so errors and interval coverage can be poor. These dates differ from the earlier annual evaluations; comparisons do not isolate horizon alone. Treat results as an exploratory historical investigation.</p>',
    '<p>Forecasting settings and transformations match the earlier analyses. Automatic ETS and ARIMA structures are selected using each fitting window only. ARIMA searches use AICc, exact maximum likelihood and stepwise search. Three-month forecast horizon does not change the monthly seasonal period of 12.</p>',
    '<p>Reproduce with analysis/forecast.R. Predictions, means, intervals, parameters, data-quality checks and fitted objects are saved in results.</p></main></body></html>')
  writeLines(html, file.path(out, "index.html"), useBytes = TRUE)
}
