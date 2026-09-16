# Revenue Review — grounded in the actual product state

*2026-06-15. What the app can realistically earn, based on what is and
isn't actually built — not on the category in the abstract.*

## The headline finding

**The app cannot collect a single dollar today.** There is no payment
integration anywhere in the codebase — no StoreKit / in-app purchase, no
RevenueCat, no Stripe, no paywall, no pricing screen, no product IDs.
Searched iOS, web, and edge functions; nothing.

Two things that *look* like monetization but aren't:

- `user_tiers` (`free` / `pro` / `unlimited`, default `daily_limit = 5`)
  is an **AI rate-limit / cost-control** construct, used in
  `coaching-agent` to cap LLM spend. There is no path to move a user from
  `free` to `pro`, because nothing takes money.
- `subscribe-to-plan` is "subscribe to a **training plan**" (turns a
  template into scheduled workouts) — not a paid subscription.

So every revenue number below is gated behind *first building the
monetization layer that doesn't exist yet.* Revenue today = **$0**, and
not because of the market — because there's no cash register.

## What IS built (the sellable value)

The core value loop is real and tested, which is the hard part:

- Voice logging (`VoiceLogViewModel`) — the daily-habit input.
- Native HealthKit ingestion — workouts auto-populate.
- Pace engine + fitness predictor — both have passing unit tests.
- Coachable-moment rule engine + the AI "Daily Read" (the differentiated,
  LLM-powered synthesis surface).
- A 5-tab app, a real design system, an LLM eval harness.

The thing people would pay for — honest, voice-aware coaching observation
— functions. What's missing is the wall between "free" and "paid," and
the launch-readiness underneath it.

## What must ship before $1 of revenue

1. **Payment layer.** App Store IAP via StoreKit 2 or (faster) RevenueCat:
   paywall, plan picker, purchase → tier upgrade, receipt validation,
   restore purchases. Roughly **2–4 focused weeks** with RevenueCat;
   longer rolling your own.
2. **Launch-readiness blockers** (already in your own docs): the
   `user_profiles` ghost table, Supabase prod still in dev config. You
   cannot run a paid service on this until these close.
3. **Fix the front-door message.** Onboarding still says *"Sunday night,
   your coach posts a note"* — the coach-dyad story the product is
   explicitly moving away from for the self-coached Maya wedge. Selling
   "observation, not prescription" while onboarding promises a human coach
   will hurt conversion. Align the pitch with what you're charging for.

## A monetization design that fits this product

The product has one naturally ownable paywall: **the AI Coach Read.**

- **Free forever:** voice logging + the journal + basic Trends, plus the
  already-built 5/day AI cap. Keep the *input* free — the journaling habit
  is your retention engine and your data moat. Cheap to serve (the rate
  limit already governs LLM cost — a genuine pre-built advantage).
- **Paid:** unlimited Coach Reads, race-anchored prediction with
  confidence, the "read my journey through this lens" queries, full
  editorial depth at `data_depth` 3.
- **Price:** ~**$10–13/mo or $89–99/yr**, deliberately just under Runna
  (~£16/mo) — the lighter-touch "observe, don't prescribe" positioning
  supports a slightly lower, stickier price.

Monetize the *synthesis*, never the *input*.

## Realistic revenue scenarios

Net ARPU assumption: ~**$95/paying user/yr** (≈$100–120 gross less the
app-store cut). Scenarios are outcome tiers, not forecasts — which one you
land in is set almost entirely by **retention**.

| Outcome | Paying subs | ARR | Notes |
|---|---|---|---|
| Never finishes monetization / no PMF | < 500 | **$0 – ~$50K** | Statistical base rate for a consumer app |
| Indie / lifestyle business | 1,000 – 5,000 | **~$100K – 475K** | Realistic *good* outcome; organic growth, wedge nailed |
| Strong niche, real PMF | 10,000 – 25,000 | **~$1M – 2.4M** | Requires churn well below category average |
| Breakout (Runna-like) | 100,000+ | **$10M+** | Runna ≈ $4M/mo revenue now — but launched pre-consolidation; lottery ticket for a new entrant |

## The two numbers that decide everything

1. **Monthly churn.** Category average is ~9.2%/mo (~68%/yr) — at that
   rate you fill a leaky bucket and stay in row one regardless of
   acquisition. The voice-journaling loop is, structurally, a daily-
   engagement habit that *should* beat that. If you can show ~3–4%/mo,
   rows two and three open up. This is the whole ballgame.
2. **LTV : CAC.** At high churn, LTV ≈ $30–40 vs. a ~$30 paid CAC — paid
   growth loses money. At low churn, LTV climbs to $150–250 and paid
   finally works. Until churn is proven low, organic/community is the only
   non-destructive channel.

## Honest bottom line

Realistically this is a **$0 to ~$500K ARR** product, with a real-but-
minority path to **$1–2M** if the journaling loop produces retention that
consumer fitness apps almost never achieve. The ceiling isn't set by the
code (strong) or even the competition (heavy but beatable on the wedge) —
it's set by churn.

And right now the number is $0 until the payment layer and the launch
blockers are built. The fastest, cheapest next move isn't growth spend or
even the paywall — it's a small closed beta instrumented to measure
30/60/90-day retention. That one curve tells you whether to build the cash
register at all. Build it for a few dozen real runners before you build it
for revenue.
