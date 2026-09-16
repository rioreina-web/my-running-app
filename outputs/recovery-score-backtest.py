#!/usr/bin/env python3
"""
Recovery-score backtest over Rio's real training history (2026-01-17..2026-08-05).

Exact port of TrendsRecoveryFactors (the NEW arithmetic wired 2026-08-05) plus
the OLD shipped ledger arithmetic, computed for every day, then evaluated:
band occupancy, volatility vs the noise threshold, and non-circular predictive
checks (score-minus-mood vs next-day mood; score vs next-day behavior).

Approximations vs the app (documented in the report):
- dedup: same UTC day + same rounded distance (+-0.05 mi) keeps one row
  (mirrors the double-logged long runs, e.g. 07-18 13.49 x2, 08-01 17.01 x2).
- day mood: mood of the day's biggest-mileage log carrying one; ties -> the
  worse mood (app uses server "hardest session" ordering).
- niggles from body_mentions pulled directly (4 rows, 2 episodes).
"""
import json
from datetime import date, timedelta
from collections import defaultdict

MOOD_RANK = {"injured": 0, "struggling": 1, "tired": 2, "neutral": 3, "positive": 4, "energized": 5}

NEW_MOOD_PTS = {"energized": 12, "positive": 7, "neutral": 0, "tired": -8, "struggling": -14, "injured": -18}
OLD_MOOD_PTS = {"energized": 10, "positive": 6, "neutral": 0, "tired": -8, "struggling": -14, "injured": -18}
MOOD_WEIGHTS = [1.0, 0.9, 0.75, 0.6, 0.5, 0.4, 0.3]

MENTIONS = [("2026-05-24", "knee"), ("2026-05-24", "knee"), ("2026-07-17", "knee"), ("2026-07-18", "knee")]

def load_days(path):
    rows = []
    for line in open(path):
        line = line.rstrip("\n")
        if not line:
            continue
        d, mi, t, mood = line.split("|")
        rows.append((d, float(mi), t, mood))
    # dedup: same day + same mi (within 0.05) keeps first
    seen, dedup = set(), []
    for d, mi, t, mood in rows:
        key = (d, round(mi, 1))
        if mi > 0 and key in seen:
            continue
        if mi > 0:
            seen.add(key)
        dedup.append((d, mi, t, mood))
    by_day_miles = defaultdict(float)
    by_day_moods = defaultdict(list)  # (miles, mood)
    for d, mi, t, mood in dedup:
        if t not in ("cross_training", "strength", "rest"):
            by_day_miles[d] += mi
        if mood:
            by_day_moods[d].append((mi, mood))
    start, end = date(2026, 1, 17), date(2026, 8, 5)
    days = []
    cur = start
    men_by_day = defaultdict(list)
    for d, area in MENTIONS:
        men_by_day[d].append(area)
    while cur <= end:
        iso = cur.isoformat()
        moods = by_day_moods.get(iso, [])
        mood = None
        if moods:
            best = max(moods, key=lambda x: (x[0], -MOOD_RANK[x[1]]))
            mood = best[1]
        days.append({"date": iso, "miles": round(by_day_miles.get(iso, 0.0), 2),
                     "mood": mood, "niggles": men_by_day.get(iso, [])})
        cur += timedelta(days=1)
    return days

# ---------- NEW arithmetic (TrendsRecoveryFactors, wired today) ----------

def new_mood(days, i):
    start = max(0, i - 6)
    window = list(reversed(days[start:i + 1]))  # newest first
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
    # Swift Int(x.rounded()) rounds half away from zero
    mean = weighted / weight_used
    pts = int(mean + 0.5) if mean >= 0 else -int(-mean + 0.5)
    return pts, True

def recent_load(days, i, new):
    if i == 0:
        return None
    weights = [1.0, 0.6, 0.3]
    carried = tw = 0.0
    miles = []
    for off, w in enumerate(weights):
        idx = i - 1 - off
        if idx < 0:
            break
        carried += days[idx]["miles"] * w
        tw += w
        miles.append(days[idx]["miles"])
    de = carried / tw if tw > 0 else 0
    if de <= 0:
        return 6 if new else 5
    cap = 8 if new else 7
    return -min(cap, int(de * 0.42 + 0.5))

def body_mentions(days, i):
    lb = [d for d in days[max(0, i - 13):i + 1] if d["niggles"]]
    if not lb:
        return 0
    counts = defaultdict(int)
    for d in lb:
        for a in d["niggles"]:
            counts[a] += 1
    n = max(counts.values())
    return -6 if n >= 2 else -3

def load_vs_baseline(days, i, new):
    last7 = sum(d["miles"] for d in days[max(0, i - 6):i + 1])
    base_days = days[max(0, i - 55):max(0, i - 6)]
    weeks = len(base_days) / 7.0
    if weeks < 2:
        return 0, False
    base = sum(d["miles"] for d in base_days) / weeks
    if base <= 0:
        return 0, False
    r = last7 / base
    if r >= 1.25:
        return -5, True
    if r >= 1.10:
        return -2, True
    if r < 0.85:
        return (3 if new else 2), True
    return (5 if new else 4), True

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

def score(days, i, new=True, include_mood=True):
    factors = []
    had_mood = False
    if include_mood:
        if new:
            pts, had_mood = new_mood(days, i)
        else:
            m = days[i]["mood"]
            pts = OLD_MOOD_PTS.get(m, 0) if m else 0
            had_mood = bool(m)
        factors.append(pts)
    rl = recent_load(days, i, new)
    if rl is not None:
        factors.append(rl)
    factors.append(body_mentions(days, i))
    lb, _ = load_vs_baseline(days, i, new)
    factors.append(lb)
    factors.append(clear_days_new(days, i) if new else days_on_old(days, i))
    raw = 50 + sum(factors)
    return max(8, min(96, raw)), had_mood

def band(s):
    return "Flat" if s < 45 else "Worn" if s < 60 else "Steady" if s < 75 else "Clear"

def spearman(xs, ys):
    def rank(v):
        order = sorted(range(len(v)), key=lambda k: v[k])
        r = [0.0] * len(v)
        i = 0
        while i < len(order):
            j = i
            while j + 1 < len(order) and v[order[j + 1]] == v[order[i]]:
                j += 1
            avg = (i + j) / 2 + 1
            for k in range(i, j + 1):
                r[order[k]] = avg
            i = j + 1
        return r
    rx, ry = rank(xs), rank(ys)
    n = len(xs)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = (sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry)) ** 0.5
    return num / den if den else 0.0

def main():
    days = load_days("/home/claude/eval/logs.txt")
    n = len(days)
    out = {"n_days": n, "start": days[0]["date"], "end": days[-1]["date"]}

    new_scores, old_scores, nomood_scores = [], [], []
    mood_logged_flags = []
    for i in range(n):
        s_new, had = score(days, i, new=True)
        s_old, _ = score(days, i, new=False)
        s_nm, _ = score(days, i, new=True, include_mood=False)
        new_scores.append(s_new)
        old_scores.append(s_old)
        nomood_scores.append(s_nm)
        mood_logged_flags.append(had)

    WARM = 56  # 8-week baseline warm-up
    idx = list(range(WARM, n))

    def occupancy(scores):
        c = defaultdict(int)
        for i in idx:
            c[band(scores[i])] += 1
        t = len(idx)
        return {b: {"days": c[b], "pct": round(100 * c[b] / t, 1)} for b in ["Flat", "Worn", "Steady", "Clear"]}

    out["occupancy_new"] = occupancy(new_scores)
    out["occupancy_old"] = occupancy(old_scores)
    out["range_new"] = [min(new_scores[i] for i in idx), max(new_scores[i] for i in idx)]
    out["range_old"] = [min(old_scores[i] for i in idx), max(old_scores[i] for i in idx)]

    deltas_new = [abs(new_scores[i] - new_scores[i - 1]) for i in idx]
    deltas_old = [abs(old_scores[i] - old_scores[i - 1]) for i in idx]
    out["volatility"] = {
        "new_mean_abs_delta": round(sum(deltas_new) / len(deltas_new), 2),
        "old_mean_abs_delta": round(sum(deltas_old) / len(deltas_old), 2),
        "new_pct_ge3": round(100 * sum(1 for d in deltas_new if d >= 3) / len(deltas_new), 1),
        "old_pct_ge3": round(100 * sum(1 for d in deltas_old if d >= 3) / len(deltas_old), 1),
        "new_max_delta": max(deltas_new), "old_max_delta": max(deltas_old),
    }

    # mood coverage by month
    cov = defaultdict(lambda: [0, 0])
    for d in days:
        m = d["date"][:7]
        cov[m][1] += 1
        if d["mood"]:
            cov[m][0] += 1
    out["mood_coverage"] = {m: round(100 * a / b, 1) for m, (a, b) in sorted(cov.items())}
    out["mood_factor_active_pct"] = round(100 * sum(1 for i in idx if mood_logged_flags[i]) / len(idx), 1)

    # --- predictive checks (non-circular where possible) ---
    # 1. score-without-mood today vs tomorrow's logged mood being negative
    lows, highs = [], []
    pairs = []
    for i in idx[:-1]:
        tm = days[i + 1]["mood"]
        if not tm:
            continue
        neg = tm in ("tired", "struggling", "injured")
        pairs.append((nomood_scores[i], neg))
    if pairs:
        neg_scores = [s for s, ng in pairs if ng]
        pos_scores = [s for s, ng in pairs if not ng]
        out["nomood_vs_next_mood"] = {
            "n": len(pairs), "n_negative": len(neg_scores),
            "mean_score_before_negative_mood": round(sum(neg_scores) / len(neg_scores), 1) if neg_scores else None,
            "mean_score_before_ok_mood": round(sum(pos_scores) / len(pos_scores), 1) if pos_scores else None,
        }
    # 2. full score today vs tomorrow is a rest day
    rest_pairs = [(new_scores[i], days[i + 1]["miles"] == 0) for i in idx[:-1]]
    r_scores = [s for s, r in rest_pairs if r]
    run_scores = [s for s, r in rest_pairs if not r]
    out["score_vs_next_rest"] = {
        "mean_score_before_rest_day": round(sum(r_scores) / len(r_scores), 1),
        "mean_score_before_run_day": round(sum(run_scores) / len(run_scores), 1),
        "n_rest": len(r_scores), "n_run": len(run_scores),
    }
    # 3. score vs next-day miles (spearman)
    xs = [float(new_scores[i]) for i in idx[:-1]]
    ys = [days[i + 1]["miles"] for i in idx[:-1]]
    out["spearman_score_vs_next_miles"] = round(spearman(xs, ys), 3)

    # 4. knee episode (Jul 17): scores in the 5 days before vs the post-warmup mean
    ep = days.index(next(d for d in days if d["date"] == "2026-07-17"))
    out["knee_episode"] = {
        "scores_before_jul17": [new_scores[ep - k] for k in range(5, 0, -1)],
        "score_on_jul17": new_scores[ep],
        "post_warmup_mean": round(sum(new_scores[i] for i in idx) / len(idx), 1),
    }

    # old-vs-new divergence
    diff_band = sum(1 for i in idx if band(new_scores[i]) != band(old_scores[i]))
    out["old_vs_new"] = {
        "mean_new": round(sum(new_scores[i] for i in idx) / len(idx), 1),
        "mean_old": round(sum(old_scores[i] for i in idx) / len(idx), 1),
        "pct_days_band_differs": round(100 * diff_band / len(idx), 1),
    }

    series = {"dates": [d["date"] for d in days], "new": new_scores, "old": old_scores,
              "miles": [d["miles"] for d in days], "mood": [d["mood"] or "" for d in days]}
    json.dump({"summary": out, "series": series}, open("/home/claude/eval/results.json", "w"), indent=1)
    print(json.dumps(out, indent=1))

if __name__ == "__main__":
    main()
