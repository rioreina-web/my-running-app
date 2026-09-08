// k6 burst smoke test (starter)
// ---------------------------------------------------------------------------
// PURPOSE: simulate the realistic traffic shape for a 1000-person beta with
// LIGHT concurrency — not 1000 users hammering at once, but a spiky burst
// (e.g. a "morning rush" of syncs/reads) on top of a low steady trickle.
//
// This catches the two failures that actually bite at your scale:
//   - your LLM/Gemini provider rate limit + latency, and
//   - database connection-pool exhaustion under a burst.
//
// RUN AGAINST STAGING ONLY. Never point this at production.
//
// INSTALL:  brew install k6        (macOS)   |   https://k6.io/docs/get-started
// RUN:      BASE_URL=https://YOUR-STAGING-URL  k6 run outputs/starter-tests/k6-burst-smoke.js
// ---------------------------------------------------------------------------

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const latency = new Trend('endpoint_latency', true);

const BASE_URL = __ENV.BASE_URL || 'http://localhost:54321';

// Traffic shape: steady trickle, then a morning-rush spike, then back down.
// Tune the spike to the load you actually expect — for a light-concurrency
// beta, a peak of ~30-50 simultaneous requests is realistic and plenty.
export const options = {
  scenarios: {
    steady_trickle: {
      executor: 'constant-vus',
      vus: 3,
      duration: '2m',
    },
    morning_rush: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '20s', target: 40 }, // spike up
        { duration: '40s', target: 40 }, // hold the rush
        { duration: '20s', target: 0 },  // drain
      ],
      startTime: '30s', // overlap the spike on top of the trickle
    },
  },
  thresholds: {
    errors: ['rate<0.01'],                 // <1% errors
    endpoint_latency: ['p(95)<2000'],      // 95% of requests under 2s
  },
};

// Pick an endpoint that is safe to hit repeatedly and representative of real
// cost. Prefer a read endpoint or a health check first; only load-test
// authenticated/LLM endpoints with a dedicated staging test token and an eye
// on your Gemini bill.
//
// Replace this with a real staging endpoint. A health/ping route is the safest
// first target to confirm the server + DB pool hold up under burst.
export default function () {
  const res = http.get(`${BASE_URL}/functions/v1/get-pace-zones?probe=1`);
  latency.add(res.timings.duration);
  const ok = check(res, {
    'status is 2xx/4xx (server responded)': (r) => r.status > 0 && r.status < 500,
    'not a 5xx (server/DB did not fall over)': (r) => r.status < 500,
  });
  errorRate.add(!ok);
  sleep(Math.random() * 2); // jitter so VUs don't move in lockstep
}

// WHAT TO WATCH while this runs (in the Supabase dashboard, separate window):
//   - Database > connection count: does the burst exhaust the pool?
//   - Edge function logs: any 5xx, timeouts, or "too many connections"?
//   - If you swap in an LLM endpoint: Gemini 429s / quota errors and what the
//     USER sees when they happen (must be a graceful retry message, not a hang).
