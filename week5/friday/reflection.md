# Week 5 Friday Reflection — Capstone

## What "production-grade" actually meant, in practice

Going into today, the brief's five requirements (Docker agent, parallel
Verify, correct post conditions, credential management, fault-injected
reliability) looked like five separate boxes to check. In practice, four of
them were already done by Wednesday and Thursday — today was almost entirely
about the fifth (Lint stage + full 5-row fault table) and about proving the
other four still held together as a single system rather than four
independent pieces. That distinction matters: a pipeline that passes five
requirements individually is not the same as a pipeline that's been run
end-to-end, faulted five separate ways, and confirmed to recover correctly
every time. The individual pieces were solid all week; today was about
verifying the composition.

## The one real surprise: faults move when the pipeline changes shape

Adding the Lint stage today silently relocated where the "Build fault"
(a lockfile-mismatched dependency) actually surfaces — it now fails inside
Lint, because `npm ci` moved there, not because anything about the
dependency-resolution failure mode itself changed. This wasn't caught by
reading the Jenkinsfile; it was only caught by re-running the exact same
fault and watching it land somewhere different than expected. This is
probably the single best argument for why fault injection has to be redone
after any structural pipeline change, not just trusted from a prior week's
run — the *category* of failure (dependency resolution) is stable, but the
*stage* that owns it moved, and only a live rerun exposes that.

## What changed between Thursday and Friday's pipeline that wasn't planned

Two things emerged from actually implementing today's requirements rather
than just describing them:

1. Archiving the `npm audit` JSON output (closing Thursday's Principle 4 gap)
   initially leaked that file — and, it turned out, `Jenkinsfile` and the
   test files too, unnoticed since Monday — into the published npm package
   itself. A `.npmignore` fixed it, but the bug existed for four days before
   a file literally named "audit" made it visible. Nothing in the fault
   injection table this week would have caught this on its own, because
   every fault this week tests whether a stage *fails correctly* — none of
   them test whether a *successful* stage produced clean output. That's a
   real gap in this week's testing philosophy worth carrying forward: green
   builds need their own scrutiny, not just red ones.

2. `post.changed` never fired once until today, despite being in the
   Jenkinsfile since Wednesday, simply because the pipeline had been green
   on every single run until the first Lint fault. A condition that's never
   observed firing is functionally unverified, regardless of how correct it
   looks in the source. Fault injection this week ended up doubling as the
   only real test of `post.changed` — ten transitions observed across five
   faults and their reverts, every one correct.

## What the capstone actually proves, versus what it can't

The pipeline is provably reliable at the boundary it operates within: it
builds, lints, tests, audits, packages, versions, and publishes correctly,
and it fails safely and visibly at every one of those steps when something
is wrong. What it cannot prove — and what no CI pipeline can prove on its
own — is that the code is *correct* beyond what's been written a test for,
or that a dependency is safe beyond what's already been publicly disclosed.
Both Thursday's reflection and today's `.npmignore` incident point at the
same underlying truth: a pipeline that's fully green is a pipeline that's
passed every check someone thought to write, which is a meaningfully weaker
claim than "the software is correct." The board doc says this directly, in
its own "what this does not do" section, because Nia's presentation should
not overstate what five days of CI work actually guarantees.
