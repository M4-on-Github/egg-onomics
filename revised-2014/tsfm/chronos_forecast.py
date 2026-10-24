"""Zero-shot Chronos-2 on the revised-2014 design (no fine-tuning, no tuning).

Same origins and windows as the R study, on original dollar prices, history cut at each origin:
  Validation  origin Dec 2013, h = 6   (Jan-Jun 2014)
  Test        origin Jun 2014, h = 6   (Jul-Dec 2014)
  Final       origin Dec 2014, h = 124 (Jan 2015-Apr 2025; h = 6 and 12 are its first months)
Post-2014 actuals appear only in the gap table, never in a context window.

Usage (from revised-2014/):  ..\\.venv\\Scripts\\python tsfm\\chronos_forecast.py
"""
import os
from importlib.metadata import version
from pathlib import Path

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

import numpy as np
import pandas as pd
from chronos import Chronos2Pipeline

HERE = Path(__file__).resolve().parent
DATA = HERE.parent / "data" / "APU0000708111.csv"
OUT = HERE / "results"
OUT.mkdir(exist_ok=True)
QUANTILES = [0.025, 0.1, 0.5, 0.9, 0.975]
STAGES = {  # stage: (origin, horizon)
    "Validation": ("2013-12-01", 6),
    "Test": ("2014-06-01", 6),
    "Final": ("2014-12-01", 124),
}

raw = pd.read_csv(DATA, parse_dates=["observation_date"]).rename(
    columns={"observation_date": "timestamp", "APU0000708111": "price"})
assert len(raw) == 544

pipe = Chronos2Pipeline.from_pretrained("amazon/chronos-2", device_map="cpu")
rows = []
for stage, (origin, h) in STAGES.items():
    ctx = raw.loc[raw["timestamp"] <= origin, ["timestamp", "price"]].assign(item_id=stage)
    assert ctx["timestamp"].max() == pd.Timestamp(origin)
    pred = pipe.predict_df(ctx, id_column="item_id", timestamp_column="timestamp", target="price",
                           prediction_length=h, quantile_levels=QUANTILES, freq="MS")
    q = [str(x) for x in QUANTILES]
    p = pred[["timestamp"] + q].copy()
    p[q] = p[q].clip(lower=0.0)  # dollar quantiles can dip below zero; prices cannot
    p.columns = ["date", "lower95", "lower80", "median", "upper80", "upper95"]
    p.insert(0, "stage", stage)
    p["horizon"] = np.arange(1, h + 1)
    rows.append(p)
fc = pd.concat(rows, ignore_index=True)
fc = fc.merge(raw[["timestamp", "price"]].rename(columns={"timestamp": "date", "price": "actual"}), on="date")
fc["error"] = fc["actual"] - fc["median"]
fc["pct_error"] = 100 * fc["error"] / fc["actual"]
fc["in80"] = (fc["actual"] >= fc["lower80"]) & (fc["actual"] <= fc["upper80"])
fc["in95"] = (fc["actual"] >= fc["lower95"]) & (fc["actual"] <= fc["upper95"])
fc["chronos_version"] = version("chronos-forecasting")
fc.to_csv(OUT / "chronos_forecasts.csv", index=False)


def score(z, k=None):
    z = z if k is None else z[z["horizon"] <= k]
    # MASE scaled like the R study: in-sample seasonal-naive MAE on the data before the origin.
    return pd.Series({"months": len(z), "ME": z["error"].mean(), "MAE": z["error"].abs().mean(),
                      "RMSE": np.sqrt((z["error"] ** 2).mean()), "MAPE": z["pct_error"].abs().mean(),
                      "Coverage80": z["in80"].mean(), "Coverage95": z["in95"].mean()})


acc = []
for stage in ["Validation", "Test"]:
    origin = STAGES[stage][0]
    y = raw.loc[raw["timestamp"] <= origin, "price"].to_numpy()
    scale = np.mean(np.abs(y[12:] - y[:-12]))
    s = score(fc[fc["stage"] == stage])
    s["MASE"] = s["MAE"] / scale
    acc.append(s.rename(stage))
pd.DataFrame(acc).to_csv(OUT / "chronos_accuracy_validation_test.csv")

fin = fc[fc["stage"] == "Final"]
gap = pd.DataFrame({w: score(fin, k) for w, k in
                    [("6 months", 6), ("12 months", 12), ("Full 2015-2025", None)]}).T
gap.to_csv(OUT / "chronos_gap_summary.csv")
print(pd.DataFrame(acc).round(4).to_string())
print(gap.round(4).to_string())
print(fin[fin["horizon"].isin([6, 12, 124])][["date", "median", "lower95", "upper95", "actual"]].round(2).to_string())
