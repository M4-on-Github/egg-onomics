# Frozen pre-outbreak forecasts, not estimates of the causal effect of HPAI.
# Run separately from forecast.R; all outputs stay in results/spike_counterfactual.
run_spike_study <- function() {
  source_files <- unlist(lapply(sys.frames(), function(fr) {
    if (!is.null(fr$ofile)) as.character(fr$ofile) else character()
  }))
  cli <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  candidates <- c(rev(source_files), cli)
  candidates <- candidates[file.exists(candidates)]
  roots <- unique(c(dirname(candidates), dirname(dirname(candidates)), getwd(), dirname(getwd())))
  roots <- roots[file.exists(file.path(roots, "egg-onomics.Rproj"))]
  if (!length(roots)) stop("Run this script from the saved egg-onomics project.")
  root <- normalizePath(roots[1], winslash = "/")
  previous <- Sys.getenv("EGG_FORECAST_OUTPUT", unset = NA_character_)
  on.exit(if (is.na(previous)) Sys.unsetenv("EGG_FORECAST_OUTPUT") else
    Sys.setenv(EGG_FORECAST_OUTPUT = previous), add = TRUE)
  out <- Sys.getenv("EGG_SPIKE_OUTPUT", unset = file.path(root, "results", "spike_counterfactual"))
  Sys.setenv(EGG_FORECAST_OUTPUT = out)
  source(file.path(root, "analysis", "helpers.R"), local = TRUE)
  # This study deliberately bypasses EGG_DATA_FILE: use the original snapshot.
  input <- file.path(root, "data", "APU0000708111.csv")
  raw <- read.csv(input, stringsAsFactors = FALSE)
  d <- data.frame(date = as.Date(raw$observation_date), price = as.numeric(raw$APU0000708111))
  stopifnot(nrow(d) == 544L, !anyNA(d), all(d$price > 0), !anyDuplicated(d$date),
    identical(d$date, seq(as.Date("1980-01-01"), as.Date("2025-04-01"), by = "month")))
  events <- read.csv(file.path(root, "analysis", "spike_events.csv"), stringsAsFactors = FALSE)
  events$origin <- as.Date(events$origin)
  ALL_METHODS <- c(METHODS, "ARIMA", "Seasonal ARIMA search")
  COLORS <- c(COLORS, "ARIMA" = "#0891b2", "Seasonal ARIMA search" = "#65a30d")
  ACTUAL <- "#c2410c"
  N_FOLDS <- 6L
  slug <- function(x) gsub("[^a-z0-9]+", "_", tolower(x))

  # Accept a truncated history only. No outbreak-period actuals enter fitting.
  fit_baseline <- function(history, method, h) {
    stopifnot(nrow(history) > 24L, !anyNA(history$price))
    y <- ts(history$price, start = c(as.integer(format(history$date[1], "%Y")),
      as.integer(format(history$date[1], "%m"))), frequency = 12)
    fit <- if (method %in% c("ARIMA", "Seasonal ARIMA search")) {
      forecast::auto.arima(y, seasonal = method == "Seasonal ARIMA search",
        ic = "aicc", stepwise = TRUE, approximation = FALSE, method = "ML",
        lambda = 0, biasadj = TRUE)
    } else fit_one(y, method, h)
    fc <- predict_one(fit, h)
    dates <- seq(max(history$date), by = "month", length.out = h + 1L)[-1L]
    prediction <- data.frame(date = dates, horizon = seq_len(h), baseline = as.numeric(fc$mean),
      lower80 = as.numeric(fc$lower[, "80%"]), upper80 = as.numeric(fc$upper[, "80%"]),
      lower95 = as.numeric(fc$lower[, "95%"]), upper95 = as.numeric(fc$upper[, "95%"]))
    stopifnot(all(is.finite(as.matrix(prediction[, 3:7]))),
      all(prediction$lower95 <= prediction$lower80), all(prediction$lower80 <= prediction$baseline),
      all(prediction$baseline <= prediction$upper80), all(prediction$upper80 <= prediction$upper95))
    list(fit = fit, prediction = prediction)
  }
  model_label <- function(fit) {
    if (inherits(fit, "Arima")) {
      a <- fit$arma
      paste0("ARIMA(", a[1], ",", a[6], ",", a[2], ")(", a[3], ",", a[7], ",", a[4], ")[", a[5], "]")
    } else if (!is.null(fit$method)) fit$method else class(fit)[1]
  }
  predictions <- cv_predictions <- folds <- selections <- audit <- sensitivity <- list()
  saved <- list()
  for (e in seq_len(nrow(events))) {
    event <- events[e, ]
    origin_id <- match(event$origin, d$date)
    h <- event$forecast_months
    stopifnot(!is.na(origin_id), origin_id - N_FOLDS * h > 24L)
    # Six disjoint 12-month validation blocks; the last ends at the origin.
    cv_ends <- origin_id - seq.int(N_FOLDS, 1L) * h
    event_cv <- list()
    for (fold in seq_along(cv_ends)) {
      end <- cv_ends[fold]
      ids <- seq.int(end + 1L, end + h)
      stopifnot(max(d$date[ids]) <= event$origin)
      folds[[length(folds) + 1L]] <- data.frame(event = event$event, fold = fold,
        train_start = d$date[1], train_end = d$date[end], validation_start = d$date[min(ids)],
        validation_end = d$date[max(ids)], months = h)
      for (method in ALL_METHODS) {
        cat(event$event, "CV", fold, "/", N_FOLDS, method, "\n")
        p <- fit_baseline(d[seq_len(end), ], method, h)$prediction
        event_cv[[length(event_cv) + 1L]] <- data.frame(event = event$event, fold = fold,
          model = method, origin = d$date[end], p, actual = d$price[ids])
      }
    }
    cv <- do.call(rbind, event_cv)
    score <- do.call(rbind, lapply(ALL_METHODS, function(method) {
      z <- cv[cv$model == method, ]
      data.frame(event = event$event, model = method, CV_RMSE = sqrt(mean((z$actual-z$baseline)^2)),
        CV_MAE = mean(abs(z$actual-z$baseline)), folds = N_FOLDS, outcomes = nrow(z))
    }))
    # Stable tie breaking uses the fixed order of methods, never outbreak scores.
    winner <- score$model[which.min(score$CV_RMSE)]
    score$selected <- score$model == winner
    selections[[e]] <- score
    cv_predictions[[e]] <- cv
    cat("Pre-event selection:", event$event, winner, "\n")
    fits <- list()
    for (method in ALL_METHODS) {
      fitted <- fit_baseline(d[seq_len(origin_id), ], method, h)
      fits[[method]] <- fitted$fit
      p <- fitted$prediction
      p$actual <- d$price[match(p$date, d$date)]
      p$gap <- p$actual - p$baseline
      p$gap_pct <- 100 * p$gap / p$baseline
      p$above_upper95 <- ifelse(is.na(p$actual), NA, p$actual > p$upper95)
      predictions[[length(predictions) + 1L]] <- data.frame(event = event$event, model = method,
        origin = event$origin, selected = method == winner, p)
      audit[[length(audit) + 1L]] <- data.frame(event = event$event, model = method,
        train_start = d$date[1], train_end = event$origin, train_months = origin_id,
        selection_last_outcome = max(cv$date), forecast_start = min(p$date),
        forecast_end = max(p$date), observed_outcomes = sum(!is.na(p$actual)),
        structure = model_label(fitted$fit))
    }
    saved[[event$event]] <- fits
    # Earlier origin sensitivity: keep the same target months, but move BOTH
    # validation and fitting to the earlier origin. Select the method again
    # from only complete folds ending by then, to avoid selection leakage.
    for (shift in c(1L, 3L)) {
      earlier_id <- origin_id - shift
      eligible <- cv[cv$date <= d$date[earlier_id], ]
      # Use complete earlier folds only, keeping methods on identical targets.
      eligible_folds <- unique(eligible$fold[vapply(eligible$fold, function(f)
        sum(eligible$fold == f & eligible$model == ALL_METHODS[1]) == h, logical(1))])
      eligible <- eligible[eligible$fold %in% eligible_folds, ]
      earlier_scores <- vapply(ALL_METHODS, function(m) {
        z <- eligible[eligible$model == m, ]; sqrt(mean((z$actual-z$baseline)^2))
      }, numeric(1))
      earlier_method <- ALL_METHODS[which.min(earlier_scores)]
      p <- fit_baseline(d[seq_len(earlier_id), ], earlier_method, h + shift)$prediction
      p <- p[p$date > event$origin, ]
      sensitivity[[length(sensitivity) + 1L]] <- data.frame(event = event$event,
        origin = d$date[earlier_id], months_earlier = shift, model = earlier_method,
        selection_last_outcome = max(eligible$date), p,
        actual = d$price[match(p$date, d$date)])
    }
  }
  pred <- do.call(rbind, predictions)
  cv <- do.call(rbind, cv_predictions)
  fold_table <- do.call(rbind, folds)
  selection <- do.call(rbind, selections)
  audit <- do.call(rbind, audit)
  sensitivity <- do.call(rbind, sensitivity)
  summary_rows <- do.call(rbind, lapply(split(pred, interaction(pred$event, pred$model, drop = TRUE)), function(z) {
    observed <- z[!is.na(z$actual), ]
    peak <- observed[which.max(observed$actual), ]
    first3 <- observed[observed$horizon <= 3L, ]
    data.frame(event = z$event[1], model = z$model[1], selected = z$selected[1],
      observed_months = nrow(observed), RMSE = sqrt(mean(observed$gap^2)),
      RMSE_first3 = sqrt(mean(first3$gap^2)), mean_gap = mean(observed$gap),
      mean_gap_pct = mean(observed$gap_pct), peak_date = peak$date,
      peak_actual = peak$actual, baseline_at_peak = peak$baseline, gap_at_peak = peak$gap,
      gap_pct_at_peak = peak$gap_pct, months_above95 = sum(observed$above_upper95),
      mean_actual = mean(observed$actual), mean_baseline = mean(observed$baseline))
  }))
  # Audits target the substantive risks: calendar leakage and accidental updating.
  stopifnot(nrow(pred) == nrow(events) * 9L * 12L,
    all(pred$date > pred$origin), all(fold_table$train_end < fold_table$validation_start),
    all(audit$selection_last_outcome <= audit$train_end),
    all(sensitivity$selection_last_outcome <= sensitivity$origin),
    all(table(pred$event[pred$selected]) == 12L))
  for (event in events$event) {
    z <- fold_table[fold_table$event == event, ]
    stopifnot(all(z$validation_start[-1] > head(z$validation_end, -1)))
  }
  for (name in c("pred", "cv", "fold_table", "selection", "audit", "sensitivity", "summary_rows")) {
    dest <- c(pred="predictions", cv="cv_predictions", fold_table="cv_folds", selection="model_selection",
      audit="leakage_audit", sensitivity="origin_sensitivity", summary_rows="all_model_summary")[[name]]
    save_csv(get(name), dest)
  }
  chosen <- summary_rows[summary_rows$selected, ]
  chosen <- chosen[match(events$event, chosen$event), ]
  save_csv(chosen, "selected_summary")
  save_csv(events, "event_definitions")
  saveRDS(saved, file.path(out, "frozen_models.rds"))
  jsonlite::write_json(list(source_md5 = unname(tools::md5sum(input)), n = nrow(d),
    last_observation = as.character(max(d$date)), folds = N_FOLDS,
    selection = "Minimum RMSE across six disjoint pre-origin 12-month blocks",
    fitting_window = "All observed history from January 1980 through each origin",
    horizon_months = 12, causal_effect = FALSE, missing_values_imputed = 0,
    models = ALL_METHODS, forecast_package = as.character(packageVersion("forecast"))),
    file.path(out, "settings.json"), pretty = TRUE, auto_unbox = TRUE)
  writeLines(capture.output(sessionInfo()), file.path(out, "sessionInfo.txt"))

  # Connect means AND interval shading to the last observed price at the origin.
  draw_forecast <- function(event_id, method, all_models = FALSE) {
    event <- events[events$event == event_id, ]
    p <- pred[pred$event == event_id & pred$model == method, ]
    history <- d[d$date <= event$origin & d$date >= seq(event$origin, by="-1 month", length.out=19)[19], ]
    actual <- d[d$date > event$origin & d$date <= max(p$date), ]
    anchor <- tail(history$price, 1)
    x <- c(event$origin, p$date)
    other <- pred[pred$event == event_id, ]
    yrange <- if (all_models) range(c(history$price, actual$price, other$baseline)) else
      range(c(history$price, actual$price, p$lower95, p$upper95))
    plot(history$date, history$price, type="n", xlim=range(c(history$date, p$date)), ylim=yrange,
      xlab="Month", ylab="U.S. dollars per dozen", main=paste(event$label, if (all_models) "| All nine frozen forecasts" else paste("|", method)))
    if (!all_models) {
      polygon(c(x, rev(x)), c(anchor, p$lower95, rev(c(anchor, p$upper95))), col=BAND_95, border=NA)
      polygon(c(x, rev(x)), c(anchor, p$lower80, rev(c(anchor, p$upper80))), col=BAND_80, border=NA)
    }
    abline(v=event$origin, lty=3, col="#64748b")
    lines(history$date, history$price, col=HISTORY_COLOR, lwd=2)
    if (all_models) for (m in ALL_METHODS) {
      q <- other[other$model == m, ]; lines(x, c(anchor, q$baseline), col=COLORS[[m]], lwd=1.8)
    } else {
      lines(x, c(anchor, p$baseline), col=COLORS[[method]], lwd=2.5)
      points(p$date, p$baseline, col=COLORS[[method]], pch=16, cex=.5)
    }
    lines(c(event$origin, actual$date), c(anchor, actual$price), col=ACTUAL, lwd=2.5)
    points(actual$date, actual$price, col=ACTUAL, pch=16, cex=.6)
    if (all_models) legend("topleft", c("Observed history", "Actual afterward", ALL_METHODS),
      col=c(HISTORY_COLOR, ACTUAL, COLORS[ALL_METHODS]), lty=1, lwd=2, ncol=2, bty="n", cex=.75) else
      legend("topleft", c("Observed history", "Actual afterward", "Frozen baseline", "80% forecast interval", "95% forecast interval"),
        col=c(HISTORY_COLOR,ACTUAL,COLORS[[method]],BAND_80,BAND_95), lwd=c(2,2,2,8,8), bty="n", cex=.8)
    mtext(paste("Frozen after", format(event$origin, "%b %Y"), "| Model-based reference, not a causal no-virus estimate"), side=3, line=.3, cex=.8)
  }
  for (event in events$event) {
    method <- chosen$model[chosen$event == event]
    figure(paste0(event, "_selected"), function() draw_forecast(event, method))
    figure(paste0(event, "_all_models"), function() draw_forecast(event, method, TRUE))
    for (m in ALL_METHODS) figure(paste0(event, "_", slug(m)), function() draw_forecast(event, m))
    z <- pred[pred$event == event & pred$selected & !is.na(pred$actual), ]
    figure(paste0(event, "_gap"), function() {
      plot(z$date, z$gap, type="h", lwd=12, col=ifelse(z$gap >= 0, ACTUAL, "#0f766e"),
        ylim=range(c(0,z$gap)), xlab="Month", ylab="Actual minus frozen baseline ($ per dozen)",
        main=paste(events$label[events$event == event], "| Departure from", method))
      abline(h=0, col="#64748b"); points(z$date,z$gap,pch=16,col=HISTORY_COLOR)
      mtext("Includes every unmodeled influence; not an HPAI effect estimate",side=3,line=.3,cex=.8)
    })
  }
  html_table <- function(tab) {
    tab[] <- lapply(tab, function(x) if (is.numeric(x)) format(round(x, 3), trim=TRUE) else as.character(x))
    paste0('<div class="scroll"><table><tr>',paste0('<th>',names(tab),'</th>',collapse=''),'</tr>',
      paste(apply(tab,1,function(row) paste0('<tr>',paste0('<td>',row,'</td>',collapse=''),'</tr>')),collapse=''),'</table></div>')
  }
  img <- function(name) paste0('<img alt="',name,'" src="data:image/png;base64,',
    jsonlite::base64_enc(readBin(file.path(FIG,paste0(name,'.png')),'raw',n=file.info(file.path(FIG,paste0(name,'.png')))$size)),'">')
  viewer <- c('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Egg prices before the spikes</title>',
    '<style>body{font:16px/1.6 system-ui;color:#172554;background:#f8fafc;margin:0}main{max-width:1100px;margin:auto;padding:32px 24px}img{width:100%;background:white;margin:12px 0}.note{background:#fffbeb;border-left:4px solid #b45309;padding:16px}table{border-collapse:collapse;background:white;font-size:13px}td,th{padding:8px;border:1px solid #cbd5e1;white-space:nowrap}th{background:#dbeafe}.scroll{overflow:auto}summary{cursor:pointer;font-weight:600;margin:12px 0}h2{margin-top:36px}</style><main>',
    '<h1>Egg prices before the spikes</h1><p>Freeze the forecast before each documented outbreak period, then compare it with what happened.</p>',
    '<p class="note">These are forecasts of how earlier price patterns might continue. They do not identify prices in a world without HPAI. Feed costs, inflation, demand, policy and other shocks also enter the gaps. The 2024 origin already includes earlier HPAI waves and higher prices.</p>',
    '<h2>Design</h2><p>Original 544 monthly prices only, January 1980–April 2025. Each origin uses all earlier history; six disjoint 12-month rolling validation blocks select among the nine existing R models. Selection and fitting stop at the origin. Forecasts remain frozen for 12 months, with no actual-price updates. All structures and coefficients are re-estimated using the available history. The 80%/95% bands are model forecast intervals, not confidence intervals for a causal effect.</p>',
    '<p>Episode boundaries come from the sources below, not an algorithm searching for the largest residuals. This is a retrospective, exploratory study. Seven months are observed for the October 2024–September 2025 forecast; the five remaining actual prices are unavailable and are not filled. Different event horizons must not be ranked as comparable accuracy tests.</p>',
    html_table(chosen[,c("event","model","observed_months","RMSE_first3","mean_gap","peak_date","peak_actual","baseline_at_peak","gap_at_peak","months_above95")]))
  for (event in events$event) {
    ev <- events[events$event==event, ]
    viewer <- c(viewer,paste0('<h2>',ev$label,'</h2><p>Origin: ',format(ev$origin,'%B %Y'),'. ',ev$reason,' <a href="',ev$source_url,'">Timing source</a>.</p>'),
      img(paste0(event,'_selected')),img(paste0(event,'_gap')),
      '<details><summary>Pre-event model selection and all nine baselines</summary>',
      html_table(selection[selection$event==event, ]),img(paste0(event,'_all_models')),
      html_table(summary_rows[summary_rows$event==event, ]),'</details>',
      '<details><summary>Individual model graphs</summary>',
      vapply(ALL_METHODS,function(m) img(paste0(event,'_',slug(m))),character(1)),'</details>')
  }
  viewer <- c(viewer,'<h2>Earlier-origin sensitivity</h2><p>origin_sensitivity.csv moves each origin back one and three months. The model is selected again using only complete validation folds ending before that earlier origin (five folds). Targets stay on the same event months. Results show dependence on origin and method choice; they do not create a causal control group.</p>',
    '<h2>Reproduce</h2><p>Run <code>Rscript analysis/spike_counterfactual.R</code> or use <code>analysis/spike_counterfactual.ipynb</code>. CSVs retain all 324 forecasts, observed gaps, per-fold validation predictions, selection scores, earlier-origin sensitivity and calendar audits. frozen_models.rds and sessionInfo.txt retain fitted models and runtime details.</p></main></html>')
  writeLines(viewer,file.path(out,"index.html"),useBytes=TRUE)
  print(chosen, row.names=FALSE)
  cat("\nSaved pre-spike study to", out, "\n")
  invisible(list(predictions=pred, summary=chosen, audit=audit))
}

if (Sys.getenv("EGG_SPIKE_AUTORUN", "1") == "1") run_spike_study()
