# Week 5 Friday — Where Everything Is

**The Jenkinsfile**: a copy is at the repo root (`/Jenkinsfile`) for
visibility. The authoritative copy actively used by the Jenkins job is at
`services/kk-payments-stub/Jenkinsfile` — this repository hosts multiple
weeks of independent coursework (Week 3 hardening, Week 4 IaC, Week 5 CI/CD),
so the pipeline lives inside the service directory it builds, rather than at
the repo root claiming the whole repository as its scope. Both files are
kept identical.

**The running pipeline**: Jenkins and Nexus both run locally on the
development machine (`localhost:8080` and `localhost:8081`), not on a
publicly reachable host, per this course's local-infrastructure constraint
(documented in the top-level `README.md` and in each day's reflection this
week). There is no live URL to click into. What's submitted here is the full
evidence trail of an actual pipeline that ran, end to end, five separate
times with deliberate faults injected and reverted:

- `green-pipeline-run.txt` — full log of the final successful run
- `fault-injection-log.md` + five raw per-fault logs — every stage faulted
  and recovered, with timestamps and build numbers traceable in the logs
- `nexus-versions-screenshot.png` — the Nexus UI showing multiple published,
  uniquely-versioned artifacts
- `credential-audit.txt` — the five required credential-hygiene checks

**The board document**: `ci-pipeline-board-document.md`

**Reflection**: `reflection.md`
