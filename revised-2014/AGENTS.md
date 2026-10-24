# Working notes

- Read `README.md` first. It is the main record of the current plan and status.
- Update `README.md` after meaningful changes to dates, modeling, outputs or
  report decisions. Keep its work log and current-results section accurate.
- This folder is the current study. Do not mix in older experiment settings or
  scores from the parent project's other folders unless the user requests it.
- Preserve the full source data and the single full-history graph with cut lines.
- When preparing a new distribution, refresh `MANIFEST.csv` after changes. Its
  hashes cover every packaged file except the manifest itself.
- Post-2014 actual prices may be used only in the post-hoc gap outputs
  (`gap_vs_actual_*`, projection plots). In the final design, that means the
  `actual_posthoc` columns, `gap_summary.csv`, `gap_by_year.csv` and the figures
  09-12 that are not marked `_clean`. Never use them for fitting, model
  selection or validation/test scoring.
- Frame the gap as forecast error of a pre-2015 model (outbreaks plus other
  changes), not as a causal "prices without the flu" estimate.
- The report and slides must be written by the team, not by AI.
- The final design is `analysis/final_two_models.R`, which writes to
  `results/final_two_models/`. It covers:
  - Damped Holt and Seasonal ARIMA only, on dollar prices with no transform;
  - training Jan 1980-Dec 2013 and test Jan-Dec 2014, with no validation set;
  - the better model chosen by 2014 test RMSE, using the tie rule in the
    script;
  - a refit through Dec 2014 and 6/12/144-month forecasts;
  - a gap scored only on the 124 months with actuals.

  Do not change this design without the team's agreement. Keep the older
  designs and results for the record. Report numbers come from the final
  design's outputs only.
- `GUIDE_FOR_REPORT_AND_SLIDES.md` is hints only. Never add report prose, slide
  text or a speaker script to it. Every number in it must come from a run;
  re-check the numbers if the script is re-run.
