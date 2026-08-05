# Week 7 Monday — Strategy Decision Practice

## Scenario 1: Overnight Batch Processor

**Strategy: Rolling (in-place, single instance)**

With one worker VM and no external traffic, blue/green's dual-environment cost buys nothing — the "double cost" trade-off only pays off when it protects live traffic from downtime, and this job has none to protect. The 24-hour rollback tolerance and minimal budget map directly onto rolling's profile in the comparison table: infrastructure cost stays normal (same server updated in place) and slow rollback (re-run the batch with v1.x) is acceptable because the constraint explicitly allows it.

## Scenario 2: User-Facing Authentication Service

**Strategy: Blue/Green**

The non-backwards-compatible JWT change rules out rolling and canary outright — both require mixed-version compatibility per the table, and a v1.x token can't validate against v2.0, so any window with both versions live breaks active sessions. Blue/green's atomic switch produces zero mixed-version exposure and meets the sub-5-minute rollback SLO via a proxy switch-back measured in milliseconds, and the team has already budgeted for the table's stated 2x infrastructure cost during the deployment window.

## Scenario 3: ML Recommendation Engine

**Strategy: Canary**

The requirement to measure actual impact against baseline before full commitment is exactly what canary is for and what blue/green cannot provide (atomic switch = no comparative data window), while the team's tolerance for simultaneous old/new exposure satisfies canary's backwards-compatibility requirement in the table. A comprehensive metrics system is already in place, which is the table's stated precondition for canary being viable at all — without it this would just be a slow rolling deployment with no gate to act on.

**Data to collect during rollout:** click-through rate and p95 latency per model version (v2.8 baseline vs. v3.0 canary), plus request error rate and per-request compute time given v3.0's higher cost profile.

**Go/no-go signal per stage:**
- **10% canary:** proceed to 50% if CTR ≥ baseline and p95 latency stays within SLO; abort (100% back to v2.8) if CTR drops or latency/error rate breaches SLO.
- **50% split:** same checks over a longer window to confirm the signal holds at higher volume before proceeding to 100%.
- **100% v3.0:** decommission v2.8 only after the full-traffic window shows CTR and latency holding steady against the pre-rollout baseline.
