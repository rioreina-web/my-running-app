# Competitive brief — Post Run Drip

**Date:** 2026-04-24 · **Author:** Rio (synthesis via Claude).

This is an honest read, not a pep talk. Dated because the landscape moves
fast — re-run this every 3–6 months and especially after any Runna /
TrainingPeaks / Strava announcement.

Caveats: I didn't web-search for current pricing or latest launches — use
this as a structured baseline, then verify specifics before citing any
number externally.

---

## 1. Who you're actually competing with

**Direct — serious runners pick between these:**
- **Runna** — AI-authored adaptive plans, highly polished iOS. Acquired by Strava 2024. Priced ~£8.99–14.99/mo. Biggest threat by distribution.
- **TrainingPeaks** — the incumbent for coach-athlete relationships. Athletes + coaches + training load analytics. Premium ~$20/mo, coach-led tiers cost more. Ugly UI but deeply entrenched.
- **Final Surge** — TrainingPeaks-lite. Free + premium. Same category.
- **Humango** — AI coach, triathlon-leaning. Smaller than Runna.
- **Private coach on Google Docs / email / Spreadsheets** — massively underrated competitor. Probably more than all the above combined for BQ-aspiring runners.

**Indirect — pulls users away without solving the same problem:**
- **Strava** — social + tracking. Now owns Runna. Distribution moat.
- **Garmin Connect** — device-centric, free. Baseline plans included.
- **Nike Run Club / adidas Running** — free, casual.
- **Stryd** — power-based running + device ecosystem.

**Substitute solutions — when nothing above fits:**
- **ChatGPT / custom GPTs** — serious runners using off-the-shelf LLMs with their Strava export. Free + already installed.
- **No plan, just vibes** — huge segment. The "self-coached runner reading Letsrun forums" market.

**Adjacent — could expand into your space:**
- **Whoop / Oura / Eight Sleep** — have biometric data, could add coaching.
- **Apple Fitness+ / Peloton** — could add structured running coaching.
- **OpenAI / Anthropic directly** — if they launch a "Coach" product.

---

## 2. Landscape map — two-axis positioning

```
                  SERIOUS / ELITE
                        │
   TrainingPeaks  ──────┼──────  Humango · Vdot
   Private Coach        │
                        │                ● Post Run Drip
                        │                  (coach + AI, serious)
                        │
                        │                ● Runna (post-Strava)
                        │                  moving this direction
                        │
   ─────────────────────┼─────────────────────────────── AI-DRIVEN
                        │
          Garmin Connect│    Nike Run Club
                        │    Runna (pre-Strava)
                        │    adidas Running
                        │
                  CASUAL / RECREATIONAL
                        │
   COACH-DRIVEN                         AI-DRIVEN
```

Post Run Drip's position — upper-middle, coach-first + AI-assisted,
serious segment — is defensible *if* the coach relationship is real.
If not, you're just "worse Runna" in the upper-right quadrant.

---

## 3. Feature comparison (honest)

Rating: **S**trong · **A**dequate · **W**eak · **—** Absent

| Capability | PRD | Runna | TrainingPeaks | Humango | Private Coach |
|---|---|---|---|---|---|
| **Plan authoring** | | | | | |
| AI-generated plans | W (suspended) | **S** | — | **S** | — |
| Coach-authored plans | A (join code) | — | **S** | — | **S** |
| Import existing plans | A | — | A | — | N/A |
| **Mid-plan adaptation** | | | | | |
| Reconcile actual vs planned | **S** (reconcile-log + adjustments) | A | W | A | varies |
| Auto-adjust on missed sessions | **S** (plan_adjustments) | A | — | A | — |
| Coach-visible adjustment queue | A (spec'd, not shipped) | — | **S** | — | N/A |
| **Coach relationship** | | | | | |
| 1:many coach-athlete | A (join codes, thin) | — | **S** | — | **S** |
| Coach dashboard | W | — | **S** | — | varies |
| Coach messaging | A | — | A | — | **S** |
| **Integrations** | | | | | |
| Apple HealthKit | **S** | **S** | A | A | — |
| Strava | A | **S** (owned) | **S** | A | varies |
| Garmin | W | A | **S** | **S** | varies |
| Vital / wearables | A | W | A | A | — |
| **Intelligence** | | | | | |
| Pace zone math | **S** (ratio ladder) | A | A | **S** | varies |
| Weather-aware pace | A | — | — | — | — |
| Voice memo + transcription | **S** | — | — | — | — |
| AI chat coaching | **S** | W | — | A | N/A |
| Injury / load signals | A | W | **S** (TSB, CTL, ATL) | A | varies |
| **Brand + UX** | | | | | |
| Editorial design language | **S** | A | W | W | N/A |
| Mobile UX polish | A | **S** | W | A | N/A |
| Web UX polish | A | A | A | A | N/A |
| **Commercial** | | | | | |
| Shipping / launched | — | **S** | **S** | **S** | **S** |
| Paid tier | — | **S** | **S** | **S** | N/A |
| Free tier | — | trial only | **S** | trial | N/A |
| User base | 0 | Millions | Hundreds of thousands | Tens of thousands | N/A |

**Takeaways from the matrix:**
- You have genuinely unique tech (voice memos, adaptive loop, weather-aware pace) — this is not a marketing claim, it's real.
- You are 0% shipped on the commercial row. Everything else is moot until H.5 lands and real users are on it.
- Coach-relationship row: you have the model but the tooling is thin. TrainingPeaks owns this today.
- Mobile polish row: Runna is the bar. You're close, not there.

---

## 4. Positioning analysis

**Runna:**
- Category: "Personalized running plans powered by AI"
- Differentiator: AI that adapts · polished UX · gamified
- Value prop: "Train for your PB without a coach"
- Proof: millions of users, Strava acquisition, App Store top charts

**TrainingPeaks:**
- Category: "The science of endurance training"
- Differentiator: Coach-athlete platform · training load analytics
- Value prop: "Train like the pros"
- Proof: used by pro teams, Kona athletes, cycling WorldTour

**Humango:**
- Category: "Your AI endurance coach"
- Differentiator: Multi-sport · learns from your sessions
- Value prop: "Adapts daily to how you feel"
- Proof: triathlete testimonials

**Post Run Drip (proposed positioning — fill in the gaps):**
- Category: *For BQ-aspiring runners, a coaching platform that pairs a real coach with an AI that handles the busy-work.*
- Differentiator: Glass-box coaching · voice reflection · adaptive every week, not once a quarter
- Value prop: "Train like you have a coach — because you do, plus an AI that remembers everything."
- Proof: *(you don't have any yet — this is the missing piece)*

The positioning is defensible. The proof is the gap.

---

## 5. Real strengths — what's actually yours

1. **The adaptive plan loop is real engineering.** `reconcile-log → adapt-plan → plan_adjustments` is not a pitch; it's shipped code. Runna adapts weekly. TrainingPeaks relies on the coach. You adapt per-session, with evidence. This is the technical moat if you build on it.

2. **Voice memos + sentiment + coaching context.** No one else does this. If athletes use it, it produces coaching signal no competitor can match — mood, injury cues, fatigue complaints — feeding directly into the AI's context and the coach's dashboard.

3. **Coach-first brand + AI-assist blend.** You sit between two lanes that think they're complete. Neither Runna nor TrainingPeaks has what you have if you execute. The blend is genuinely under-explored.

4. **Pace + weather intelligence.** The ratio-based ladder (shipped today) + weather-aware pace adjustment = serious-runner catnip. Surface it visibly.

5. **Editorial brand voice.** Sets you apart from functional / sterile competitors. Matches the reflective, process-oriented BQ-aspirant persona.

---

## 6. Real risks — what keeps you honest

1. **You're not launched. They are.** Runna has years of data, reviews, retention curves. Every month you don't ship is a month you're falling behind, not catching up.

2. **Strava owns Runna = zero-CAC distribution.** Runna can push Strava users into their app for free. Your user acquisition costs start at real dollars.

3. **Single operator against well-funded teams.** Runna has engineers, designers, a marketing team. TrainingPeaks has 200+ people. Feature-parity war is a losing race — pick your battles carefully.

4. **Coach marketplace is empty.** "Coach-first" is a brand promise that requires actual coaches. You need 5–10 signed coaches before GA or the empty-state "Join Coach's Plan" flow is a dead end for 95% of signups.

5. **Build Adaptive suspension left a gap.** Athletes who don't have a coach and don't have an existing plan to import now have nothing. Import Plan is a technical path, not a product path — most users won't use it.

6. **AI coaching is table stakes now.** Having an AI chat isn't differentiated. It needs to be *demonstrably better* — grounded in a coaching corpus, citing evidence, glass-box rationales.

7. **Runna launching a coach marketplace would compress your timeline to zero.** They have the polish, the users, the capital. If they add coaches, you're in real trouble. Watch their changelog.

---

## 7. Strategic implications — the "so what"

Three moves, in priority order. These should inform what you ship next.

**1. Ship H.5 and go to launch. Stop shipping features until you do.**
   - Every week unlaunched is compound interest in competitors' favor.
   - Don't try to be at feature parity with Runna at launch. Launch with the three things you're actually better at: voice memos + adaptive loop + coach-first path.
   - Restrict GA to a narrow segment (e.g., "if you have a coach and want the AI to help") to make the coach-first promise deliverable.

**2. Recruit 10 coaches before GA. This is the single highest-leverage activity.**
   - Each coach brings ~20–50 athletes. 10 coaches × 30 = 300 seed users with intent.
   - That's more valuable than any feature.
   - The coach-first brand is a check that only a live coach marketplace can cash.
   - Build a lightweight coach onboarding flow: invite-by-link, branded athlete dashboard, join code generation, coach's cut of any paid tier.

**3. Double down on the three durable advantages. Stop racing Runna on Runna's strengths.**
   - **Voice memos → coaching context.** Build the reflection → sentiment → rationale pipeline. No one else has this.
   - **Glass-box rationales.** AP-4 in the athlete-plan-prompts is literally this. It's your "Why?" drawer — Runna can't copy this without rebuilding their architecture.
   - **Adaptive loop as visible intelligence.** Expose `plan_adjustments` as a timeline: "here's what the AI adjusted this month and why." Nobody else makes their adaptation visible.

**What to explicitly NOT do:**
- Rebuild Build Adaptive before the corpus exists. You'll ship Runna-lite.
- Try to match Runna on polish week-over-week. Different races.
- Ship a free tier. Your segment (BQ-aspirant) pays. Price at $29–49/mo for coach-enabled, position against the $300+/mo private-coach-on-docs option.
- Compete with Garmin on device features. That's a land war.

---

## 8. What to monitor (set up a quarterly check)

- **Runna product changelog.** Any mention of "coach," "marketplace," "1:1 coaching."
- **TrainingPeaks modernization.** Rumored UI rebuild — if they ship a Runna-feeling UX, they become dangerous in your segment.
- **Strava AI features.** They sit on data. Any AI coaching launch is a threat to you and Runna both.
- **Apple / Garmin native coaching.** Watch WWDC and Garmin announcements.
- **Generic coach-on-docs backlash.** If 10,000 BQ-aspirants migrate off Google Docs to TrainingPeaks, that's your signal the segment is ready.

---

## 9. One-line summary

*You have three things nobody else has (voice memos, adaptive loop, glass-box rationales) and two things you urgently need (launched product, signed coaches). Ship H.5, sign 10 coaches, and protect the three moats. Don't build Runna.*

---

*Companion docs: `brand-voice.md`, `docs/athlete-plan-ux.md`,
`docs/build-adaptive-plan-suspension.md`, `pace-system-rework.md`.*
