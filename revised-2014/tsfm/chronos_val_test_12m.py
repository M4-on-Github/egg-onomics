"""Chronos-2 zero-shot on the 12m validation (origin Dec 2012) and 12m test (origin Dec 2013), dollars.
Merges with the R tables from analysis/val_test_12m.R. Run from revised-2014/."""
import os
from pathlib import Path
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
import numpy as np, pandas as pd
from chronos import Chronos2Pipeline

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "results" / "val_test_12m"
raw = pd.read_csv(HERE.parent / "data" / "APU0000708111.csv", parse_dates=["observation_date"]).rename(
    columns={"observation_date": "timestamp", "APU0000708111": "price"})
pipe = Chronos2Pipeline.from_pretrained("amazon/chronos-2", device_map="cpu")
for stage, n, first in [("validation", 396, "2013-01-01"), ("test", 408, "2014-01-01")]:
    ctx = raw.iloc[:n][["timestamp", "price"]].assign(item_id="a")
    p = pipe.predict_df(ctx, id_column="item_id", timestamp_column="timestamp", target="price",
                        prediction_length=12, quantile_levels=[0.025, 0.1, 0.5, 0.9, 0.975], freq="MS")
    assert p["timestamp"].iloc[0] == pd.Timestamp(first) and len(p) == 12
    a = raw.iloc[n:n + 12]["price"].to_numpy(); e = a - p["0.5"].to_numpy()
    y = raw.iloc[:n]["price"].to_numpy(); scale = np.mean(np.abs(y[12:] - y[:-12]))
    row = {"model": "Chronos-2", "ME": e.mean(), "MAE": np.abs(e).mean(), "RMSE": np.sqrt((e ** 2).mean()),
           "MAPE": 100 * np.mean(np.abs(e / a)), "MASE": np.abs(e).mean() / scale,
           "Coverage80": np.mean((a >= p["0.1"]) & (a <= p["0.9"])),
           "Coverage95": np.mean((a >= p["0.025"]) & (a <= p["0.975"]))}
    r = pd.read_csv(OUT / f"r_{stage}_12m.csv")
    t = pd.concat([r, pd.DataFrame([row])]).sort_values("RMSE")
    t.insert(0, "rank", range(1, len(t) + 1))
    t.to_csv(OUT / f"{stage}_12m_all_models.csv", index=False)
    print(stage.upper()); print(t.round(4).to_string(index=False))
