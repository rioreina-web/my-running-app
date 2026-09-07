#!/usr/bin/env python3
"""
Recovery-score recalibration harness (2026-08-06).

Compares three arithmetics over Rio's real 202-day history:
  CUR — TrendsRecoveryFactors as wired today (flat 0.42x recent-load charge)
  REL — recalibrated: Recent load relative to the athlete's own 8-wk daily average
  OLD — pre-retool shipped ledger (for reference)

#
# Data: regenerate logs.txt next to this script with one row per training log,
# "YYYY-MM-DD|miles|type|mood" (see the SQL in the 08-05 backtest report).
Evaluates band occupancy (whole period + the Jan-Mar "mood was flowing" slice),
percentiles, volatility, and the same non-circular predictive checks as the
2026-08-05 backtest.
"""
import json
from datetime import date, timedelta
from collections import defaultdict

MOOD_RANK = {"injured": 0, "struggling": 1, "tired": 2, "neutral": 3, "positive": 4, "energized": 5}
NEW_MOOD_PTS = {"energized": 12, "positive": 7, "neutral": 0, "tired": -8, "struggling": -14, "injured": -18}
OLD_MOOD_PTS = {"energized": 10, "positive": 6, "neutral": 0, "tired": -8, "struggling": -14, "injured": -18}
MOOD_WEIGHTS = [1.0, 0.9, 0.75, 0.6, 0.5, 0.4, 0.3]
MENTIONS = [("2026-05-24", "knee"), ("2026-05-24", "knee"), ("2026-07-17", "knee"), ("2026-07-18", "knee")]

def swift_round(x):
    return int(x + 0.5) if x >= 0 else -int(-x + 0.5)

def load_days(path):
    rows = []
    for line in open(path):
        line = line.rstrip("\n")
        if not line:
            continue
        d, mi, t, mood = line.split("|")
        rows.append((d, float(mi), t, mood))
    seen, dedup = set(), []
    for d, mi, t, mood in rows:
        key = (d, round(mi, 1))
        if mi > 0 and key in seen:
            continue
        if mi > 0:
            seen.add(key)
        dedup.append((d, mi, t, mood))
    by_day_miles = defaultdict(float)
    by_day_moods = defaultdict(list)
    for d, mi, t, mood in dedup:
        if t not in ("cross_training", "strength", "rest"):
            by_day_miles[d] += mi
        if mood:
            by_day_moods[d].append((mi, mood))
    start, end = date(2026, 1, 17), date(2026, 8, 6)
    men_by_day = defaultdict(list)
    for d, area in MENTIONS:
        men_by_day[d].append(area)
    days, cur = [], start
    while cur <= end:
        iso = cur.isoformat()
        moods = by_day_moods.get(iso, [])
        mood = None
        if moods:
            known = [m for m in moods if m[1] in MOOD_RANK]
            if known:
                best = max(known, key=lambda x: (x[0], -MOOD_RANK[x[1]]))
                mood = best[1]
        days.append({"date": iso, "miles": round(by_day_miles.get(iso, 0.0), 2),
                     "mood": mood, "niggles": men_by_day.get(iso, [])})
        cur += timedelta(days=1)
    return days

# ---------------- factors ----------------

def mood_new(days, i):
    window = list(reversed(days[max(0, i - 6):i + 1]))
    weighted = weight_used = 0.0
    logged = 0
    for off, day in enumerate(window):
        if off >= len(MOOD_WEIGHTS):
            break
        m = day["mood"]
        if not m or m not in NEW_MOOD_PTS:
            continue
        w = MOOD_WEIGHTS[off]
        weighted += NEW_MOOD_PTS[m] * w
        weight_used += w
        logged += 1
    if weight_used == 0:
        return 0, False
    return swift_round(weighted / weight_used), True

def recent_load_cur(days, i):
    """As wired today: flat 0.42 x 3-day decayed daily equivalent."""
    if i == 0:
        return None
    weights = [1.0, 0.6, 0.3]
    carried = tw = 0.0
    for off, w in enumerate(weights):
        idx = i - 1 - off
        if idx < 0:
            break
        carried += days[idx]["miles"] * w
        tw += w
    de = carried / tw if tw > 0 else 0
    if de <= 0:
        return 6
    return -min(8, swift_round(de * 0.42))

def recent_load_rel(days, i, cuts, pts):
    """Recalibrated: same 3-day decayed daily equivalent, but scored against
    the athlete's OWN 8-week average daily load (same window the Load factor
    uses). Falls back to the absolute rule when there's no baseline yet."""
    if i == 0:
        return None
    weights = [1.0, 0.6, 0.3]
    carried = tw = 0.0
    for off, w in enumerate(weights):
        idx = i - 1 - off
        if idx < 0:
            break
        carried += days[idx]["miles"] * w
        tw += w
    de = carried / tw if tw > 0 else 0
    if de <= 0:
        return 6
    base_days = days[max(0, i - 55):max(0, i - 6)]
    base_daily = (sum(d["miles"] for d in base_days) / len(base_days)) if len(base_days) >= 14 else 0
    if base_daily <= 0.5:
        return -min(8, swift_round(de * 0.42))  # fallback: absolute
    r = de / base_daily
    for cut, p in zip(cuts, pts):
        if r <= cut:
            return p
    return pts[-1]

def body_mentions(days, i):
    lb = [d for d in days[max(0, i - 13):i + 1] if d["niggles"]]
    if not lb:
        return 0
    counts = defaultdict(int)
    for d in lb:
        for a in d["niggles"]:
            counts[a] += 1
    return -6 if max(counts.values()) >= 2 else -3

def load_vs_baseline(days, i):
    last7 = sum(d["miles"] for d in days[max(0, i - 6):i + 1])
    base_days = days[max(0, i - 55):max(0, i - 6)]
    weeks = len(base_days) / 7.0
    if weeks < 2:
        return 0
    base = sum(d["miles"] for d in base_days) / weeks
    if base <= 0:
        return 0
    r = last7 / base
    if r >= 1.25:
        return -5
    if r >= 1.10:
        return -2
    if r < 0.85:
        return 3
    return 5

def clear_days_new(days, i):
    since, k = 0, i
    while k >= 0 and days[k]["miles"] > 0:
        since += 1
        k -= 1
    found = k >= 0
    if not found and since < 14:
        return 0
    if since <= 3:
        return 5
    if since <= 7:
        return 2
    if since <= 13:
        return 0
    if since <= 20:
        return -3
    return -5

def days_on_old(days, i):
    since, k = 0, i
    while k >= 0 and days[k]["miles"] > 0:
        since += 1
        k -= 1
    if since >= 8:
        return -5
    if since >= 6:
        return -3
    if since >= 4:
        return -1
    return 0

def recent_load_old(days, i):
    if i == 0:
        return None
    weights = [1.0, 0.6, 0.3]
    carried = tw = 0.0
    for off, w in enumerate(weights):
        idx = i - 1 - off
        if idx < 0:
            break
        carried += days[idx]["miles"] * w
        tw += w
    de = carried / tw if tw > 0 else 0
    if de <= 0:
        return 5
    return -min(7, swift_round(de * 0.42))

def load_vs_baseline_old(days, i):
    last7 = sum(d["miles"] for d in days[max(0, i - 6):i + 1])
    base_days = days[max(0, i - 55):max(0, i - 6)]
    weeks = len(base_days) / 7.0
    if weeks < 2:
        return 0
    base = sum(d["miles"] for d in base_days) / weeks
    if base <= 0:
        return 0
    r = last7 / base
    if r >= 1.25:
        return -5
    if r >= 1.10:
        return -2
    if r < 0.85:
        return 2
    return 4

def score(days, i, variant, cuts=None, pts=None, include_mood=True):
    fs = []
    if include_mood:
        if variant == "OLD":
            m = days[i]["mood"]
            fs.append(OLD_MOOD_PTS.get(m, 0) if m else 0)
        else:
            p, _ = mood_new(days, i)
            fs.append(p)
    if variant == "CUR":
        rl = recent_load_cur(days, i)
    elif variant == "REL":
        rl = recent_load_rel(days, i, cuts, pts)
    else:
        rl = recent_load_old(days, i)
    if rl is not None:
        fs.append(rl)
    fs.append(body_mentions(days, i))
    fs.append(load_vs_baseline(days, i) if variant != "OLD" else load_vs_baseline_old(days, i))
    fs.append(clear_days_new(days, i) if variant != "OLD" else days_on_old(days, i))
    return max(8, min(96, 50 + sum(fs)))

def band(s):
    return "Flat" if s < 45 else "Worn" if s < 60 else "Steady" if s < 75 else "Clear"

def pct(xs, p):
    xs = sorted(xs)
    k = (len(xs) - 1) * p
    f = int(k)
    return xs[f] + (xs[min(f + 1, len(xs) - 1)] - xs[f]) * (k - f)

def occupancy(scores, idx):
    c = defaultdict(int)
    for i in idx:
        c[band(scores[i])] += 1
    t = len(idx)
    return {b: f"{c[b]} ({100*c[b]/t:.1f}%)" for b in ["Flat", "Worn", "Steady", "Clear"]}

def evaluate(days, cuts, pts, label, verbose=True):
    n = len(days)
    rel = [score(days, i, "REL", cuts, pts) for i in range(n)]
    idx56 = list(range(56, n))
    # inputs-on slice: Jan 31 (day 14, baseline fallback ends quickly) .. Mar 15 (mood coverage >=45%)
    janmar = [i for i in range(14, n) if days[i]["date"] <= "2026-03-15"]
    out = {
        "label": label,
        "occ_all": occupancy(rel, idx56),
        "occ_inputs_on": occupancy(rel, janmar),
        "mean": round(sum(rel[i] for i in idx56) / len(idx56), 1),
        "p25_p50_p75_p90": [round(pct([rel[i] for i in idx56], p), 1) for p in (0.25, 0.5, 0.75, 0.9)],
        "range": [min(rel[i] for i in idx56), max(rel[i] for i in idx56)],
        "vol": round(sum(abs(rel[i] - rel[i-1]) for i in idx56) / len(idx56), 2),
    }
    if verbose:
        print(json.dumps(out, indent=1))
    return rel, out

def main():
    days = load_days("logs.txt")
    n = len(days)
    idx56 = list(range(56, n))
    janmar = [i for i in range(14, n) if days[i]["date"] <= "2026-03-15"]

    cur = [score(days, i, "CUR") for i in range(n)]
    old = [score(days, i, "OLD") for i in range(n)]
    print("=== CUR (as wired today) ===")
    print(json.dumps({"occ_all": occupancy(cur, idx56), "occ_inputs_on": occupancy(cur, janmar),
                      "mean": round(sum(cur[i] for i in idx56)/len(idx56), 1),
                      "p25_p50_p75_p90": [round(pct([cur[i] for i in idx56], p), 1) for p in (0.25, 0.5, 0.75, 0.9)],
                      "vol": round(sum(abs(cur[i]-cur[i-1]) for i in idx56)/len(idx56), 2)}, indent=1))
    print("=== OLD (pre-retool) ===")
    print(json.dumps({"occ_all": occupancy(old, idx56)}, indent=1))

    # candidate REL tunings: (cuts, pts) — ratio thresholds and their points
    candidates = [
        ("A gentle",   [0.5, 0.8, 1.2, 1.5, 1.9], [4, 2, 0, -3, -6, -8]),
        ("B moderate", [0.5, 0.85, 1.25, 1.6, 2.0], [4, 2, 0, -4, -6, -8]),
        ("C credit-normal", [0.5, 0.8, 1.15, 1.5, 1.9], [5, 3, 1, -3, -6, -8]),
    ]
    results = {}
    for label, cuts, pts in candidates:
        print(f"=== REL {label} ===")
        rel, out = evaluate(days, cuts, pts, label)
        results[label] = rel

    # ratio distribution for context
    ratios = []
    for i in range(20, n):
        weights = [1.0, 0.6, 0.3]
        carried = tw = 0.0
        for off, w in enumerate(weights):
            idx_ = i - 1 - off
            if idx_ < 0:
                break
            carried += days[idx_]["miles"] * w
            tw += w
        de = carried / tw
        base_days = days[max(0, i - 55):max(0, i - 6)]
        bd = sum(d["miles"] for d in base_days) / len(base_days)
        if bd > 0.5:
            ratios.append(de / bd)
    print("ratio p10/p25/p50/p75/p90:", [round(pct(ratios, p), 2) for p in (0.1, 0.25, 0.5, 0.75, 0.9)])

if __name__ == "__main__":
    main()
