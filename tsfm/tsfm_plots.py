"""Exploratory plots for the Chronos-2 rolling-origin forecasts (tsfm_forecasts.csv).

Writes three PNGs to plots/ and prints a few summary numbers.
"""
from pathlib import Path

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent  # paths work from any working directory
PLOTS = HERE / "plots"
PLOTS.mkdir(exist_ok=True)

# Palette (reference instance, light mode): blue = forecast, orange = actual, gray = naive.
SURFACE, INK, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, ORANGE, GRAY = "#2a78d6", "#eb6834", "#8a8984"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": MUTED, "xtick.color": MUTED, "ytick.color": MUTED,
    "text.color": INK, "axes.titlecolor": INK, "axes.grid": True, "grid.color": GRID,
    "grid.linewidth": 0.8, "axes.spines.top": False, "axes.spines.right": False,
    "font.size": 10, "axes.titlesize": 11, "axes.titleweight": "bold", "axes.titlelocation": "left",
})

prices = pd.read_csv(HERE.parent / "data" / "APU0000708111.csv", parse_dates=["observation_date"]).rename(
    columns={"observation_date": "date", "APU0000708111": "price"}
).set_index("date")["price"]
fc = pd.read_csv(HERE / "tsfm_forecasts.csv", parse_dates=["origin", "target_date"])

# Naive benchmark: the last observed price at the origin, carried forward.
fc["naive"] = fc["origin"].map(prices)
fc["err"] = (fc["median"] - fc["actual"]).abs()
fc["naive_err"] = (fc["naive"] - fc["actual"]).abs()
scored = fc.dropna(subset=["actual"]).copy()
scored["in80"] = (scored["actual"] >= scored["q10"]) & (scored["actual"] <= scored["q90"])
scored["in95"] = (scored["actual"] >= scored["q025"]) & (scored["actual"] <= scored["q975"])

# 1. Forecast fans at four origins: before the 2015 spike, calm, before the 2022 spike, early 2025.
origins = ["2014-06-01", "2018-06-01", "2022-06-01", "2024-12-01"]
def draw_fan(ax, o):
    """Draw history, Chronos-2 median and intervals, and actuals for the origin month `o`."""
    o = pd.Timestamp(o)
    f = fc[fc["origin"] == o]
    hist = prices[(prices.index <= o) & (prices.index > o - pd.DateOffset(months=36))]
    act = prices[(prices.index >= o) & (prices.index <= f["target_date"].max())]
    ax.fill_between(f["target_date"], f["q025"], f["q975"], color=BLUE, alpha=0.15, lw=0, label="95% interval")
    ax.fill_between(f["target_date"], f["q10"], f["q90"], color=BLUE, alpha=0.30, lw=0, label="80% interval")
    ax.plot(hist.index, hist, color=GRAY, lw=2, label="History")
    ax.plot(f["target_date"], f["median"], color=BLUE, lw=2, ls="--", label="Chronos-2 median")
    ax.plot(act.index, act, color=ORANGE, lw=2, label="Actual")
    ax.axvline(o, color=GRID, lw=1)
    ax.set_title(f"Origin {o:%b %Y}")
    ax.set_ylabel("USD per dozen")
    ax.xaxis.set_major_locator(mdates.YearLocator())  # year-only ticks avoid label overlap
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))


fig, axes = plt.subplots(2, 2, figsize=(11, 7))
for ax, o in zip(axes.flat, origins):
    draw_fan(ax, o)
handles, labels = axes.flat[0].get_legend_handles_labels()
fig.legend(handles, labels, loc="lower center", ncol=5, frameon=False)
fig.suptitle("Chronos-2 forecast fans: 12 months ahead from four origins", x=0.06, ha="left", fontweight="bold")
fig.tight_layout(rect=(0, 0.05, 1, 0.97))
fig.savefig(PLOTS / "1_forecast_fans.png", dpi=150)

# 1b. One extra fan: origin Apr 2024, 12 months ahead (May 2024 - Apr 2025, all actuals known).
fig, ax = plt.subplots(figsize=(8, 4.6))
draw_fan(ax, "2024-04-01")
ax.legend(frameon=False, loc="upper left")
ax.set_title("Chronos-2 forecast from Apr 2024: May 2024 to Apr 2025")
fig.tight_layout()
fig.savefig(PLOTS / "1b_forecast_apr2024.png", dpi=150)

# 2. Mean absolute error by horizon: Chronos-2 vs naive.
by_h = scored.groupby("horizon")[["err", "naive_err"]].mean()
fig, ax = plt.subplots(figsize=(7, 4.2))
ax.plot(by_h.index, by_h["err"], color=BLUE, lw=2, marker="o", ms=6, label="Chronos-2 median")
ax.plot(by_h.index, by_h["naive_err"], color=GRAY, lw=2, marker="o", ms=6, label="Naive (last price)")
ax.set_xlabel("Forecast horizon (months)")
ax.set_ylabel("Mean absolute error (USD per dozen)")
ax.set_xticks(range(1, 13))
ax.set_ylim(bottom=0)
ax.set_title("Error grows with horizon (origins 2010-2025)")
ax.legend(frameon=False)
fig.tight_layout()
fig.savefig(PLOTS / "2_error_by_horizon.png", dpi=150)

# 3. Rolling interval coverage over origin date (24-origin window, all horizons pooled).
per_origin = scored.groupby("origin")[["in80", "in95"]].mean()
roll = per_origin.rolling(24, min_periods=12).mean()
fig, ax = plt.subplots(figsize=(9, 4.2))
ax.plot(roll.index, roll["in80"], color=BLUE, lw=2, label="80% interval")
ax.plot(roll.index, roll["in95"], color=ORANGE, lw=2, label="95% interval")
ax.axhline(0.80, color=BLUE, lw=1, ls=":")
ax.axhline(0.95, color=ORANGE, lw=1, ls=":")
ax.set_ylim(0, 1.02)
ax.set_xlabel("Forecast origin")
ax.set_ylabel("Share of actuals inside interval")
ax.set_title("Rolling coverage vs nominal level (dotted lines)")
ax.legend(frameon=False, loc="lower left")
fig.tight_layout()
fig.savefig(PLOTS / "3_rolling_coverage.png", dpi=150)

print("MAE by horizon (USD):")
print(by_h.loc[[1, 3, 6, 12]].round(3).to_string())
apr = scored[scored["origin"] == "2024-04-01"]
print(f"\nApr 2024 origin: MAE Chronos-2 {apr['err'].mean():.3f}, naive {apr['naive_err'].mean():.3f}; "
      f"inside 80% band {apr['in80'].mean():.0%}, 95% band {apr['in95'].mean():.0%}")
print(f"\nOverall coverage: 80% band {scored['in80'].mean():.1%}, 95% band {scored['in95'].mean():.1%}")
