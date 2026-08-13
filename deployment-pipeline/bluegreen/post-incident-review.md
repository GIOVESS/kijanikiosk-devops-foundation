# Post-Incident Review: Wrong-Environment Deployment During Investor Demo

## Section 1: Incident Summary

During an investor walkthrough, the deployment pipeline sent traffic to the wrong
version of the application. Visitors trying to reach the staging site got errors
for about 48 seconds until the team switched back to the correct version by hand.
No customer data was affected and no payment was processed incorrectly — the
outage was limited to the demo environment being briefly unreachable.

## Section 2: Timeline (reconstructed — see note on estimation basis)

All timestamps below are **estimated**, reconstructed from the incident narrative
rather than pulled from real logs, since this incident is a hypothetical scenario
for this exercise rather than an event with retained evidence. Basis for each
estimate is noted inline, following the pattern in Challenge C.

| Time (estimated) | Event | Basis for estimate |
|---|---|---|
| 09:10 (est., ±2 min) | Investor walkthrough begins; team starts narrating the live pipeline demo | Narrative states the incident occurred "during" the walkthrough |
| 09:14 (est., ±1 min) | Engineer triggers a deployment/switch intended for a secondary or scratch environment, but the target passed to the switch step resolves to the environment currently live in the demo | Root cause section below; this is the triggering action |
| 09:15 (est., ±1 min) | The proxy begins returning errors, based on the narrative stating errors appeared within about a minute of the trigger | Consistent with the brief's own example estimation pattern for this exact incident |
| 09:15:30–09:16 (est.) | Team notices the demo environment is unreachable, mid-walkthrough | Narrative implies real-time visibility of the failure during the demo |
| 09:16 (est., ±30s) | Engineer manually re-runs the switch, targeting the correct environment this time | No automated rollback existed for this incident — this predates `post-deploy-monitor.sh`, which is the whole reason this project exists |
| 09:16:48 (est.) | Correct environment confirmed live again via manual health check | 48-second unavailability window per the incident summary, applied against the 09:16 recovery start |

**Total unavailability**: ~48 seconds, matching the stated incident impact.

## Section 3: Root Cause (four whys)

**Why did the demo environment go down?**
Because the deployment pipeline switched traffic to a version of the application
that was not ready to serve the demo audience.

**Why did the pipeline switch to the wrong version?**
Because the engineer running the deployment passed a target environment name that
did not match the environment the investors were actually looking at. The switch
command itself executed successfully — it did exactly what it was told.

**Why did the pipeline accept a target that didn't match the live demo context?**
Because the switch mechanism (`switch-env.sh`, in this project's implementation)
only validates that the target string is one of the two valid values (`blue` or
`green`). It has no concept of "which environment is currently being watched by
an audience" or "which environment is the demo-safe one right now." Any
syntactically valid target is accepted and executed immediately, with no
confirmation step and no environment-context check.

**Why does the switch mechanism have no context-awareness or confirmation step?**
Because the switch script was designed to solve the technical problem (move
traffic from A to B cleanly, verify health, update state files) and correctness
was defined entirely in terms of "does the target exist and become healthy." It
was never designed against the failure mode of a human choosing the *technically
valid but contextually wrong* target during a live, audience-facing moment. That
gap — no distinction between a routine switch and a switch during an
observed, high-stakes window — is the structural finding: the tooling has no
concept of operational context, only of destination validity.

**Root cause (structural)**: The deployment switch mechanism validates *that* a
target is a legitimate environment, but not *whether* switching to it right now,
in this context, is safe. There is no confirmation gate, no "demo mode" lock, and
no distinction between an ordinary deployment and one happening while a live
audience is watching a specific environment.

## Section 4: Contributing Factors

- No environment-lock or "do not switch" flag exists that could have been set
  for the duration of the investor demo.
- The switch script runs immediately on a valid target with no dry-run,
  confirmation prompt, or preview of what would change.
- There was no automated rollback at the time of this incident (this project's
  `post-deploy-monitor.sh` is the direct response to that gap) — recovery
  depended entirely on a human noticing the failure and manually correcting it.
- No pre-demo checklist step existed to confirm "which environment and version
  is currently live" immediately before starting a live walkthrough.

## Section 5: What Went Well

The team detected the problem quickly during the walkthrough itself — the
narrative indicates the failure was visible in real time, not discovered after
the fact from a customer complaint or a delayed metrics alert. The manual
recovery, while slow relative to the 90-second automated target this project
now meets, was still fast enough (48 seconds) that the incident was resolved
within the same demo session rather than requiring it to be rescheduled.

## Section 6: Action Items

1. **Owner: Engineering lead (Osei's role).** Add a target-confirmation step to
   `switch-env.sh` that prints the current active environment and the proposed
   target, and requires an explicit `--yes` flag (or interactive confirmation)
   before executing when run outside of the automated pipeline context.
   **Timeframe: next sprint.**

2. **Owner: Whoever is running a live demo.** Add a "demo lock" file
   (e.g. `/opt/kijanikiosk/.demo-lock`) that, when present, causes
   `switch-env.sh` to refuse any switch and exit with an explicit error naming
   the lock, until the lock is manually removed. Set it as the first step of any
   investor-facing or customer-facing walkthrough. **Timeframe: before the next
   scheduled demo.**

3. **Owner: On-call engineer / whoever owns the deployment pipeline.** Extend
   `post-deploy-monitor.sh`'s automated rollback coverage (currently triggers on
   consecutive health-check failure) to also run continuously during any window
   flagged as a live demo, regardless of whether a deployment was just
   performed — so a wrong-environment switch during a demo gets caught and
   auto-corrected the same way a bad release does today. **Timeframe: within
   two sprints, after the demo-lock mechanism in item 2 is in place.**

4. **Owner: Engineering lead.** Document a pre-demo checklist (active
   environment, version, health status, demo-lock engaged) as a required step
   before any investor or customer-facing walkthrough, stored alongside
   `demo-script.md`. **Timeframe: before the next scheduled demo.**
