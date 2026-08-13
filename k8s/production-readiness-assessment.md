# Production Readiness Assessment — kk-api / kk-payments Deployment

## External routing

The current Ingress terminates plain HTTP at `kijani.local`, and kk-payments handles payment credentials — Stripe keys, JWT secrets — over that unencrypted connection. Anyone positioned on the network path between a client and the Ingress controller can read those credentials in transit; HTTP gives no protection at all here, and this is disqualifying for real customer traffic regardless of what else is hardened.

To fix this: add a `Certificate` resource (cert-manager) or a manually-provisioned TLS `Secret`, reference it in the Ingress under `spec.tls`, and add the `nginx.ingress.kubernetes.io/ssl-redirect: "true"` annotation to force HTTP→HTTPS. In a real cluster this would pair with cert-manager and a `ClusterIssuer` (e.g. Let's Encrypt) rather than a static cert, so renewal doesn't become a manual chore.

Beyond TLS, there is no rate limiting on the payments path. A payment endpoint with no request throttling is exposed to both abusive traffic and accidental retry storms — we saw a version of this today when Nexus's own rate-limiter locked us out under retry pressure from crash-looping pods; an unprotected payments Ingress has the same failure shape in reverse, with the traffic coming from outside. The fix is `nginx.ingress.kubernetes.io/limit-rps` (or `limit-connections`) scoped to the `/payments` path specifically, tuned below the service's real capacity.

## Health signalling

The probe timing (`readiness`: 5s delay/10s period/3 failures; `liveness`: 15s delay/20s period/3 failures) is copied from a generic template, not tuned to kk-payments' actual startup behavior — and since the stub has no real database connection or warm-up cost, we don't actually know what "real" startup looks like yet. Before this serves production traffic, `initialDelaySeconds` needs to reflect actual cold-start time under real dependencies (DB connection pool warm-up, secret retrieval), not a guess.

The bigger risk is `failureThreshold: 3` on the liveness probe. If the payments database is briefly slow (a lock contention spike, a connection pool exhaustion event), a low failure threshold makes Kubernetes kill and restart pods that were about to recover on their own — turning a transient DB slowdown into a full pod restart storm, which is strictly worse for a payment service than just waiting it out. This threshold should be raised for kk-payments specifically, separate from kk-api's tolerance.

## Capacity

Three replicas with no autoscaling is a fixed ceiling — fine for steady load, inadequate for an end-of-month spike where KijaniKiosk's real traffic pattern likely concentrates. Making autoscaling viable requires: `metrics-server` installed in the cluster, the resource `requests` we already set (CPU/memory) to give the HPA something to measure against, and an `HorizontalPodAutoscaler` targeting CPU utilization.

The HPA's target percentage matters more than it looks. Set too high (e.g. 90%), pods only scale once they're already saturated — new replicas arrive too late to prevent latency spikes or timeouts during the surge itself. Set too low (e.g. 20%), the deployment scales aggressively on routine load, churning pods constantly and wasting cluster resources without meaningfully improving reliability. A mid-range target (60-70%) with reasonable `stabilizationWindowSeconds` to prevent flapping is the safer starting point, tuned against real traffic data once it exists.
