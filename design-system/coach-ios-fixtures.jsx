/* global window */
/* ════════════════════════════════════════════════════════════════════
   COACH · iOS · fixtures
   Same week of training. Three directions read it differently.
   Sarah · week 9 of 16 · marathon block · sub-3:15 build.
   ════════════════════════════════════════════════════════════════════ */

const COACH_FIXTURES = {

  /* ── SHARED CONTEXT ─────────────────────────────────────────────── */
  dateline:   "THU · MAY 14 · WK 9 / 16",
  athlete:    "Sarah",
  plan:       "Sub-3:15 · marathon build",

  /* Coaching docs from the RAG knowledge base (supabase/seed/
     coaching_documents.json). Cited inline alongside workouts so
     "every recommendation cites the data behind it" is visible. */
  docs: {
    fuelTraining: {
      id: "doc-fuel-training",
      category: "NUTRITION",
      title:   "Fueling for Training",
      excerpt: "Runs 90+ min: 60–90g carbs/hour becomes important. Practice in training what you'll do in races.",
    },
    longRun: {
      id: "doc-long-run",
      category: "TRAINING",
      title:   "The Long Run",
      excerpt: "Long runs are when you practice race-day nutrition. Test gels, drinks, and timing.",
    },
    recovery: {
      id: "doc-recovery",
      category: "RECOVERY",
      title:   "Recovery Between Sessions",
      excerpt: "The body may be fatigued muscularly, neurologically, or systemically. Respect that.",
    },
  },

  /* Workouts the coach references across directions.
     Each has a tiny shape so it can render as an evidence chip. */
  workouts: {
    tueTempo: {
      id: "w-tue-tempo",
      day:    "TUE · MAY 12",
      type:   "TEMPO",
      title:  "5 mi @ HMP",
      meta:   "6:48 avg · 152 bpm · 68°F",
      adj:    "negative split, last mile 6:42",
    },
    sunLong: {
      id: "w-sun-long",
      day:    "SUN · MAY 10",
      type:   "LONG",
      title:  "18 mi steady",
      meta:   "7:42 avg · 144 bpm · drizzle",
      adj:    "held through, no fade",
    },
    thuEasy: {
      id: "w-thu-easy",
      day:    "THU · MAY 7",
      type:   "EASY",
      title:  "6 mi recovery",
      meta:   "8:21 avg · 132 bpm",
      adj:    "felt flat, knee mention",
    },
  },

  /* ── DIRECTION A · THE READ (editorial) ─────────────────────────── */
  read: {
    plate: { surface: "COACH · THE READ", fig: "FIG. 14 · A" },
    eyebrow: "FROM YOUR COACH · THU 7:41 AM",
    headline: "The base is taking.",
    /* paragraph with inline evidence anchors. Each segment is either a
       string, {workout:id} (workout citation), or {doc:id} (RAG doc
       citation). Both render as tappable mono chips, kerned with the
       prose — making "every recommendation cites the data" visible. */
    paragraph: [
      "Three good weeks in a row. Easy paces have settled a beat slower without losing fitness, ",
      { workout: "thuEasy" },
      " — that's the aerobic base doing its work. Tuesday's tempo landed where it should, ",
      { workout: "tueTempo" },
      ", and Sunday you held 18 through drizzle without a fade, ",
      { workout: "sunLong" },
      ". The volume is honest. Don't add to it — the next test is Wednesday's MP block, and the legs need to be a little hungry for it.",
    ],
    signature: "— posted Thursday morning · 4 min read",
    /* Honest when uncertain. The brand-voice attribute hardest to fake. */
    cantSee: {
      eyebrow: "WHAT I CAN'T SEE",
      body:    "Sleep this week — your watch hasn't synced since Sunday. And the knee mention on Thursday's easy is one data point. If it shows up again, tell me Saturday morning.",
    },
    /* Sources — the actual things the read was built from. Opens
       to reveal cited workouts + docs + memos. */
    sources: {
      label: "SOURCES · 6",
      sub:   "WORKOUTS, KNOWLEDGE, VOICE MEMOS",
      items: [
        { kind: "workout", id: "thuEasy" },
        { kind: "workout", id: "tueTempo" },
        { kind: "workout", id: "sunLong" },
        { kind: "doc",     id: "recovery" },
        { kind: "doc",     id: "longRun" },
        { kind: "memo",    label: "Voice memo · SUN 11:14 AM",
          excerpt: "...felt strong through 12, last six were honest work but no fade..." },
      ],
    },
    confidence: {
      label: "CONFIDENCE",
      level: "HIGH",
      sub:   "47 workouts read · last 12 weeks complete · 3 docs cited",
    },
    threads: [
      {
        id: "t1",
        title: "the knee",
        last:  "MON · 2D AGO",
        coachLine: "Move Tuesday to easy 6. Three tempos left before taper.",
        unread: 0,
      },
      {
        id: "t2",
        title: "race-week travel",
        last:  "FRI · 6D AGO",
        coachLine: "Land Tuesday, shake-out Thursday, race Sunday — that order matters.",
        unread: 0,
      },
      {
        id: "t3",
        title: "fueling on the long run",
        last:  "SUN · 4D AGO",
        coachLine: "You under-took on miles 14–16. 90g/hr next time, not 60.",
        unread: 1,
      },
    ],
    askChips: [
      "Should I push Wednesday's MP?",
      "How should I fuel the 22?",
      "What's a realistic A goal now?",
    ],
  },

  /* ── DIRECTION A · REPLY STATE ──────────────────────────────────
     What an answer to "How should I fuel the 22?" looks like.
     The coach reaches into RAG (nutrition doc) AND your actual long
     run memo, and cites both. This is the brand-voice promise made
     visible — "yes, there's AI under the hood, here's what we do
     with it." */
  readReply: {
    plate: { surface: "COACH · ANSWERED", fig: "FIG. 14 · A·R" },
    you: {
      eyebrow: "YOU ASKED · THU 8:12 AM",
      text:    "How should I fuel the 22?",
    },
    eyebrow: "FROM YOUR COACH · THU 8:14 AM",
    headline: "Ninety grams an hour. Not sixty.",
    paragraph: [
      "On Sunday's eighteen you took two gels and a bottle, roughly sixty grams an hour, and you faded — not badly, but the last three miles were heavier than the first three, ",
      { workout: "sunLong" },
      ". For a twenty-two with marathon-pace finishing miles, the playbook is closer to ninety grams an hour, ",
      { doc: "fuelTraining" },
      ". Take a gel every thirty-five minutes starting at the top, and bring eight more ounces than Sunday. Treat the 22 as race-day rehearsal — same flavor, same bottles, same pockets, ",
      { doc: "longRun" },
      ". If anything sits wrong, that's the report I want to read on Saturday night.",
    ],
    signature: "— answered in 14s · 2 docs + 1 workout cited",
    confidence: {
      label: "CONFIDENCE",
      level: "HIGH",
      sub:   "Sunday's fuel-log + 2 nutrition docs cited",
    },
    relatedAsk: [
      "What about caffeine timing?",
      "Should I practice cramping recovery?",
      "Pre-run breakfast for the 22?",
    ],
  },

  /* ── DIRECTION B · BRIEFING (decisive) ──────────────────────────── */
  briefing: {
    plate: { surface: "COACH · TODAY'S BRIEFING", fig: "FIG. 14 · B" },
    eyebrow: "TODAY'S CALL · THU MAY 14",
    call:    "Hold the easy. Save it for tomorrow's MP.",
    callSub: "5 easy miles, conversational. Don't chase the pace.",
    /* Decisions waiting on you. Each has the coach's recommendation,
       the alternative, and the evidence behind the call. */
    decisions: [
      {
        id: "d1",
        question:  "Tuesday tempo · move it?",
        because:   "Knee mention on Thursday's easy. Three tempos left before taper — losing one is fine.",
        evidence:  ["thuEasy", "tueTempo"],
        recommend: "MOVE TO EASY 6",
        alt:       "Keep tempo",
        urgency:   "DECIDE BY MON",
      },
      {
        id: "d2",
        question:  "Long run distance · 20 or 22?",
        because:   "You held 18 clean through drizzle, no fade. Twenty-two is the next honest step; 20 is the safe one. I'd go 22.",
        evidence:  ["sunLong"],
        recommend: "GO 22",
        alt:       "Stay at 20",
        urgency:   "DECIDE BY SAT",
      },
      {
        id: "d3",
        question:  "Race-week fueling test",
        because:   "You under-took on Sunday's long run, fade-adjacent mile 14. Test 90g/hr on the 22.",
        evidence:  ["sunLong"],
        recommend: "TEST 90g/hr",
        alt:       "Stick with 60",
        urgency:   "DECIDE BY SAT",
      },
    ],
    /* "What I'm seeing" — three short observations with a number each */
    seeing: [
      { lbl: "VOLUME",    val: "50 MI",   sub: "↑ 4 vs prior · honest"      },
      { lbl: "TEMPO PACE", val: "6:48",   sub: "↓ 8s vs wk 5 · sharpening"  },
      { lbl: "RESTING HR", val: "47 BPM", sub: "↓ 2 · base taking"          },
    ],
    flag: {
      label: "FLAG · KNEE",
      body:  "Mentioned once on Thursday's easy. Not enough to act on; enough to watch. Tell me Saturday morning.",
    },
    ask: "Push back, ask, or change something →",
  },

  /* ── DIRECTION C · THREAD, REFINED (chat done right) ───────────── */
  thread: {
    plate: { surface: "COACH · THE THREAD", fig: "FIG. 14 · C" },
    /* anchored topic — chat isn't generic; it's pinned to a thing */
    topic: {
      eyebrow: "THIS THREAD",
      title:   "Wednesday MP block",
      meta:    "OPEN · 4 MESSAGES · LAST REPLY 32 MIN AGO",
    },
    /* messages — coach uses CoachQuote bubble, athlete uses plain right.
       'workout' field on a message renders an inline evidence chip
       inside the bubble. */
    messages: [
      {
        role: "coach", ts: "WED · 7:14 AM",
        text: "Wednesday is the test. Eight at MP off two tempos in the bank — that's the right setup.",
      },
      {
        role: "you", ts: "WED · 7:42 AM",
        text: "How honest was Tuesday? Felt smooth but the HR was higher than I expected.",
      },
      {
        role: "coach", ts: "WED · 8:10 AM",
        text: "Tuesday was honest. The HR drift is the weather — it was 68°F. Pace held, last mile got faster, not slower. That's the right shape.",
        workout: "tueTempo",
      },
      {
        role: "you", ts: "WED · 9:01 AM",
        text: "OK. Sticking with the plan. 6:55 target for the MP miles?",
      },
      {
        role: "coach", ts: "WED · 9:30 AM",
        text: "6:55 to 7:00. If it feels like work in the first three, hold the back end — don't chase. The goal is finishing the eight, not the fastest eight.",
      },
    ],
    /* suggested next questions — grounded in your actual data */
    suggested: [
      { text: "Move Wednesday earlier?", note: "Forecast: 74°F by 9 AM" },
      { text: "What's the fade risk?",   note: "Off 50-mi week + 2 quality" },
      { text: "Show me last MP block",   note: "Wk 5 · 6 × MP, hit 6:58 avg" },
    ],
    /* other open threads — collapsed strip below */
    otherThreads: [
      { id: "t-knee",  title: "the knee",           last: "2D",  count: 6 },
      { id: "t-fuel",  title: "fueling · long run", last: "4D",  count: 4 },
      { id: "t-trav",  title: "race-week travel",   last: "6D",  count: 9 },
      { id: "t-shoes", title: "race shoes",         last: "2W",  count: 3 },
    ],
  },
};

window.COACH_FIXTURES = COACH_FIXTURES;
