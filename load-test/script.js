// k6 load test for the orders platform, through the public ingress.
//   PROFILE=smoke    30s, 2 VUs                       (sanity check)
//   PROFILE=steady   ~5 req/s for DURATION            (baseline traffic for dashboards)
//   PROFILE=load     ramp up to 30 VUs and hold        (capacity / latency under load)
//   PROFILE=incident constant 10 req/s with injected errors/latency (FAIL_RATE, DELAY_MS)
// The thresholds mirror the SLO and alert thresholds, so a failed run == an alert-worthy state.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const PROFILE = __ENV.PROFILE || 'smoke';
const DURATION = __ENV.DURATION || '2m';
const FAIL_RATE = Number(__ENV.FAIL_RATE || 0);
const DELAY_MS = Number(__ENV.DELAY_MS || 0);

const profiles = {
  smoke:  { executor: 'constant-vus', vus: 2, duration: '30s' },
  steady: { executor: 'constant-arrival-rate', rate: 5, timeUnit: '1s', duration: DURATION, preAllocatedVUs: 10, maxVUs: 30 },
  load:   { executor: 'ramping-vus', startVUs: 0, stages: [
            { duration: '30s', target: 10 }, { duration: '1m', target: 30 },
            { duration: '1m', target: 30 }, { duration: '30s', target: 0 } ] },
  incident: { executor: 'constant-arrival-rate', rate: 10, timeUnit: '1s', duration: DURATION, preAllocatedVUs: 20, maxVUs: 60 },
};

export const options = {
  scenarios: { main: profiles[PROFILE] },
  thresholds: {
    // Same numbers as the alerts: error rate < 5%, p95 < 300ms.
    'http_req_failed{expected:true}': ['rate<0.05'],
    'http_req_duration{expected:true}': ['p(95)<300'],
    checks: ['rate>0.95'],
  },
  summaryTrendStats: ['avg', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// 500s from /fail are intentional during an incident drill, so they must not count as failures.
const failExpected = http.expectedStatuses({ min: 200, max: 399 }, 500);

export default function () {
  const list = http.get(`${BASE}/api/orders`, { tags: { name: 'GET /orders', expected: 'true' } });
  check(list, { 'list orders 200': (r) => r.status === 200 });

  if (Math.random() < 0.2) {
    const body = JSON.stringify({ item: `k6-item-${__VU}-${__ITER}`, quantity: 1 + Math.floor(Math.random() * 5) });
    const create = http.post(`${BASE}/api/orders`, body, {
      headers: { 'Content-Type': 'application/json' }, tags: { name: 'POST /orders', expected: 'true' } });
    check(create, { 'create order 201': (r) => r.status === 201 });
  }

  if (FAIL_RATE > 0 || DELAY_MS > 0) {
    // Not tagged expected:true, so injected failures/latency do not trip the run's own thresholds.
    http.get(`${BASE}/api/fail?rate=${FAIL_RATE}&delay_ms=${DELAY_MS}`, {
      responseCallback: failExpected, tags: { name: 'GET /fail', expected: 'false' } });
  }
  sleep(0.2);
}
