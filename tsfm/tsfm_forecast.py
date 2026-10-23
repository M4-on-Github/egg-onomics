"""Rolling-origin zero-shot forecasts of egg prices with Chronos-2.

For every monthly origin (= last observed month) we forecast the next 12 months from
the history up to that origin and write a long-format CSV that R reads and scores
next to the ETS/ARIMA models.

Usage:  .venv\\Scripts\\python tsfm\\tsfm_forecast.py [--first-origin 2010-01] [--limit N]
"""
import argparse
import os
from importlib.metadata import version
from pathlib import Path

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

import numpy as np
import pandas as pd
from chronos import Chronos2Pipeline

HERE = Path(__file__).resolve().parent  # paths work from any working directory
DATA = HERE.parent / "data" / "APU0000708111.csv"
OUT = HERE / "tsfm_forecasts.csv"
MODEL = "amazon/chronos-2"
HORIZON = 12
QUANTILES = [0.025, 0.1, 0.5, 0.9, 0.975]

ap = argparse.ArgumentParser()
ap.add_argument("--first-origin", default="2010-01")
ap.add_argument("--limit", type=int, default=None, help="only run the first N origins (smoke test)")
args = ap.parse_args()

# Work in log price: quantiles map exactly through exp(), so exp(q_log) is the price quantile.
raw = pd.read_csv(DATA, parse_dates=["observation_date"]).rename(
    columns={"observation_date": "timestamp", "APU0000708111": "price"}
)
raw["log_price"] = np.log(raw["price"])

origins = raw.loc[raw["timestamp"] >= args.first_origin, "timestamp"].tolist()
if args.limit:
    origins = origins[: args.limit]

# One series per origin (truncated history), all forecast independently in one batched call.
context = pd.concat(
    [
        raw.loc[raw["timestamp"] <= o, ["timestamp", "log_price"]].assign(item_id=f"{o:%Y-%m}")
        for o in origins
    ],
    ignore_index=True,
)

pipe = Chronos2Pipeline.from_pretrained(MODEL, device_map="cpu")
pred = pipe.predict_df(
    context,
    id_column="item_id",
    timestamp_column="timestamp",
    target="log_price",
    prediction_length=HORIZON,
    quantile_levels=QUANTILES,
    freq="MS",
    cross_learning=False,  # keep origins independent (no information sharing)
)

qcols = [str(q) for q in QUANTILES]
out = pred[["item_id", "timestamp"] + qcols].rename(
    columns={"item_id": "origin", "timestamp": "target_date"}
)
out[qcols] = np.exp(out[qcols])
out = out.rename(columns={"0.025": "q025", "0.1": "q10", "0.5": "median", "0.9": "q90", "0.975": "q975"})
out["origin"] = pd.to_datetime(out["origin"] + "-01")
out["horizon"] = (out["target_date"].dt.year - out["origin"].dt.year) * 12 + (
    out["target_date"].dt.month - out["origin"].dt.month
)
assert out["horizon"].between(1, HORIZON).all()
out = out.merge(raw[["timestamp", "price"]].rename(columns={"timestamp": "target_date", "price": "actual"}),
                on="target_date", how="left")  # actual is NaN past the end of the data
out["model"] = "chronos-2"
out["chronos_version"] = version("chronos-forecasting")

cols = ["model", "chronos_version", "origin", "horizon", "target_date", "median", "q025", "q10", "q90", "q975", "actual"]
out[cols].to_csv(OUT, index=False)
print(f"wrote {len(out)} rows for {len(origins)} origins -> {OUT}")
