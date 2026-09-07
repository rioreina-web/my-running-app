"""Faithful port of TrendsRecoveryFactors + TrendsRecoveryDemand (shipped 2026-08-10)."""
import json, math, datetime as dt
from collections import defaultdict

LOGS = json.load(open('/tmp/logs.json'))
BIO = {}
for chunk in open('/home/claude/bio.txt').read().strip().split(';'):
    d, rhr, slp = chunk.split(',')
    BIO[d] = (float(rhr) if rhr else None, int(slp) if slp else None)
CHECKINS = {"2026-08-07": "rough", "2026-08-12": "ok", "2026-08-17": "ok"}
MENTIONS = defaultdict(list)
for d, area in [("2026-05-24","knee"),("2026-05-24","knee"),("2026-07-17","knee"),
                ("2026-07-18","knee"),("2026-08-13","knee")]:
    MENTIONS[d].append(area)

QUALITY = {"tempo","threshold","interval","intervals","mile_repeats","mp_run","progression","race"}
LONG = {"long_run","long","long run","longrun"}

# ---- build one TrendsDay per calendar day
by_day = defaultdict(lambda: {"mi":0.0,"mn":0.0,"sl":0.0,"types":[],"moods":[],"rpe":[]})
for r in LOGS:
    if r["ex"]: continue
    b = by_day[r["d"]]
    b["mi"] += float(r["mi"] or 0); b["mn"] += float(r["mn"] or 0)
    b["sl"] += float(r["sl"] or 0)
    b["types"].append((r["wt"] or "").lower())
    if r["mood"]: b["moods"].append(r["mood"].lower())
    if r["fr"] is not None: b["rpe"].append((r["fr"], r["pr"]))

start = dt.date.fromisoformat(min(by_day)); end = dt.date.fromisoformat(max(by_day))
days = []
d = start
while d <= end:
    k = d.isoformat(); b = by_day.get(k)
    if b and b["mi"] > 0:
        ch = "long" if any(t in LONG for t in b["types"]) else ("key" if any(t in QUALITY for t in b["types"]) else "easy")
    else:
        ch = "rest"
    rhr, slp = BIO.get(k, (None, None))
    days.append(dict(date=k, miles=(b["mi"] if b else 0.0), dur=(b["mn"] if b else 0.0),
                     stress=(b["sl"] if b and b["mi"]>0 else None), type=ch,
                     mood=(b["moods"][0] if b and b["moods"] else None),
                     niggles=MENTIONS.get(k, []), sleepQuality=CHECKINS.get(k),
                     restingHr=rhr, sleepMin=slp,
                     rpe=(b["rpe"] if b else [])))
    d += dt.timedelta(days=1)

# ---- demand
ACUTE, CHRONIC, WARMUP, SPIKE_T, SPIKE_LB = 7.0, 42.0, 42, 2.0, 30
INT = {"rest":0.0,"easy":1.0,"long":1.1,"key":1.4}
def load_unit(ds):
    run = [x for x in ds if x["miles"] > 0]
    if not run: return "miles"
    if all(x["stress"] is not None for x in run): return "stress"
    if all(x["dur"] > 0 for x in run): return "dur"
    return "miles"
UNIT = load_unit(days)
def sload(x, unit=None):
    unit = unit or UNIT
    if unit == "stress": return x["stress"] or 0.0
    if unit == "dur": return x["dur"] * INT[x["type"]]
    return x["miles"] * INT[x["type"]]
def balance(ds, i):
    aa = 1 - math.exp(-1/ACUTE); ca = 1 - math.exp(-1/CHRONIC)
    n = min(len(ds), int(CHRONIC))
    seed = sum(sload(ds[j]) for j in range(n))/n if n else 0
    a = c = seed
    for j in range(i+1):
        L = sload(ds[j]); a += (L-a)*aa; c += (L-c)*ca
    if i+1 < WARMUP or c <= 0.0001: return a, c, None
    return a, c, 100*(a-c)/c
def spike_mult(ds, i):
    if ds[i]["miles"] <= 0: return None
    s = max(0, i-SPIKE_LB)
    if s >= i: return None
    pm = max((ds[j]["miles"] for j in range(s, i)), default=0)
    return ds[i]["miles"]/pm if pm > 0 else None

# ---- factors
MOOD_PTS = {"energized":4,"positive":2,"neutral":0,"tired":-8,"struggling":-14,"injured":-18}
MOOD_W = [1.0,0.9,0.75,0.6,0.5,0.4,0.3]
def rnd(x): return int(math.floor(x+0.5)) if x >= 0 else -int(math.floor(-x+0.5))
def F(name, pts, best=0, src="runs", ev=""): return dict(name=name, points=pts, best=best, src=src, ev=ev)

def f_mood(ds, i):
    w = list(reversed(ds[max(0,i-6):i+1]))
    tot = wu = 0.0; logged = []
    for o, day in enumerate(w):
        if o >= len(MOOD_W): break
        m = day["mood"]
        if not m or m not in MOOD_PTS: continue
        tot += MOOD_PTS[m]*MOOD_W[o]; wu += MOOD_W[o]; logged.append(m)
    if wu == 0: return F("Mood", 0, 4, "words", "nothing logged in 7 days")
    return F("Mood", rnd(tot/wu), 4, "words", f"{len(logged)} days in 7")

def f_body(ds, i):
    lb = [x for x in ds[max(0,i-13):i+1] if x["niggles"]]
    if not lb: return F("Body mentions", 0, 0, "words", "none in 14 days")
    c = defaultdict(int)
    for x in lb:
        for n in x["niggles"]: c[n] += 1
    n = max(c.values())
    return F("Body mentions", -6 if n >= 2 else -3, 0, "words", f"{n} in 14 d")

def f_need(ds, i):
    _,_,idx = balance(ds, i)
    if idx is None: return None
    for hi, p in [(-30,11),(-15,9),(-5,7),(10,5),(25,-2),(45,-6),(70,-9),(1e9,-12)]:
        if idx < hi: return F("Recovery need", p, 11, "runs", f"{idx:+.0f}%")
def f_spike(ds, i):
    m = spike_mult(ds, i)
    if m is None or m < SPIKE_T: return None
    return F("Big day", -5, 0, "runs", f"{m:.1f}x")

def f_clear(ds, i):
    since = 0; k = i
    while k >= 0 and ds[k]["miles"] > 0: since += 1; k -= 1
    found = k >= 0
    if not found and since < 14: return F("Clear days", 0, 0, "runs", "no clear day")
    if since <= 3: p = 5
    elif since <= 7: p = 2
    elif since <= 13: p = 0
    elif since <= 20: p = -3
    else: p = -5
    return F("Clear days", p, 5, "runs", f"{since} d since clear")

def med(xs):
    s = sorted(xs); n = len(s)
    return 0 if not s else ((s[n//2-1]+s[n//2])/2 if n % 2 == 0 else s[n//2])
def sd(xs):
    if len(xs) < 2: return 0
    m = sum(xs)/len(xs); return math.sqrt(sum((x-m)**2 for x in xs)/len(xs))

def f_sleep(ds, i):
    q = ds[i]["sleepQuality"]
    if q:
        return F("Sleep", {"good":4,"rough":-6}.get(q,0), 4, "words", f"{q} · logged")
    recent = ds[max(0,i-20):i+1]
    if not any(x["sleepQuality"] or x["sleepMin"] for x in recent): return None
    win = [x["sleepMin"] for x in ds[max(0,i-6):i+1] if x["sleepMin"]]
    base = [x["sleepMin"] for x in ds[max(0,i-20):max(0,i-6)] if x["sleepMin"]]
    if len(win) < 5 or len(base) < 7:
        return F("Sleep", 0, 2, "words", "not enough sleep data")
    delta = med(win) - med(base)
    thr = min(60, max(20, 0.5*sd([float(b) for b in base])))
    if delta <= -thr: return F("Sleep", -3, 2, "words", "under average")
    if delta >= thr: return F("Sleep", 2, 2, "words", "above average")
    return F("Sleep", 0, 2, "words", "in line")

def f_overnight(ds, i):
    win = ds[max(0,i-6):i+1]; base = ds[max(0,i-27):max(0,i-6)]
    rnow = [x["restingHr"] for x in win if x["restingHr"]]
    rbase = [x["restingHr"] for x in base if x["restingHr"]]
    if len(rnow) < 5 or len(rbase) < 14: return None
    s = sd(rbase)
    if s <= 0: dr = 0
    else:
        delta = sum(rnow)/len(rnow) - sum(rbase)/len(rbase)
        dr = 1 if delta >= 0.5*s else (-1 if delta <= -0.5*s else 0)
    # no HRV anywhere in this dataset → RHR-only branch
    return F("Overnight", {1:-3,-1:2,0:0}[dr], 2, "nights", f"rhr dir {dr}")

def ledger(ds, i):
    fs = [f_mood(ds,i), f_body(ds,i)]
    s = f_sleep(ds,i)
    if s: fs.append(s)
    need = f_need(ds,i)
    if need:
        fs.append(need); sp = f_spike(ds,i)
        if sp: fs.append(sp)
    else:
        # pre-warm-up fallback pair (recentLoad + loadVsBaseline) — port
        fs.append(f_recent(ds,i) or F("Recent load",0,6)); fs.append(f_lvb(ds,i))
    fs.append(f_clear(ds,i))
    o = f_overnight(ds,i)
    if o: fs.append(o)
    raw = 50 + sum(f["points"] for f in fs)
    return dict(total=max(8,min(96,raw)), raw=raw, factors=fs,
                ceiling=max(8,min(96,50+sum(f["best"] for f in fs))))

def f_recent(ds, i):
    if i == 0: return None
    W = [1.0,0.6,0.3]; carried = tw = 0.0; rm = []
    for o, w in enumerate(W):
        idx = i-1-o
        if idx < 0: break
        carried += ds[idx]["miles"]*w; tw += w; rm.append(ds[idx]["miles"])
    de = carried/tw if tw else 0
    if de <= 0: return F("Recent load", 6, 6)
    bd = ds[max(0,i-55):max(0,i-6)]
    bl = sum(x["miles"] for x in bd)/len(bd) if len(bd) >= 14 else 0
    if bl <= 0.5: return F("Recent load", -min(8, rnd(de*0.42)), 6)
    r = de/bl
    for hi, p in [(0.5,4),(0.85,2),(1.25,0),(1.6,-4),(2.0,-6),(1e9,-8)]:
        if r <= hi: return F("Recent load", p, 6)

def f_lvb(ds, i):
    l7 = sum(x["miles"] for x in ds[max(0,i-6):i+1])
    bd = ds[max(0,i-55):max(0,i-6)]; wk = len(bd)/7.0
    if wk < 2: return F("Load", 0, 5, "runs", "not enough history")
    b = sum(x["miles"] for x in bd)/wk
    if b <= 0: return F("Load", 0, 5, "runs", "no baseline")
    r = l7/b
    if r >= 1.25: return F("Load", -5, 5)
    if r >= 1.10: return F("Load", -2, 5)
    if r < 0.85: return F("Load", 3, 5)
    return F("Load", 5, 5)

def band(t):
    return "Clear" if t >= 75 else "Steady" if t >= 60 else "Worn" if t >= 45 else "Flat"

if __name__ == "__main__":
    print("unit:", UNIT, "days:", len(days), days[0]["date"], "→", days[-1]["date"])
    L = [ledger(days, i) for i in range(len(days))]
    json.dump([{ "date": days[i]["date"], **{k:v for k,v in L[i].items()} } for i in range(len(days))],
              open('/home/claude/scores.json','w'))
    print("today:", L[-1]["total"], band(L[-1]["total"]), "ceiling", L[-1]["ceiling"])
    for f in L[-1]["factors"]: print("   ", f["name"], f["points"], f["ev"])
