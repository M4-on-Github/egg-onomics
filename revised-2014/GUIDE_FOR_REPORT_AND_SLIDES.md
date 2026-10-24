# Guide for the report and slides (hints only)

This file is a map and a checklist. It is **not** a draft. The course forbids using
AI to write the report or the slides, so nothing here is meant to be copied in.
It gives no finished sentences and no speaker script. Each item says where to look,
which numbers matter, and what to watch out for. The wording, the argument and the
slides must be your own.

Every number below comes from one run of `analysis/final_two_models.R` on
23 October 2026 (R 4.5.2, forecast 9.0.2). The script writes everything to
`results/final_two_models/`. If you re-run it, check the numbers again. Exact
values are in the CSV files named here, and `results.txt` prints all of them on
one page.

**Do not mix in numbers from `results/*.csv` (the older nine-model 6+6 design).**
They come from different forecast origins and different test windows. For
example, the old file gives Seasonal ARIMA a test RMSE of 0.0697 for Jul-Dec 2014
from a June 2014 origin, while the final design gives 0.0721 for Jan-Dec 2014
from a December 2013 origin.

---

## 0. Read these first: problems and judgement calls

1. **"About 10 time steps" in Task 5 means months, not years.** The data are
   monthly, so the 12-month forecast (Jan-Dec 2015) answers Task 5. The
   144-month (12-year) forecast is an extra. The "10 years" figure is just how
   long the post-2014 actuals run: 124 months, Jan 2015-Apr 2025. The script
   produces all three horizons (6, 12 and 144 months) and scores only the 124
   months that have actual prices. Say in the report which forecast answers
   Task 5 and why the others exist.
2. **The two models were picked after the team had seen 2014 results.** Earlier
   runs scored nine models on 2014, and Seasonal ARIMA came first with Damped
   Holt joint second (see `results/one_year_test/r_models_one_year_test.csv`).
   So the 2014 test is not fully "unseen" for this pairing, and the winner's test
   error is probably a little optimistic. The best defence is
   `sensitivity_other_test_years.csv`: Seasonal ARIMA had the lower RMSE in 8 of
   10 separate one-year tests from 2005 to 2014. Disclose this rather than hide
   it. Likewise, do not claim the tie rule was fixed in advance: it was written
   when the 2014 ranking was already known.
3. **Seasonal ARIMA is not in the PDF's list of example methods** ("Exponential
   smoothing, Holt, Damped Holt, Holt-Winters, ETS"). The list reads as examples,
   but check with the instructor or be ready to justify the choice. Holt-Winters
   is the seasonal method on the list, and its 2014 numbers already exist (see
   section 6).
4. **The "opposite ranking" is not in 2013.** On the 2013 one-year check, Seasonal
   ARIMA also beat Damped Holt: RMSE 0.0930 vs 0.1069 (`sensitivity_other_test_years.csv`,
   and reproduced from `results/val_test_12m/r_validation_12m.csv`). The flip
   happens *inside* 2014, between the two halves of the year:
   - Jan-Jun 2014: Damped Holt RMSE 0.0548 vs Seasonal ARIMA 0.0714;
   - Jul-Dec 2014: Damped Holt 0.0912 vs Seasonal ARIMA 0.0728.

   See `test_accuracy_by_half_year.csv`. This explains the older 6+6 design.
   Its Jan-Jun 2014 validation window had Damped Holt (0.0548) ahead of
   Seasonal ARIMA (0.0714); Naive was selected at 0.0547, a near tie
   (`results/validation_accuracy.csv`). Its Jul-Dec 2014 test, refit through
   June 2014, had Seasonal ARIMA at 0.0697 (`results/test_accuracy.csv`).
5. **The long-horizon 95% interval gets very wide.** Over 144 months the
   lowest 95% bound is $0.015, so it stays just above $0, but the width grows
   from $0.27 at month 1 to $4.64 at month 144. Beyond Dec 2026 the bound would
   go negative (additive errors on the dollar scale; the log transform was
   removed on purpose). Present the width as a limitation.
6. **Neither model has white-noise residuals.** The Ljung-Box test rejects at
   5% for both (section 2, Task 3). Seasonal ARIMA is much closer to white noise.
7. **Damped Holt is effectively simple exponential smoothing here.** Beta sits on
   its lower bound (0.0001), so the slope never updates. The 2014 forecast is flat
   between $2.0162 and $2.0163. Its 2014 RMSE (0.07527) matches SES and the
   non-seasonal ARIMA in the older nine-model table.
8. **Date oddity in the PDF.** The header says "Fall 2024" and "Final Due Date:
   October 21", but the file is called `Project 2026.pdf` and today is 23 October 2026.
   Confirm the real deadline and the presentation sign-up.
9. **The code was written with AI help.** The PDF says you may use class code
   "but you should edit and streamline your code and include comments", and
   "Proper use of AI tools is expected". Every team member should be able to explain each step of
   `final_two_models.R`. Decide as a team how to disclose AI help with the code,
   and whether to submit a shorter version you have edited yourselves. Both are
   your call.

---

## 1. The design in one table

| Item | Setting | Where to check |
| --- | --- | --- |
| Series | BLS average price APU0000708111, eggs, grade A, large, per dozen, U.S. city average, monthly | `data_check.csv` |
| Source file | `data/APU0000708111.csv`, 544 rows, Jan 1980-Apr 2025, MD5 `bf246189cbf9d52a5da338e57f838d30` | `data_check.csv` |
| Training | Jan 1980-Dec 2013, 408 months | `data_check.csv`, `leakage_checks.csv` |
| Test | Jan-Dec 2014, 12 months, all forecast from the Dec 2013 origin (horizons 1-12) | `test_predictions_2014.csv` |
| Validation set | none | - |
| Models | Damped Holt = ETS(A,Ad,N); Seasonal ARIMA = `auto.arima` seasonal search (AICc, stepwise, exact ML), giving ARIMA(1,1,0)(2,0,0)[12] | `model_structures.csv` |
| Scale | original dollars, no transform | - |
| Choice rule | lower 2014 test RMSE; tie = RMSEs equal to $0.001, then lower MAE, then smaller absolute ME | `better_model.csv` |
| Final fit | refit on Jan 1980-Dec 2014 (420 months); ARIMA order kept, coefficients re-estimated | `model_structures.csv` |
| Forecasts | better model only: 6, 12 and 144 months (Jan 2015-Dec 2026) | `better_forecast_*_months.csv` |
| Post-hoc check | 124 months with actuals (Jan 2015-Apr 2025); months 125-144 unscored | `gap_summary.csv` |
| Leakage checks | 9 of 9 passed | `leakage_checks.csv` |

Run it from the `revised-2014` folder with `Rscript analysis/final_two_models.R`
(about 1 minute). `file_guide.csv` lists every output file and the PDF task it supports.

---

## 2. Task by task

### Task 1: Choose an appropriate data set

- **What it really asks:** a credible source and enough observations for a
  training/test split.
- **Where the answer is:** `data_check.csv`, `figures/01_history_with_cuts.png`.
- **Numbers:**
  - 544 monthly observations; 420 are used by the models (Jan 1980-Dec 2014);
  - 408 for training, 12 for testing;
  - 124 kept back for the post-hoc check only.
- **Points worth making:**
  - The source is a government statistics agency (BLS Average Price Data).
  - The CSV layout (`observation_date`, series ID) is what FRED gives you. Cite
    both BLS (the publisher) and FRED (where you downloaded it), with the date
    you downloaded it. Check that date yourselves; it is not recorded in this folder.
- **Traps:** do not call the series "egg prices in the U.S." without the
  qualifiers. It is the average retail price for grade A large eggs, per dozen,
  U.S. city average.
- **Honest limitations:** it is a national average, so regional prices and
  cage-free versus conventional eggs are not separated.

### Task 2: Import, prepare and explore

- **What it really asks:**
  - a completeness check;
  - a plot with labelled axes;
  - a correlogram, interpreted for trend, seasonality and cycles.
- **Where the answer is:**
  - `data_check.csv`;
  - `exploration_summary.csv` and `exploration_by_decade.csv`;
  - figures 01 (history with cut lines), 02 (ACF and PACF of the price and of
    the monthly change), 03 (STL decomposition) and 04 (seasonal pattern by
    calendar month).
- **Completeness numbers:** 0 missing months, 0 missing or non-numeric prices,
  0 duplicate dates, 0 non-positive prices, 0 imputed values.
- **Price ranges:**
  - training $0.678 (May 1988) to $2.203 (Mar 2008), mean $1.146;
  - test year $1.948 to $2.210;
  - post-hoc period $1.203 to $6.227.
- **Correlogram numbers:**
  - Price ACF: lag 1 0.972, lag 12 0.802, lag 24 0.675, lag 48 0.534. This is
    a slow decay, typical of a trend or a wandering level.
  - Monthly change ACF: lag 1 -0.109, lag 12 0.264, lag 24 0.256. The
    approximate significance bound is ±0.097. The spikes at lags 12, 24 and 36
    (visible in figure 02) point to seasonality.
  - PACF of the change: lag 12 0.227, lag 24 0.180.
  - KPSS suggests 1 ordinary difference and 0 seasonal differences.
- **STL numbers:**
  - Trend strength 0.96 (strong); seasonal strength 0.30 (weak to moderate).
  - Seasonal swing about 12.4 cents. Peak in Dec (+6.0 cents) and Jan
    (+5.0 cents); trough in Jun (-6.4 cents), with May and Jul at -5.2 cents.
- **Volatility by decade (`exploration_by_decade.csv`):** the standard deviation
  of the monthly change rises with the price level.

  | Period | Mean price | Change sd | Change sd as % of mean |
  | --- | --- | --- | --- |
  | 1980s | $0.875 | 0.059 | 6.7% |
  | 1990s | $0.972 | 0.061 | 6.3% |
  | 2000s | $1.331 | 0.086 | 6.5% |
  | 2010-2013 | $1.794 | 0.104 | 5.8% |

- **Points worth making:**
  - Trend: yes (slow ACF decay, rising STL trend).
  - Seasonality: yes, but small next to the trend and the shocks.
  - Cycles: irregular multi-year swings with no fixed period. In the training
    data, the price was more than $0.40 above its level 12 months earlier in
    Jan-Feb 1984, Mar-Apr 2004, Feb 2007, Sep 2007-Jul 2008 and Oct 2011
    (worked out from the source file, not saved as an output). The annual mean
    peaked at $1.986 in 2008 and fell to $1.664 in 2009.
  - Volatility in dollars grows with the price level.
- **Traps:**
  - The lag-0 bar in the ACF is always 1. Do not read it as evidence.
  - Do not call a peak "seasonal" if it is a one-off spike.
  - If you attribute a spike to a cause (bird flu, feed costs, demand), cite a
    source.
- **Honest limitations:** the exploration uses training data only (1980-2013),
  on purpose.

### Task 3: Choose and fit at least two methods

For **each** method the PDF wants:
- why you chose it;
- the fit on the training data;
- a residual time plot, histogram and ACF;
- a forecast on the test data, plotted against the test data;
- accuracy measures.

- **Where the answer is:**
  - `model_structures.csv` and `model_parameters.csv`;
  - `figures/05_residuals_<model>.png` (time plot, histogram, ACF and Q-Q
    panels together);
  - `figures/06_test_forecast_<model>.png`;
  - `accuracy_table.csv`, `test_predictions_2014.csv`, `residual_diagnostics.csv`.

- **Why each method (hints, tie them to the Task 2 evidence):**
  - *Damped Holt:*
    - the level has a trend (slow ACF decay);
    - damping stops the trend from running on for ever, which matters for a
      price that rises and falls.
  - *Seasonal ARIMA:*
    - the differenced series has significant ACF and PACF spikes at lags 12 and
      24, which suggests seasonal autoregression;
    - KPSS asks for one difference and no seasonal difference.
  - Be honest about how the pair was really chosen (section 0, item 2).

- **Test-fit parameters (`model_parameters.csv`, rows "Test fit"):**
  - *Damped Holt:*
    - alpha 0.904: the level follows the latest price closely;
    - beta 0.0001, at the lower bound: the slope never updates;
    - phi 0.881: after 12 months the slope is multiplied by about 0.22
      (0.881^12, worked out from phi);
    - initial level $0.881, initial slope -$0.0092 per month;
    - sigma 0.0744.
  - *Seasonal ARIMA(1,1,0)(2,0,0)[12]:*
    - ar1 -0.191 (se 0.050): a monthly change tends to reverse slightly the
      next month;
    - sar1 0.228 (se 0.048) and sar2 0.233 (se 0.049): this month's change
      echoes the same month 1 and 2 years earlier;
    - sigma 0.0690;
    - no constant or drift term.
  - The three ARIMA coefficients are 3.8 to 4.7 standard errors from zero.

- **Residual numbers (`residual_diagnostics.csv`, training, 408 months):**

  | | Damped Holt | Seasonal ARIMA |
  | --- | --- | --- |
  | Residual sd | 0.0739 | 0.0687 |
  | Mean | 0.0033 | 0.0018 |
  | ACF lag 1 | -0.008 | 0.009 |
  | ACF lag 12 | **0.279** | -0.055 |
  | ACF lag 24 | **0.274** | -0.071 |
  | Ljung-Box p, lag 12 (fitdf 3) | below 0.0001 | 0.015 |
  | Ljung-Box p, lag 24 | below 0.0001 | 0.0005 |
  | Excess kurtosis | 1.64 | 0.89 |
  | Largest residual | Oct 2010 | Oct 2010 |

  The ACF bound is ±0.097.

- **Accuracy numbers:** see Task 4.

- **Traps:**
  - Task 3 asks for "difference error measurements" and Task 4 for "different
    error measures". Either way, report several measures built from
    actual minus forecast: at least ME, MAE, RMSE, MAPE and MASE.
  - State the sign convention: error = actual - forecast, so a positive ME
    means the forecast was too low.
  - State the MASE scale: the in-sample MAE of the 12-month seasonal naive
    forecast on the training data.
  - Do not compare AIC or AICc between the ETS model and the ARIMA model
    (339.3 vs -1013.8). The forecast package computes the two likelihoods in
    different ways, and the ARIMA one is for the differenced series, so they
    are not on the same basis.
- **Honest limitations:**
  - Both residual series have heavier tails than a normal distribution (see
    the Q-Q panels).
  - Residuals grow over time (`residual_sd_by_decade.csv`, Seasonal ARIMA:
    0.059 in the 1980s, 0.053 in the 1990s, 0.081 in the 2000s, 0.090 in
    2010-13).
  - The model sigma (0.069) is therefore below the recent residual sd (0.090,
    about 1.3 times larger). The intervals are likely too narrow at 2014 price
    levels.

### Task 4: Compare the methods

- **What it really asks:**
  - what the residual plots tell you;
  - whether the error measures agree or are mixed, and what a mixed result
    means;
  - which model is best for the task.
- **Where the answer is:**
  - `accuracy_table.csv`, `better_model.csv`, `test_accuracy_by_half_year.csv`;
  - figures 07 (forecasts and monthly errors) and 08 (error-measure bars);
  - `sensitivity_other_test_years.csv`.

- **2014 test, 12 months from the Dec 2013 origin:**

  | Model | ME | MAE | RMSE | MAPE | MASE | 80% cover | 95% cover |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | Damped Holt | 0.0022 | 0.0573 | 0.0753 | 2.78% | 0.428 | 12/12 | 12/12 |
  | Seasonal ARIMA | 0.0366 | 0.0508 | 0.0721 | 2.44% | 0.379 | 12/12 | 12/12 |

  - The better model is **Seasonal ARIMA**, decided by RMSE. The margin is
    $0.0031 (4.2%).
  - Seasonal ARIMA wins MAE, RMSE, MAPE and MASE. Damped Holt wins on absolute
    ME. So the result is mixed.

- **Training one-step fit (not a test):**
  - Damped Holt: RMSE 0.0739, MAE 0.0549.
  - Seasonal ARIMA: RMSE 0.0687, MAE 0.0511.

- **Points worth making:**
  - *Residuals:*
    - Damped Holt leaves clear seasonality behind (lag-12 and lag-24 ACF about
      0.28). Seasonal ARIMA removes most of it.
    - That is a reason to prefer Seasonal ARIMA that does not depend on the
      test year.
  - *Why the result is mixed:*
    - Damped Holt's flat line ($2.016) happened to sit almost exactly at the
      2014 average actual price ($2.0185). Its errors cancel, so its ME is
      near 0.
    - Seasonal ARIMA follows the shape of the year better, giving smaller
      typical errors. But it was too low on average by $0.037, mostly
      in Mar-May and Dec 2014 (`test_predictions_2014.csv`).
    - ME measures bias; MAE and RMSE measure size. The two models trade one
      against the other.
  - *Half-year flip:*
    - Damped Holt wins Jan-Jun (RMSE 0.0548 vs 0.0714).
    - Seasonal ARIMA wins Jul-Dec (0.0728 vs 0.0912).
    - A choice based on six months could go either way.
  - *Wider evidence:* over one-year tests from 2005 to 2014, Seasonal ARIMA
    has the lower RMSE in 8 of 10 years. Damped Holt wins 2005 and 2011.
  - *Biggest single misses:*
    - Dec 2014: actual $2.210; errors +0.194 (Damped Holt) and +0.162
      (Seasonal ARIMA).
    - Apr 2014: actual $2.119; errors +0.103 and +0.137.
- **Traps:**
  - A $0.003 RMSE gap on 12 months is not a significance test, so do not call
    it "significantly better".
  - 100% interval coverage on 12 months does not prove the intervals are
    right. The year was calm, and with well-calibrated 80% intervals you would
    expect a miss or two.
  - Remember section 0, item 2: selection was informed by the test year.
- **Honest limitations:** one test year; one forecast origin.

### Task 5: Forecast

- **What it really asks:**
  - a forecast of about 10 time steps from the chosen method;
  - a plot with the data, intervals, labelled axes and a title.
- **Where the answer is:**
  - `better_forecast_12_months.csv`;
  - `figures/10_better_forecast_12_months_clean.png`: the forecast only, no
    post-2014 actuals. Use this one for Task 5.
  - `better_forecast_6_months.csv` and `figures/09_..._clean.png`: the shorter
    view.
  - `better_forecast_144_months.csv` and `figures/11_..._clean.png`: the
    12-year extra.
- **Final model:** Seasonal ARIMA(1,1,0)(2,0,0)[12], refit on Jan 1980-Dec 2014.
  - Coefficients (`model_parameters.csv`, "Final fit"): ar1 -0.183, sar1 0.233,
    sar2 0.234, sigma 0.0689.
  - A fresh order search on data through Dec 2014 picks the same order
    (`model_structures.csv`, "Check only" row).
- **12-month forecast, from `better_forecast_12_months.csv`:**

  | Month | Point forecast | 80% interval | 95% interval |
  | --- | --- | --- | --- |
  | Jan 2015 | $2.162 | 2.074 to 2.250 | 2.027 to 2.297 |
  | Jun 2015 | $2.135 | 1.947 to 2.323 | 1.847 to 2.422 |
  | Dec 2015 | $2.235 | 1.973 to 2.497 | 1.834 to 2.636 |

  The 12-month mean is $2.163. The width of the 95% interval is $0.27 at month
  1, $0.80 at month 12, $4.23 at month 124 and $4.64 at month 144.
- **Points worth making:**
  - The forecast is almost flat with a small seasonal shape: it rises to
    $2.189 in April, dips to $2.129 in July and rises again to $2.235 in
    December.
  - The intervals widen quickly because the model has a unit root (d = 1).
- **Traps:**
  - The PDF says "confidence intervals". These are *prediction* intervals for a
    future value. Use the right term, or explain the difference in a phrase.
  - Use the `_clean` figure for the forecast itself. The versions with the
    orange actual line are for the post-hoc check only and must say so.
- **Honest limitations:**
  - There is no drift or inflation term. The long-run forecast settles at about
    $2.34 in nominal dollars (the 144-month mean ranges from $2.13 to $2.34).
  - At long horizons the 95% lower bound is negative (section 0, item 5).

### Task 6: Report (word-processed, for a boss who knows forecasting)

- **What it really asks:**
  - Introduce the data: source, why it matters, plots and what they mean for
    forecasting.
  - Compare and justify the methods, with residual plots and accuracy measures.
  - Present the forecast graph.
  - Say how confident you are, which decisions the forecast supports, and what
    data you would collect next time.
- **Where the answer is:** everything above, plus `gap_summary.csv`,
  `gap_by_year.csv` and figures 11 and 12, for the confidence discussion.
- **Post-hoc check: the Dec 2014 forecast against actual prices that were never
  used** (`gap_summary.csv`):

  | Window | ME | MAE | RMSE | MAPE | 80% cover | 95% cover | Months actual above |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | 6 months (Jan-Jun 2015) | -0.009 | 0.154 | 0.204 | 6.8% | 4/6 | 5/6 | 1/6 |
  | 12 months (2015) | +0.307 | 0.388 | 0.475 | 14.5% | 4/12 | 5/12 | 7/12 |
  | 124 months (Jan 2015-Apr 2025) | -0.104 | 0.773 | 0.974 | 37.7% | 68/124 | 93/124 | 40/124 |
  | Months 125-144 (May 2025-Dec 2026) | unscored | | | | | | |

  - Mean actual over 124 months: $2.188. Mean forecast: $2.293.
  - Actuals above the 95% band: 14 months (Jun-Dec 2015, Dec 2022-Feb 2023,
    Jan-Apr 2025).
  - Actuals below the 95% band: 17 months (May 2016-Sep 2017).
- **Gap by year (mean of actual minus forecast, `gap_by_year.csv`):**

  | Year | Gap |
  | --- | --- |
  | 2015 | +0.31 |
  | 2016 | -0.54 |
  | 2017 | -0.80 |
  | 2018 | -0.55 |
  | 2019 | -0.92 |
  | 2020 | -0.82 |
  | 2021 | -0.65 |
  | 2022 | +0.53 |
  | 2023 | +0.46 |
  | 2024 | +0.84 |
  | 2025 (Jan-Apr only) | +3.21 |

  In Jan-Apr 2025 the mean actual was $5.55 against a forecast of $2.34.

- **Points worth making on confidence:**
  - *Short horizon:*
    - In 2014 both models stayed inside their intervals.
    - In Jan-May 2015 the forecast was too high every month, by 4 to 19
      cents. May 2015 ($1.962) fell just below the 80% band.
    - June 2015 ($2.570) then jumped above the 95% band.
    - The 6-month ME of -0.009 is near zero only because five months too
      high and one month 44 cents too low cancel out. Look at MAE and RMSE,
      not ME, for this window (`better_forecast_6_months.csv`).
  - *Beyond a year:*
    - The forecast is a baseline that ignores shocks. The errors run both
      ways: actual prices were far *below* the projection for six years
      (2016-2021) and far *above* it in 2022-2025.
  - *Intervals:* likely too narrow at today's price levels (Task 3
    limitations), and partly negative at long horizons.
- **Decisions the forecast could support (hints):**
  - short-term budgeting or purchasing for a food business, school canteen or
    food bank;
  - setting a price range to plan against, rather than a single number;
  - deciding when to review the plan, for example when the price leaves the
    80% band.
- **Data to collect next time (hints):**
  - outbreak data (USDA APHIS detections, layer flock losses);
  - flock size and production (USDA NASS "Chickens and Eggs");
  - feed costs (corn and soybean prices);
  - wholesale egg prices (USDA AMS);
  - CPI, to separate inflation from real price changes;
  - the cage-free share of production.
- **Traps:**
  - The post-hoc gap is the forecast error of a pre-2015 model. It mixes
    outbreaks with inflation, feed costs, cage-free rules and everything else.
    It is **not** an estimate of "prices without the flu".
  - Because the signed error changes direction, the 124-month RMSE ($0.974) is
    not "the cost of the shocks". The README's "Claim 3" uses that label. A
    qualifying note has been added there, and the report must qualify it too.
  - Post-2014 actuals were never used for fitting or choosing (all 9 leakage
    checks passed). Say so, so the reader does not suspect hindsight.
- **Honest limitations:**
  - a single forecast origin (Dec 2014);
  - dollar-scale additive errors;
  - no outside predictors;
  - the post-hoc years include unusual events, so they test robustness to
    shocks more than everyday accuracy.

### Task 7: Present

- **What it really asks:** each member makes **their own** 5-7 minute
  presentation and gives it one-on-one in the instructor's office. Slides are an
  individual product.
- **Where the answer is:** section 4 below gives a plan. Each member builds and
  words their own deck.
- **Traps:**
  - Several near-identical decks could look like shared or generated work. Vary
    the emphasis, and know every number on your own slides.
  - One-on-one means questions. Rehearse section 5.

### Academic integrity

- **Data:** real BLS data, unchanged, with no filled or imputed values
  (`data_check.csv`).
- **Code:**
  - The PDF allows class code, edited, streamlined and commented.
  - `final_two_models.R` is long (several hundred lines) and was written with
    AI help. See section 0, item 9.
- **Report and slides:** must be written by the team. Allowed AI uses, per the
  PDF: ideas for data sources, editing written work, editing slides or
  backgrounds.

---

## 3. Suggested report structure (headings and required content only)

1. **Title, team, date, data source.**
2. **Summary for the boss.** The question, the chosen model, the 12-month
   forecast range, and how far it can be trusted.
3. **Data.**
   - Source and citation (BLS, FRED, download date).
   - Why it matters.
   - Completeness check.
   - Figure 01.
4. **Exploration.**
   - Correlogram interpretation: trend, seasonality, cycles (figure 02).
   - Decomposition (figure 03) and monthly pattern (figure 04).
   - Volatility by decade.
5. **Design.**
   - Training and test dates and counts.
   - Why no validation set.
   - Why the study stops in Dec 2014.
   - The rule for picking the better model.
   - Leakage safeguards.
6. **Methods.** For each model: why chosen, specification, fitted parameters and
   what each one means.
7. **Residual diagnostics.** Figures 05, the Ljung-Box table and the
   interpretation.
8. **Test results and comparison.**
   - Accuracy table, figures 06, 07 and 08.
   - The mixed result and what it means.
   - The half-year flip.
   - The sensitivity years.
   - The choice and how firm it is.
9. **Forecast.**
   - The final fit.
   - The 12-month forecast figure (clean version) and table.
   - Which horizon answers Task 5, and why 6 and 144 months are also shown.
10. **Confidence and post-hoc check.**
    - Interval behaviour.
    - The gap tables and figures 11 and 12, with the correct framing.
    - The negative lower bound.
11. **Decisions and future data.**
12. **Limitations.** Selection-informed test, one origin, dollar scale, residual
    structure, no outside predictors.
13. **Appendix.** How to run the code, the file list (`file_guide.csv`),
    session info, and AI-use disclosure as agreed by the team.

---

## 4. Slide plan for 5-7 minutes (one figure per slide)

Topic labels, not slide text. Each member writes their own titles and words.
The plan below adds up to about 6 minutes, which leaves room for questions.

| # | Topic | Figure | Time |
| --- | --- | --- | --- |
| 1 | The question and the data | `01_history_with_cuts.png` | 0:40 |
| 2 | What the correlogram shows | `02_correlogram.png` (or `03_stl_decomposition.png`) | 0:50 |
| 3 | The two models and their residuals | `05_residuals_seasonal_arima.png` (quote Damped Holt's lag-12 ACF of 0.28 for contrast) | 0:50 |
| 4 | The 2014 test | `07_test_comparison.png` | 0:50 |
| 5 | Error measures and the choice | `08_accuracy_comparison.png` | 0:40 |
| 6 | The 12-month forecast | `10_better_forecast_12_months_clean.png` | 0:50 |
| 7 | How far to trust it | `12_gap_by_year.png` or `11_better_forecast_144_months.png` | 0:50 |
| 8 | Decisions and next data | none, or reuse figure 10 | 0:30 |

Notes:
- One number per point is enough on a slide. Keep the tables for the report.
- If you show any figure with the orange post-2014 line, label it as a post-hoc
  check.
- Figures are PNG at 150 dpi, 1600-1800 px wide and 900-1500 px tall, on a
  white background.

---

## 5. Likely questions and where the evidence is

| Question | Evidence to look at |
| --- | --- |
| Is the data complete? Where is it from? | `data_check.csv`: 0 missing, 0 imputed; BLS APU0000708111 via FRED |
| Is there a trend? Seasonality? Cycles? | `exploration_summary.csv`: ACF lag 1 0.972; change ACF lag 12 0.264; STL seasonal strength 0.30, trend 0.96 |
| Why these two models? Why not Holt-Winters, given the seasonality? | Task 2 evidence. Holt-Winters 2014 test RMSE 0.0832, 7th of 9 (`results/one_year_test/`), though it was best on 2013 with 0.0434 (`results/val_test_12m/`). Both tables reproduced exactly on 23 Oct 2026 |
| Did you see the test year before choosing? | Yes, for the pairing (section 0, item 2); 8 of 10 years in `sensitivity_other_test_years.csv` |
| Is a $0.003 RMSE difference meaningful? | 4.2% margin, one year, half-year flip (`test_accuracy_by_half_year.csv`), 8 of 10 years |
| Why is the Damped Holt forecast a flat line? | beta 0.0001 at its bound, phi 0.881 (`model_parameters.csv`); 2014 forecast $2.0162-2.0163 |
| The residuals fail Ljung-Box. So what? | `residual_diagnostics.csv`: Seasonal ARIMA p 0.015 (lag 12) and 0.0005 (lag 24), Damped Holt below 0.0001; point forecasts are usable but intervals and structure are imperfect |
| Why compare on RMSE and not AICc? | AICc is not comparable across ETS and ARIMA; RMSE is measured on the same 12 months for both |
| What does MASE 0.379 mean? | test MAE is 38% of the in-sample seasonal-naive MAE |
| Why is 2014 coverage 100%? | 12 calm months; with 80% intervals you would expect about 2 misses; intervals likely too narrow at high price levels (`residual_sd_by_decade.csv`) |
| Why not use a log scale? | Team decision (README work log): all prices positive and between $0.68 and $2.21 before 2015, same scale for all models; cost: negative long-run lower bound and intervals that do not scale with the price level |
| Why does the 12-year forecast go flat? | ARIMA with d = 1 and no drift; seasonal AR terms fade; mean settles near $2.34 |
| Why does the interval go below $0? | additive dollar errors; the 95% interval is $4.64 wide at month 144 and would cross $0 just after Dec 2026 |
| Is the gap the cost of bird flu? | No: forecast error of a pre-2015 model, signed both ways (`gap_by_year.csv`) |
| Why stop at Dec 2014 when data run to 2025? | the team's design: the calmer pre-2015 regime is modelled, and later data give an honest check; months 125-144 unscored |
| How would you improve it? | outside predictors, rolling origins, a variance-stabilising scale, more recent training data; see Task 6 data list |

---

## 6. Other numbers you may need (all checked)

- **Older nine-model one-year test, Jan-Dec 2014 (fit through Dec 2013), RMSE**
  (`results/one_year_test/r_models_one_year_test.csv`, reproduced in a scratch
  copy on 23 Oct 2026):

  | Model | RMSE |
  | --- | --- |
  | Seasonal ARIMA | 0.0721 |
  | Damped Holt, ARIMA, SES | 0.0753 |
  | Naive | 0.0756 |
  | Holt | 0.0766 |
  | Holt-Winters | 0.0832 |
  | Auto ETS | 0.1158 |
  | Seasonal naive | 0.1205 |

- **Older 2013 one-year check (fit through Dec 2012), RMSE**
  (`results/val_test_12m/r_validation_12m.csv`):

  | Model | RMSE |
  | --- | --- |
  | Holt-Winters = Auto ETS | 0.0434 |
  | Seasonal ARIMA | 0.0930 |
  | Damped Holt | 0.1069 |

- **Agreement with the older pipeline:** the post-hoc gap numbers in this guide
  match the "Seasonal ARIMA search" rows of `results/gap_vs_actual_summary.csv`.
  Both use the same order and the same data through 2014.
- **Order stability:** the training search, the Dec 2014 search and 8 of the 10
  sensitivity years all give ARIMA(1,1,0)(2,0,0)[12]. The 2009 and 2010 test
  years gave (2,1,0)(2,0,0)[12].
- **Damped Holt phi in the sensitivity years:** it hit its lower bound (0.80) in
  2005 and 2008 and its upper bound (0.98) in 2013. The estimate is fragile.

---

## 7. Final submission checklist

- [ ] Real deadline and presentation sign-up confirmed (the PDF header says Fall 2024, Oct 21).
- [ ] Report written by the team. Numbers copied from `results/final_two_models/` only, not from the older `results/*.csv`.
- [ ] Data source cited (BLS series ID, FRED link, download date).
- [ ] Completeness check reported (Task 2).
- [ ] History plot with labelled axes (figure 01).
- [ ] Correlogram shown **and interpreted** for trend, seasonality and cycles (figure 02).
- [ ] For **each** model: why chosen, fit, residual time plot, histogram, residual ACF, test forecast plot, accuracy measures.
- [ ] Error measures defined, with the sign convention and MASE scale stated.
- [ ] The mixed result explained; the half-year flip and the sensitivity years mentioned.
- [ ] Selection-informed test disclosed.
- [ ] Better model and rule stated.
- [ ] Task 5 forecast is the 12-month one, with the figure title, labelled axes, and 80% and 95% prediction intervals. The 144-month extra explained.
- [ ] Confidence discussion includes interval width, the negative long-run bound and the post-hoc check, framed as forecast error rather than a causal effect.
- [ ] Decisions and future data covered.
- [ ] R code commented, runs from the `revised-2014` folder, and every member can explain it. AI-use disclosure agreed.
- [ ] Each member's own 5-7 minute deck rehearsed and timed.
