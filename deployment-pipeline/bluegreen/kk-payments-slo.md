# kk-payments: Service Level Indicators and Objectives

## Scope and measurement caveat

This service currently runs as a staging simulator (Vagrant VM, blue/green on ports
3000/3001, single nginx proxy on port 80). It has never carried real production
traffic. Every target below is a **proposed target**, set from engineering judgment
and the reliability requirements in the Week 8 brief, not from measured production
behavior. Where a number needs production validation before it can be trusted for
an SLA, that is called out explicitly.

---

## SLI 1: Availability

**Definition**: The proportion of health-check and application requests to
`kk-payments` that receive a successful (non-5xx) response through the nginx
proxy, over a rolling window.

- **Data source**: nginx access logs (`/var/log/nginx/access.log`), filtered to
  requests on port 80 routed through the `kijanikiosk_active` upstream.
- **Calculation**: `1 - (count of 5xx responses / count of total responses)` over
  the measurement window, expressed as a percentage.
- **Measurement window**: 30 days, for the SLO. Short-window checks (below) use a
  much tighter window for rollback decisions.

**SLO target**: 99.5% availability over 30 days (proposed target — not yet
measured against production traffic; this staging box has no sustained request
volume to validate against).

---

## SLI 2: Latency

**Definition**: The proportion of requests to the `/health` endpoint (used here as
the available proxy for application responsiveness, since `kk-payments` does not
yet expose a payment-specific timed endpoint) that complete in under 300ms,
measured at the nginx proxy.

- **Data source**: nginx access log `$request_time` field (requires
  `log_format` to include `$request_time`; not yet enabled on this staging
  box — see exclusions).
- **Calculation**: `count of requests with request_time < 0.3s / total requests`
  over the window, expressed as a percentage.
- **Measurement window**: 30 days for the SLO; 60-second rolling window for
  short-window rollback evaluation.

**SLO target**: 95% of requests under 300ms over 30 days (proposed target — the
`/health` endpoint on this stub responds in single-digit milliseconds locally, so
this number is a placeholder informed by typical API latency budgets, not this
service's actual measured distribution).

---

## SLI 3: Payment error rate

**Definition**: The proportion of payment-processing requests that fail due to a
server-side error (not a legitimate business decline such as insufficient funds),
out of all payment-processing requests.

- **Data source**: this would be a structured log field emitted by the
  application itself at the point of payment processing (e.g. a `payment_result`
  field with values `success` / `declined` / `error`), not something nginx or the
  proxy layer can distinguish. **The current `kk-payments` stub has no payment
  logic and does not emit this field.** This SLI is specified as what the
  production service would need to implement, not something measurable today.
- **Calculation**: `count of payment_result=error / count of all payment attempts`
  over the window.
- **Measurement window**: 30 days for the SLO.

**SLO target**: <0.1% server-side payment error rate over 30 days (proposed
target, unmeasured — there is no payment logic in the current stub to generate
this signal).

---

## Rollback threshold table

Rollback thresholds are deliberately tighter and shorter-window than the SLO
targets. The SLO describes what "good" looks like over a month; the rollback
threshold describes what triggers an automatic reaction in the next few seconds.
A single short window breaching threshold does not mean the 30-day SLO has been
violated — it means the current deployment looks unhealthy enough that reverting
to the last known-good version is safer than waiting for more data.

| SLI | Rollback threshold (short window) | Window | Relationship to SLO target |
|---|---|---|---|
| Availability | 2 consecutive health-check failures | 10s (2 x 5s poll interval) | Far more aggressive than the 99.5%/30-day SLO — a single 10s outage window is a rounding error against a 30-day budget, but it's still a strong enough signal that the newly deployed version is broken |
| Latency | Not currently implemented in `post-deploy-monitor.sh` | — | Gap — see exclusions below |
| Payment error rate | Not currently implemented — no payment logic exists to measure | — | Gap — see exclusions below |

**Current implementation status**: only the availability threshold is wired into
`post-deploy-monitor.sh` today (`FAILURE_THRESHOLD=2` at `POLL_INTERVAL=5s`, giving
10s detection and a measured 6-second T0-to-T2 rollback in testing, well under the
90-second requirement). Latency and payment-error rollback triggers are specified
here as a design target for the monitor, not yet built.

---

## What we do not commit to

- **End-to-end payment success rate as experienced by the customer's browser.**
  We can measure server-side error rate, but not client-side failures (timeout
  before the request reaches us, JS errors in checkout, network failures on the
  customer's connection). Those require real user monitoring, which this staging
  environment has no mechanism to collect.

- **Latency under concurrent load.** The 300ms target above is based on a single
  request against an idle stub service. We do not commit to that number holding
  under realistic concurrent traffic, because this environment has never been
  load-tested — there is no data to support a concurrency-adjusted target yet.
