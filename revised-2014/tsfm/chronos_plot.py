"""Plot the Chronos-2 projection from Dec 2014 against actual prices."""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

HERE = Path(__file__).resolve().parent
raw = pd.read_csv(HERE.parent / "data" / "APU0000708111.csv", parse_dates=["observation_date"])
raw.columns = ["date", "price"]
fc = pd.read_csv(HERE / "results" / "chronos_forecasts.csv", parse_dates=["date"])
f = fc[fc["stage"] == "Final"]
fig, ax = plt.subplots(figsize=(10, 5.5))
ax.fill_between(f["date"], f["lower95"], f["upper95"], color="#dbe7ff", label="95% interval")
ax.fill_between(f["date"], f["lower80"], f["upper80"], color="#93c5fd", label="80% interval")
ax.plot(raw[(raw["date"] >= "2005-01-01") & (raw["date"] <= "2014-12-01")]["date"],
        raw[(raw["date"] >= "2005-01-01") & (raw["date"] <= "2014-12-01")]["price"], color="#1e2a5a", label="History to Dec 2014")
ax.plot(f["date"], f["median"], color="#2563eb", lw=2, label="Chronos-2 median")
a = raw[raw["date"] > "2014-12-01"]
ax.plot(a["date"], a["price"], color="#b45309", lw=2, label="Actual (never in context)")
ax.axvline(pd.Timestamp("2014-12-01"), color="#64748b", ls="--")
ax.set(xlabel="Month", ylabel="U.S. dollars per dozen",
       title="Chronos-2 zero-shot projection from Jan 2015 vs actual (gap includes outbreaks and other changes)")
ax.legend(loc="upper left", frameon=False)
fig.tight_layout()
fig.savefig(HERE / "results" / "chronos_projection.png", dpi=140)
