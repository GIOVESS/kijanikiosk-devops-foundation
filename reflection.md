# Reflection

## 1. Where did the demo script's plain language overclaim?

The line "That recovery just happened in six seconds" is accurate, but the plain
language around it implies this speed is typical of how failures get caught.
It isn't. Our monitor only detects a failure that manifests as the health
endpoint going completely unreachable — that's what our controlled fault
(stopping the service outright) produced. A real production failure is more
likely to be partial: slow responses, intermittent errors, a memory leak that
degrades service gradually rather than killing it outright. None of those would
necessarily trip two consecutive health-check failures in ten seconds the way a
stopped service does.

To be more precise without losing the board, I'd add one sentence acknowledging
scope: something like "for failures serious enough to break basic connectivity,
recovery happens in seconds — for subtler problems, we're still building out
what automatic detection looks like." That keeps the demonstrated number honest
while not implying we've solved failure detection in general.

## 2. Highest-value action item, and confidence it prevents recurrence

The highest-value item is the demo-lock mechanism (action item 2 in the
post-incident review) — a file-based lock that causes the switch script to
refuse to run during a flagged demo window. I have moderate confidence this
specifically prevents *this* incident from recurring, because it directly
targets the actual root cause we identified: the switch script validates that a
target is a legitimate environment but has no concept of operational context.

I'm less confident it prevents the broader category of incident. The lock only
helps if someone remembers to set it before a demo, which reintroduces a human
step that can be forgotten — the same class of failure, one level up. To be
more certain, I'd need to know how deployments actually get triggered day to
day: is it always a human running a command by hand, or does anything else
(a scheduled job, a webhook, another engineer's script) also have the ability to
call the switch script? If it's not exclusively manual, a lock file alone
doesn't fully close the gap.

## 3. What carries forward into the container world, and what becomes redundant

The **state files** (`.active-env`, `.previous-env`) are specific to the
blue/green model and become entirely redundant in Kubernetes — the cluster
itself tracks which Pods are running and healthy; there's no equivalent concept
of "the currently active named environment" to persist, because Kubernetes
doesn't switch between two long-lived environments, it continuously reconciles
toward a desired state.

The **switch script** also doesn't carry forward as written — Kubernetes
handles the mechanics of introducing new versions and shifting traffic through
its own deployment strategies, not through a custom script calling `nginx -t`
and `systemctl reload`.

What *does* carry forward conceptually is the **rollback script's underlying
logic**: watch a health signal, decide when it indicates failure, act on that
decision without a human in the loop. Kubernetes reimplements this idea through
liveness and readiness probes rather than our bash script, but the concept —
continuous health observation driving automatic corrective action — is the same
one we built by hand for blue/green, and seeing Kubernetes do it as a built-in
capability (rather than something we had to write ourselves) was the clearest
illustration of why the platform is valuable.

The **monitor's specific 5-second-poll, 2-failure-threshold design** doesn't
carry forward directly either — Kubernetes' probe configuration
(`initialDelaySeconds`, `periodSeconds`) does the equivalent job, but as
declarative configuration rather than an imperative script we wrote and have to
maintain ourselves.

## 4. Hardcoded values in the deployment manifest, and their operational cost

- **The image tag** (`0.1.0-aa9305b`) is hardcoded directly in the manifest.
  Every new release requires editing this file and reapplying it, which means
  the deployment definition and the release process are tightly coupled — there's
  no way to promote a new version without a manifest change.

- **`PORT: "3000"`** is hardcoded as a plain environment variable. If this ever
  needed to differ between environments (a staging cluster running on a
  different port convention, for instance), the manifest itself would need to
  fork or be templated, rather than the same manifest working across
  environments with different configuration supplied separately.

- **The resource requests and limits** (`cpu`, `memory`) are hardcoded numbers
  chosen for this stub's actual footprint. As the real payments logic grows,
  these values will need retuning, and right now that means editing and
  reapplying the deployment rather than adjusting a separate resource
  configuration that could be reviewed and changed independently of the
  application code itself.

- **The registry address** (`localhost:5000/docker-kijanikiosk/...`) is baked
  into the image field. If the registry ever moves — a real concern here, since
  this project's registry is a local Nexus instance standing in for a proper
  cloud registry — every manifest referencing it needs a manual edit rather than
  a single configuration value changing in one place.

None of these are wrong for a lab-scale project, but each one represents a
place where an operational change currently requires a code-adjacent change
(editing and reapplying a Kubernetes manifest) rather than an isolated
configuration change — which is exactly the problem ConfigMaps and Secrets are
built to solve.
