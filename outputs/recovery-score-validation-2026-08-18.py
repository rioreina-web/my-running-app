"""
Recovery-score validation harness — 2026-08-18.

The Stage-3 check that the 9-of-10 plan called for and that had never been run:
does the shipped recovery ledger predict anything?

Run:  python3 recovery-score-validation-2026-08-18.py
Needs: recovery_ledger_port.py (a line-by-line port of TrendsRecoveryFactors +
TrendsRecoveryDemand as shipped 2026-08-10), /tmp/logs.json and bio.txt
(pulled from Supabase — see the SQL at the foot of this file).
"""
import json, math, statistics as st
from collections import Counter, defaultdict
from recovery_ledger_port import days, ledger, band, sload, balance, F

def pear(a,b):
    n=len(a); ma,mb=st.mean(a),st.mean(b); sa,sb=st.pstdev(a),st.pstdev(b)
    return float("nan") if sa==0 or sb==0 else sum((x-ma)*(y-mb) for x,y in zip(a,b))/(n*sa*sb)
def ci95(r,n):
    if n<4 or abs(r)>=1: return (float("nan"),)*2
    z=0.5*math.log((1+r)/(1-r)); se=1/math.sqrt(n-3)
    f=lambda z:(math.exp(2*z)-1)/(math.exp(2*z)+1)
    return f(z-1.96*se), f(z+1.96*se)

# ─────────── analyze.py ───────────
from collections import Counter, defaultdict

L = [ledger(days, i) for i in range(len(days))]
tot = [x["total"] for x in L]
N = len(days)
print(f"== {N} days, {days[0]['date']} → {days[-1]['date']}  (unit=stress_load)\n")

# 1 band distribution
c = Counter(band(t) for t in tot)
print("BAND DISTRIBUTION")
for b in ["Flat","Worn","Steady","Clear"]:
    print(f"  {b:7} {c[b]:4}  {100*c[b]/N:5.1f}%")
print(f"  score: mean {st.mean(tot):.1f}  sd {st.pstdev(tot):.1f}  min {min(tot)}  max {max(tot)}")
print(f"  p10 {sorted(tot)[N//10]}  median {st.median(tot)}  p90 {sorted(tot)[9*N//10]}")

# 2 ceiling
ceil_lt75 = sum(1 for x in L if x["ceiling"] < 75)
print(f"\nCEILING: days where Clear is arithmetically unreachable: {ceil_lt75}/{N} = {100*ceil_lt75/N:.0f}%")
print("  ceiling values:", Counter(x["ceiling"] for x in L).most_common())

# 3 factor contribution: sd of each factor's points, and share of |points|
names = ["Mood","Body mentions","Sleep","Recovery need","Big day","Clear days","Overnight","Recent load","Load"]
print("\nFACTOR BEHAVIOUR (over all days present)")
print(f"  {'factor':15} {'days':>5} {'mean':>7} {'sd':>6} {'min':>5} {'max':>5} {'r w/ total':>11}")
series = {}
for nm in names:
    v = []; idx = []
    for i, x in enumerate(L):
        p = next((f["points"] for f in x["factors"] if f["name"] == nm), None)
        if p is not None: v.append(p); idx.append(i)
    if not v: continue
    series[nm] = (idx, v)
    sub = [tot[i] for i in idx]
    if len(v) > 2 and st.pstdev(v) > 0:
        mv, ms = st.mean(v), st.mean(sub)
        r = sum((a-mv)*(b-ms) for a,b in zip(v,sub))/ (len(v)*st.pstdev(v)*st.pstdev(sub))
    else: r = float('nan')
    print(f"  {nm:15} {len(v):5} {st.mean(v):7.2f} {st.pstdev(v):6.2f} {min(v):5} {max(v):5} {r:11.2f}")

# 4 day-to-day movement
d = [abs(tot[i]-tot[i-1]) for i in range(1,N)]
print(f"\nDAY-TO-DAY |change|: mean {st.mean(d):.1f}  median {st.median(d)}  "
      f">=3pt (above noise floor) on {100*sum(1 for x in d if x>=3)/len(d):.0f}% of days")
# lag-1 autocorrelation
m = st.mean(tot); v = sum((t-m)**2 for t in tot)
ac = sum((tot[i]-m)*(tot[i-1]-m) for i in range(1,N))/v
print(f"lag-1 autocorrelation: {ac:.2f}")

# 5 mood logging coverage
logged = sum(1 for x in days if x["mood"])
run_days = sum(1 for x in days if x["miles"]>0)
print(f"\nINPUT COVERAGE over {N} days:")
print(f"  mood logged        {logged:4} days ({100*logged/N:.0f}%)   of {run_days} run days: {100*logged/run_days:.0f}%")
print(f"  sleep rating       {sum(1 for x in days if x['sleepQuality']):4} days ({100*sum(1 for x in days if x['sleepQuality'])/N:.0f}%)")
print(f"  watch sleep mins   {sum(1 for x in days if x['sleepMin']):4} days ({100*sum(1 for x in days if x['sleepMin'])/N:.0f}%)")
print(f"  resting HR         {sum(1 for x in days if x['restingHr']):4} days")
print(f"  HRV                   0 days (0%)")
print(f"  felt RPE           {sum(1 for x in days if x['rpe']):4} days")

json.dump({"tot":tot,"dates":[x['date'] for x in days]}, open('/home/claude/tot.json','w'))


# ─────────── predict.py ───────────
from collections import Counter, defaultdict

L = [ledger(days,i) for i in range(len(days))]
tot = [x["total"] for x in L]
N = len(days)

def pear(a,b):
    n=len(a); ma,mb=st.mean(a),st.mean(b)
    sa,sb=st.pstdev(a),st.pstdev(b)
    if sa==0 or sb==0: return float('nan')
    return sum((x-ma)*(y-mb) for x,y in zip(a,b))/(n*sa*sb)
def ci95(r,n):
    if n<4 or abs(r)>=1: return (float('nan'),)*2
    z=0.5*math.log((1+r)/(1-r)); se=1/math.sqrt(n-3)
    lo,hi=z-1.96*se,z+1.96*se
    f=lambda z:(math.exp(2*z)-1)/(math.exp(2*z)+1)
    return f(lo),f(hi)

# ---------- prospective: YESTERDAY's score vs TODAY's felt RPE
X=[];Y=[];PL=[];LOADT=[];MOODY=[]
for i in range(1,N):
    if not days[i]["rpe"]: continue
    fr = st.mean([r[0] for r in days[i]["rpe"]])
    X.append(tot[i-1]); Y.append(fr)
    pr=[r[1] for r in days[i]["rpe"] if r[1] is not None]
    PL.append(st.mean(pr) if pr else None)
    LOADT.append(sload(days[i]))
    MOODY.append(next(f["points"] for f in L[i-1]["factors"] if f["name"]=="Mood"))
n=len(X)
r=pear(X,Y); lo,hi=ci95(r,n)
print(f"PROSPECTIVE TEST — yesterday's recovery score vs today's felt RPE   (n={n} run days with RPE)")
print(f"  r = {r:+.3f}   95% CI [{lo:+.2f}, {hi:+.2f}]   r^2 = {r*r:.3f}")
rl=pear(LOADT,Y); lo2,hi2=ci95(rl,n)
print(f"  baseline — TODAY'S OWN training load vs today's felt RPE: r = {rl:+.3f} [{lo2:+.2f},{hi2:+.2f}]")
rm=pear(MOODY,Y); lo3,hi3=ci95(rm,n)
print(f"  the mood factor alone (yesterday): r = {rm:+.3f} [{lo3:+.2f},{hi3:+.2f}]")
pp=[(p,y) for p,y in zip(PL,Y) if p is not None]
print(f"  planned RPE available on {len(pp)}/{n} of those days"
      + (f"; r(planned, felt) = {pear([a for a,_ in pp],[b for _,b in pp]):+.3f}" if len(pp)>3 else ""))

# by band
g=defaultdict(list)
for x,y in zip(X,Y): g[band(x)].append(y)
print("\n  mean felt RPE the day after each band:")
for b in ["Flat","Worn","Steady","Clear"]:
    if g[b]: print(f"    {b:7} n={len(g[b]):3}  RPE {st.mean(g[b]):.2f}  (sd {st.pstdev(g[b]):.2f})")
    else: print(f"    {b:7} n=  0  —")

# ---------- behavioural: does a low score precede a rest day?
A=[];B=[]
for i in range(1,N):
    A.append(tot[i-1]); B.append(1 if days[i]["miles"]==0 else 0)
rest=[a for a,b in zip(A,B) if b]; run=[a for a,b in zip(A,B) if not b]
print(f"\nBEHAVIOURAL — yesterday's score before a REST day {st.mean(rest):.1f} (n={len(rest)}) "
      f"vs before a RUN day {st.mean(run):.1f} (n={len(run)})")
sp=math.sqrt((st.pvariance(rest)*len(rest)+st.pvariance(run)*len(run))/(len(rest)+len(run)))
print(f"  difference {st.mean(rest)-st.mean(run):+.1f} pts, Cohen's d = {(st.mean(rest)-st.mean(run))/sp:+.2f}")

# ---------- the injury episode
print("\nTHE ONE INJURY EPISODE (knee, 2026-07-17) — score on the 14 days before:")
idx={d['date']:i for i,d in enumerate(days)}
i0=idx['2026-07-17']
row=[f"{days[j]['date'][5:]}:{tot[j]}" for j in range(i0-13,i0+1)]
print("  "+" ".join(row))
print(f"  percentile of those 14 scores within the whole history: "
      f"{100*sum(1 for t in tot if t < st.mean(tot[i0-13:i0+1]))/N:.0f}th")

# ---------- how much is mood-log ARRIVAL vs physiology
moved=[]; 
for i in range(1,N):
    had = days[i]["mood"] is not None
    moved.append((abs(tot[i]-tot[i-1]), had))
withlog=[m for m,h in moved if h]; without=[m for m,h in moved if not h]
print(f"\nNOISE SOURCE — |daily change| on days a mood WAS logged: {st.mean(withlog):.1f} (n={len(withlog)}) "
      f"vs not logged: {st.mean(without):.1f} (n={len(without)})")


# ─────────── predict2.py ───────────
from collections import defaultdict
L=[ledger(days,i) for i in range(len(days))]; tot=[x["total"] for x in L]; N=len(days)
def pear(a,b):
    n=len(a); ma,mb=st.mean(a),st.mean(b); sa,sb=st.pstdev(a),st.pstdev(b)
    return float('nan') if sa==0 or sb==0 else sum((x-ma)*(y-mb) for x,y in zip(a,b))/(n*sa*sb)

# fair test A: within EASY runs only (removes workout-type confound)
for label, keep in [("all runs", lambda d: True), ("easy/recovery only", lambda d: d["type"]=="easy"),
                    ("key sessions only", lambda d: d["type"]=="key")]:
    X=[];Y=[]
    for i in range(1,N):
        if days[i]["rpe"] and keep(days[i]):
            X.append(tot[i-1]); Y.append(st.mean([r[0] for r in days[i]["rpe"]]))
    if len(X)>5: print(f"  score(d-1) vs felt RPE — {label:22} n={len(X):3}  r={pear(X,Y):+.3f}")

# fair test B: the CHANGE in score rather than the level
print()
for lag,name in [(1,"1-day change"),(3,"3-day change"),(7,"7-day change")]:
    X=[];Y=[]
    for i in range(lag+1,N):
        if days[i]["rpe"]:
            X.append(tot[i-1]-tot[i-1-lag]); Y.append(st.mean([r[0] for r in days[i]["rpe"]]))
    print(f"  {name:14} vs next felt RPE  n={len(X):3}  r={pear(X,Y):+.3f}")

# fair test C: score vs SAME-DAY felt RPE (circular, but the strongest case for it)
X=[];Y=[]
for i in range(N):
    if days[i]["rpe"]: X.append(tot[i]); Y.append(st.mean([r[0] for r in days[i]["rpe"]]))
print(f"\n  same-day score vs felt RPE (CIRCULAR — shares the mood log): n={len(X)} r={pear(X,Y):+.3f}")

# what the score is actually made of: variance explained by mood alone
mo=[next(f["points"] for f in L[i]["factors"] if f["name"]=="Mood") for i in range(N)]
print(f"\n  r(score, mood factor)            = {pear(tot,mo):+.3f}   → mood explains {100*pear(tot,mo)**2:.0f}% of score variance")
nd=[(i,next((f["points"] for f in L[i]["factors"] if f["name"]=="Recovery need"),None)) for i in range(N)]
nd=[(i,p) for i,p in nd if p is not None]
print(f"  r(score, recovery-need factor)   = {pear([tot[i] for i,_ in nd],[p for _,p in nd]):+.3f}")
cd=[next(f["points"] for f in L[i]["factors"] if f["name"]=="Clear days") for i in range(N)]
print(f"  r(score, clear-days factor)      = {pear(tot,cd):+.3f}")
# overlap between the two load-ish factors
print(f"  r(recovery need, clear days)     = {pear([p for _,p in nd],[cd[i] for i,_ in nd]):+.3f}")

# biggest single-day drops and what followed
dd=sorted(((tot[i]-tot[i-1],i) for i in range(1,N)))[:6]
print("\n  six biggest 1-day drops:")
for delta,i in dd:
    nxt=[st.mean([r[0] for r in days[j]["rpe"]]) for j in range(i,min(N,i+4)) if days[j]["rpe"]]
    print(f"    {days[i]['date']}  {delta:+d} pts (to {tot[i]})   felt-RPE next 3 d: "
          + (", ".join(f"{v:.0f}" for v in nxt) if nxt else "none logged"))


# ─────────── predict3.py ───────────
L=[ledger(days,i) for i in range(len(days))]; tot=[x["total"] for x in L]; N=len(days)

def rpe_next(i,k=3):
    v=[st.mean([r[0] for r in days[j]["rpe"]]) for j in range(i+1,min(N,i+1+k)) if days[j]["rpe"]]
    return v
allrpe=[st.mean([r[0] for r in d["rpe"]]) for d in days if d["rpe"]]
base=st.mean(allrpe)
print(f"baseline felt RPE across all {len(allrpe)} logged runs: {base:.2f} (sd {st.pstdev(allrpe):.2f})\n")

def report(name, flags):
    hit=[]; miss=[]
    for i in range(1,N-1):
        v=rpe_next(i)
        if not v: continue
        (hit if flags(i) else miss).append(st.mean(v))
    if len(hit)<3: print(f"  {name:42} n={len(hit)} too few"); return
    sp=math.sqrt((st.pvariance(hit)*len(hit)+st.pvariance(miss)*len(miss))/(len(hit)+len(miss)))
    d=(st.mean(hit)-st.mean(miss))/sp if sp else 0
    print(f"  {name:42} n={len(hit):3}  RPE next 3d {st.mean(hit):.2f} vs {st.mean(miss):.2f}  d={d:+.2f}")

print("PREDICTOR COMPARISON — mean felt RPE over the next 3 days")
report("score drops >=10 pts in a day", lambda i: tot[i]-tot[i-1] <= -10)
report("score is Flat (<45)",            lambda i: tot[i] < 45)
report("score in its own bottom quartile", lambda i: tot[i] <= sorted(tot)[N//4])
report("RAW mood log = tired/struggling/injured", lambda i: (days[i]["mood"] or "") in ("tired","struggling","injured"))
report("RAW mood log today, any negative in last 3d",
       lambda i: any((days[j]["mood"] or "") in ("tired","struggling","injured") for j in range(max(0,i-2),i+1)))
report("a body mention in the last 3 days", lambda i: any(days[j]["niggles"] for j in range(max(0,i-2),i+1)))


# ─────────── gt.py ───────────
import statistics as st
from collections import defaultdict
g=defaultdict(list)
for d in days:
    if d["rpe"]: g[d["type"]].append(st.mean([r[0] for r in d["rpe"]]))
print("IS felt_rpe ITSELF A USABLE GROUND TRUTH?  mean felt RPE by session type")
for k in ["easy","long","key"]:
    if g[k]: print(f"  {k:6} n={len(g[k]):3}  RPE {st.mean(g[k]):.2f}  sd {st.pstdev(g[k]):.2f}")
allv=[v for k in g for v in g[k]]
import math
def pear(a,b):
    n=len(a); ma,mb=st.mean(a),st.mean(b); sa,sb=st.pstdev(a),st.pstdev(b)
    return float('nan') if sa==0 or sb==0 else sum((x-ma)*(y-mb) for x,y in zip(a,b))/(n*sa*sb)
X=[sload(d) for d in days if d["rpe"]]; Y=[st.mean([r[0] for r in d["rpe"]]) for d in days if d["rpe"]]
print(f"  r(session stress_load, felt RPE) = {pear(X,Y):+.3f}   n={len(X)}")
M=[d["miles"] for d in days if d["rpe"]]
print(f"  r(miles, felt RPE)               = {pear(M,Y):+.3f}")
print(f"  felt RPE values seen: {sorted(set(int(v) for v in Y))}")


# ─────────── residual.py ───────────
from collections import defaultdict
L=[ledger(days,i) for i in range(len(days))]; tot=[x["total"] for x in L]; N=len(days)
def pear(a,b):
    n=len(a); ma,mb=st.mean(a),st.mean(b); sa,sb=st.pstdev(a),st.pstdev(b)
    return float('nan') if sa==0 or sb==0 else sum((x-ma)*(y-mb) for x,y in zip(a,b))/(n*sa*sb)
def ci(r,n):
    z=0.5*math.log((1+r)/(1-r)); se=1/math.sqrt(n-3)
    f=lambda z:(math.exp(2*z)-1)/(math.exp(2*z)+1); return f(z-1.96*se), f(z+1.96*se)

typ=defaultdict(list)
for d in days:
    if d["rpe"]: typ[d["type"]].append(st.mean([r[0] for r in d["rpe"]]))
mu={k:st.mean(v) for k,v in typ.items()}

X=[];Y=[];MO=[]
for i in range(1,N):
    if not days[i]["rpe"]: continue
    f=st.mean([r[0] for r in days[i]["rpe"]])
    X.append(tot[i-1]); Y.append(f-mu[days[i]["type"]])
    MO.append(next(fa["points"] for fa in L[i-1]["factors"] if fa["name"]=="Mood"))
r=pear(X,Y); lo,hi=ci(r,len(X))
print("THE FAIR TEST — 'did this run feel harder than this kind of run usually does?'")
print(f"  residual felt RPE (type-adjusted), n={len(X)}")
print(f"  vs yesterday's recovery score : r = {r:+.3f}  95% CI [{lo:+.2f},{hi:+.2f}]   (expected sign: negative)")
rm=pear(MO,Y); lo2,hi2=ci(rm,len(MO))
print(f"  vs yesterday's mood factor    : r = {rm:+.3f}  95% CI [{lo2:+.2f},{hi2:+.2f}]")
g=defaultdict(list)
for x,y in zip(X,Y): g[band(x)].append(y)
print("  residual by band:")
for b in ["Flat","Worn","Steady"]:
    if g[b]: print(f"    {b:7} n={len(g[b]):3}  residual {st.mean(g[b]):+.2f}")
# how big would a real effect need to be to be detectable
print(f"\n  with n={len(X)}, the smallest correlation distinguishable from zero at 95% is about r=±{1.96/math.sqrt(len(X)-3):.2f} (Fisher)")


# ── SQL used to build the inputs ──────────────────────────────────────────
# logs.json:
#   select workout_date::date d, workout_distance_miles mi, workout_duration_minutes mn,
#          workout_type wt, mood, felt_rpe fr, planned_rpe pr, stress_load sl, stats_excluded ex
#   from training_logs where user_id = :uid order by workout_date;
# bio.txt (date,resting_hr,sleep_total_min per row):
#   select date, resting_hr, sleep_total_min from daily_biometrics where user_id = :uid order by date;
