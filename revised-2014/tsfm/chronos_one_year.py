"""Chronos-2, zero-shot, 12-month test: context Jan 1980-Dec 2013, forecast Jan-Dec 2014 (dollars).
Combines with the R table from analysis/one_year_test.R. Run from revised-2014/."""
import os
from pathlib import Path
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
import numpy as np, pandas as pd
from chronos import Chronos2Pipeline

HERE = Path(__file__).resolve().parent
raw = pd.read_csv(HERE.parent / "data" / "APU0000708111.csv", parse_dates=["observation_date"]).rename(
    columns={"observation_date": "timestamp", "APU0000708111": "price"})
ctx = raw.iloc[:408][["timestamp", "price"]].assign(item_id="a")
assert ctx["timestamp"].max() == pd.Timestamp("2013-12-01")
pipe = Chronos2Pipeline.from_pretrained("amazon/chronos-2", device_map="cpu")
p = pipe.predict_df(ctx, id_column="item_id", timestamp_column="timestamp", target="price",
                    prediction_length=12, quantile_levels=[0.025, 0.1, 0.5, 0.9, 0.975], freq="MS")
a = raw.iloc[408:420]["price"].to_numpy(); assert len(p) == 12
e = a - p["0.5"].to_numpy()
y = raw.iloc[:408]["price"].to_numpy(); scale = np.mean(np.abs(y[12:] - y[:-12]))
row = {"model": "Chronos-2", "ME": e.mean(), "MAE": np.abs(e).mean(), "RMSE": np.sqrt((e ** 2).mean()),
       "MAPE": 100 * np.mean(np.abs(e / a)), "MASE": np.abs(e).mean() / scale,
       "Coverage80": np.mean((a >= p["0.1"]) & (a <= p["0.9"])),
       "Coverage95": np.mean((a >= p["0.025"]) & (a <= p["0.975"]))}
r = pd.read_csv(HERE.parent / "results" / "one_year_test" / "r_models_one_year_test.csv")
out = pd.concat([r, pd.DataFrame([row])]).sort_values("RMSE")
out.insert(0, "rank", range(1, len(out) + 1))
out.to_csv(HERE.parent / "results" / "one_year_test" / "one_year_test_all_models.csv", index=False)
print(out.round(4).to_string(index=False))
