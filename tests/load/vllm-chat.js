import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 2 },
    { duration: '2m', target: 8 },
    { duration: '2m', target: 16 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],     // lab target, adjust after your first run
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8000';
const MODEL = __ENV.MODEL || 'lab-model';      // use the --served-model-name from your manifest

export default function () {
  const body = JSON.stringify({
    model: MODEL,
    max_tokens: 64,
    messages: [{ role: 'user', content: 'Explain a Kubernetes PodDisruptionBudget in two sentences.' }],
  });
  const res = http.post(`${BASE}/v1/chat/completions`, body, {
    headers: { 'Content-Type': 'application/json' },
    timeout: '30s',
  });
  check(res, {
    'status 200': (r) => r.status === 200,
    'has text': (r) => r.json('choices.0.message.content') !== '',
  });
  const content = res.json('choices.0.message.content');
  if (!content) { console.log(`empty content: status=${res.status} body=${String(res.body).slice(0, 300)}`); }
  sleep(0.2);
}
