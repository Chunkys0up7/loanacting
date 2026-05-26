# Load, Performance, Scaling, and Chaos Testing

The non-functional category that most projects skip. Used during Pass 4 of the audit. Use
this whenever the user asks for load tests, scaling tests, performance tests, or when a
service is being deployed without one.

A service with no load test has unknown capacity. That is a defect, not a future enhancement.

---

## The Non-Functional Test Pyramid

```
        ╱─────────────╲
       ╱   Chaos       ╲     ← rare, expensive, high value
      ╱─────────────────╲
     ╱    Soak/Endurance ╲   ← run nightly/weekly
    ╱─────────────────────╲
   ╱  Scalability tests    ╲
  ╱─────────────────────────╲
 ╱    Stress + Spike tests   ╲ ← run on major changes
╱─────────────────────────────╲
╱       Load tests              ╲ ← run on every release
─────────────────────────────────
╱   Benchmarks (per-function)    ╲ ← run in CI
───────────────────────────────────
```

Most projects have *nothing* above the bottom layer. Aim for at least benchmarks + a baseline
load test before declaring a service production-ready.

---

## Required Metrics

Every load/performance test must report:

- **Throughput** — requests/second (or operations/second).
- **Latency** — p50, p95, p99, p99.9. Mean alone is misleading.
- **Error rate** — percent of failed responses.
- **Resource usage** — CPU, memory, file descriptors, DB connections.
- **Saturation** — queue depth, connection pool utilization.

Failing to report p99 latency is reporting nothing — your mean is dominated by fast requests
that don't reflect user experience.

---

## Performance / Benchmark Tests (per-function)

For hot paths or any function that's known to be sensitive to performance.

### pytest-benchmark (Python)
```python
def test_parse_benchmark(benchmark):
    result = benchmark(parse, LARGE_INPUT)
    assert result.status == "ok"
```

Run with:
```bash
pytest --benchmark-only --benchmark-autosave
pytest-benchmark compare    # detect regressions vs. baseline
```

Set a regression threshold in CI:
```bash
pytest --benchmark-only --benchmark-compare-fail=mean:10%
```

### When to add benchmarks
- Any parsing / serialization on the request path
- Any algorithm with non-trivial complexity
- Any function used inside a tight loop
- Any function that was *previously* slow and got fixed

Without a benchmark, the next refactor will silently undo the fix.

---

## Load Tests

The single most important non-functional test. Answers: can the system handle production
traffic?

### locust (Python, good for HTTP services)
```python
# locustfile.py
from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def view_homepage(self):
        self.client.get("/")

    @task(1)
    def search(self):
        self.client.get("/search?q=test")
```

Run:
```bash
locust -f locustfile.py --users 100 --spawn-rate 10 --run-time 5m --host http://localhost:8000
```

### k6 (JS DSL, lightweight, scripts work in CI)
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 100 },  // ramp to 100 users
    { duration: '3m', target: 100 },  // stay at 100
    { duration: '1m', target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],   // 95% under 500ms
    http_req_failed: ['rate<0.01'],     // <1% errors
  },
};

export default function () {
  const res = http.get('http://localhost:8000/');
  check(res, { 'status was 200': (r) => r.status === 200 });
  sleep(1);
}
```

Run:
```bash
k6 run script.js
```

### What to specify in a load test
- Target RPS (expected production load)
- Ramp-up profile (don't just slam — production ramps)
- Duration (5-15 minutes minimum)
- Endpoints to hit and at what weight
- Assertions on p95 latency and error rate as pass/fail gates

A load test without thresholds is just a stress demo. Define thresholds.

---

## Stress Tests

Same tool, different settings. Push past expected load to find the failure point.

```javascript
// k6
export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '2m', target: 500 },   // stress
    { duration: '2m', target: 1000 },  // breaking point
    { duration: '5m', target: 0 },     // does it recover?
  ],
};
```

Pass criteria: graceful degradation. Not "no errors at 10x load" — that's unrealistic. Look
for:
- Errors return cleanly (503s, not connection resets)
- p99 degrades but doesn't time out completely
- After the spike, the system recovers (latency returns to baseline)

Cascade failures (one slow dependency takes down the whole system) are the bug to find here.

---

## Spike Tests

Sudden, dramatic increase in traffic.

```javascript
export const options = {
  stages: [
    { duration: '1m',  target: 10 },    // baseline
    { duration: '30s', target: 1000 },  // SPIKE
    { duration: '3m',  target: 1000 },  // sustained
    { duration: '30s', target: 10 },    // back to baseline
    { duration: '2m',  target: 10 },    // recovery
  ],
};
```

Tests:
- Autoscaling reaction time
- Connection pool elasticity
- Cache cold-start behavior
- Recovery (does latency / error rate return to baseline?)

---

## Soak / Endurance Tests

Sustained moderate load over hours. The bug detector for leaks.

```javascript
export const options = {
  stages: [
    { duration: '5m',  target: 100 },
    { duration: '4h',  target: 100 },   // ← long sustained
    { duration: '5m',  target: 0 },
  ],
};
```

Watch for, over the duration:
- **Memory** — does it grow monotonically? Leak.
- **Connections / sockets** — leaking?
- **File descriptors** — leaking?
- **GC pause times** — increasing?
- **Disk** — log/temp file accumulation?
- **Database connection pool** — leaking?
- **Latency drift** — slowly increasing over the run?

Tools to pair with soak runs: Prometheus + Grafana, pyroscope (continuous profiling), or even
just `top` snapshots if you're starting simple.

---

## Scalability Tests

Test whether adding resources actually scales throughput.

The test: at fixed load per worker, increase worker count and measure total throughput.

| Workers | Expected (linear) | Actual | Loss |
|---|---|---|---|
| 1 | 100 rps | 100 rps | 0% |
| 2 | 200 rps | 195 rps | 2.5% |
| 4 | 400 rps | 380 rps | 5% |
| 8 | 800 rps | 600 rps | 25% ← bottleneck |
| 16 | 1600 rps | 700 rps | 56% ← contention |

The point where loss accelerates is the bottleneck. Likely culprits:
- DB connection pool too small
- Shared lock contention
- Single shared cache
- Single-threaded downstream
- Database itself

Without a scalability test, the assumption "we can scale horizontally" is unverified.

---

## Chaos Tests

Inject failures into a running system.

### Tools
- **toxiproxy** — TCP proxy that introduces network conditions (latency, packet loss,
  bandwidth limits, connection drops). Easy to start with.
- **Pumba** — Docker chaos (kill containers, pause, slow network).
- **Litmus / Chaos Mesh** — Kubernetes-native chaos platforms.
- **AWS Fault Injection Service** — for AWS-hosted systems.
- **Gremlin** — commercial, broad.

### Failure modes to test
| Failure | Expected behavior |
|---|---|
| Dependency returns 500 | Circuit breaker / fallback / fail fast |
| Dependency times out | Timeout enforced, no thread leak |
| Network partition | Reconnect, no data loss |
| Slow dependency (added latency) | No cascade — finite queue, fail fast |
| Disk full | Graceful failure, alerts |
| DNS slow | Connection cached, no per-request DNS |
| OS OOM | Restart cleanly via supervisor |

Each failure mode is a test case. Most projects test zero of these.

### Minimal chaos starter
```bash
# toxiproxy: add 500ms latency to the upstream service
toxiproxy-cli create -l 127.0.0.1:6380 -u 127.0.0.1:6379 redis
toxiproxy-cli toxic add -t latency -a latency=500 redis

# Now run the load test against the service.
# Does the service degrade gracefully or fall over?
```

---

## Security Testing (the non-functional that's often non-existent)

### Dependency scanning
Mandatory, run in CI on every PR:
```bash
pip-audit              # Python
npm audit              # JS
trivy fs .             # cross-language, also containers
```

### Static analysis (SAST)
```bash
bandit -r src/        # Python security linter
semgrep --config=auto src/
```

### Secret scanning
```bash
gitleaks detect --source .
trufflehog filesystem .
```

### Fuzzing
For any parser, deserializer, or public input handler:
```python
# atheris (Python coverage-guided fuzzer)
import atheris
import sys

def TestOneInput(data):
    try:
        my_parser(data)
    except (ValueError, MyParseError):
        pass  # expected

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

### AuthN/AuthZ
Every protected endpoint needs minimum 3 tests:
- Valid token → 200
- No token → 401
- Wrong role / wrong user → 403

If any protected endpoint is missing one of those, it's a gap.

---

## Demanding Non-Functional Tests Where They're Missing

When auditing a project with no non-functional tests, the recommendation should be concrete:

> **Priority additions (in order):**
> 1. Set up `pytest-benchmark` and add benchmarks for the 5 hottest functions (use cProfile
>    output as the picker).
> 2. Write a baseline locust scenario hitting the top 3 endpoints at production-representative
>    rates. Run it on every release.
> 3. Add `pip-audit` + `bandit` to CI.
> 4. Add a soak run (1-hour duration) to weekly schedule. Watch memory growth.
> 5. Introduce one chaos test: simulate the most critical dependency timing out for 30s.

Concrete, ordered, file-level. Don't say "you should do load testing" — say "add this k6
script and gate releases on p95 < 500ms".

---

## Continuous Vigilance

Even after non-functional tests exist, ask:

- When did the load test last run? If >3 months ago, it's stale — load has grown.
- Is the load test thresholded? If not, it's decorative.
- Are benchmarks compared against a baseline in CI? If not, they're decorative.
- Is the chaos test in the on-call game day rotation? If not, it's decorative.

Tests that don't enforce a gate or get reviewed don't change behavior. They become wallpaper.
