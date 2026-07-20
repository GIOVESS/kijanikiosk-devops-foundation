# Week 5 Thursday Reflection

## Q1: Docker Agent Isolation in Depth

If `kk-payments-stub` needed `libvips` and the current `node:18-alpine` image
lacks it, three approaches, quickest to most maintainable:

1. **Modify the Dockerfile** — write a custom Dockerfile `FROM node:18-alpine`
   that adds `RUN apk add --no-cache vips-dev`, build and push it to a
   registry, then point `agent { docker { image 'my-org/node-vips:18' } }` at
   it. Disadvantage: introduces a new artifact (the custom image) that itself
   needs a build/publish pipeline and version management — exactly the
   problem this week's Nexus work solved for the application artifact, now
   duplicated for the build environment.

2. **Use a different base image** — switch to a Debian-based Node image
   (`node:18-bullseye`) that either ships `libvips` or has apt access to
   install it inline as an early pipeline step (`sh 'apt-get install -y
   libvips-dev'`). Quicker than building a custom image, but reintroduces
   exactly the "environment declared vs inherited" problem this whole day was
   about — the install step runs fresh every single build, adding time and
   depending on the Debian mirror being reachable and unchanged.

3. **Mount a volume with the library pre-installed** — use `args '-v
   /opt/vips-libs:/usr/lib/vips'` to bind-mount a pre-built library directory
   from the host into the container. Fastest to implement (no rebuild, no
   apt call), but ties the pipeline to a specific host's filesystem layout —
   it would break immediately on any other Jenkins agent, defeating the
   entire purpose of declaring the environment in the Jenkinsfile rather than
   inheriting it from wherever the pipeline happens to run.

Most maintainable long-term: option 1, despite the extra overhead, because it
keeps the full build environment declared and versioned exactly like the
application artifact itself.

## Q2: Parallel Stage Design Decisions

Adding an 8-minute integration-test branch to the parallel Verify stage would
violate the 10-minute rule immediately: today's entire pipeline runs in
roughly 30-45 seconds end to end (confirmed in `pipeline-design-review.md`),
and even though parallel branches run concurrently rather than adding their
times together, the Verify stage's total time equals its *longest* branch —
so an 8-minute integration suite would make Verify alone take roughly 8
minutes regardless of how fast Test and Security Audit are individually. The
correct architecture is a separate, non-blocking pipeline that runs on a
different trigger — not on every push, but on merge to `develop` or on a
schedule. The specific Jenkins mechanism is a second Pipeline job with its own
trigger configuration (e.g. an SCM-poll or webhook scoped to `develop` merges
only, rather than every feature-branch commit), keeping the fast feedback
loop (this week's `kk-payments-ci` job) separate from slow comprehensive
checks that developers don't need to wait on before continuing work.

## Q3: The Week as a Complete System

**For Nia (plain language, no jargon):** When someone finishes a change to
the payments code and shares it, a computer picks it up automatically,
double-checks the code builds correctly and passes every test we've written
for it, scans it for known security problems, and — only if every one of
those checks passes — packages it up, labels it with a version number, and
stores it somewhere safe where it's ready to be installed. If any check
fails, everything stops right there and nothing gets stored, so what's saved
is only ever code that's been fully verified.

**For Tendo (full technical specificity):** A Jenkins declarative pipeline
triggers via SCM polling on push to the tracked branch. The build runs inside
a pinned `node:18-alpine` Docker agent, isolating the runtime from whatever
Node version happens to be installed on the Jenkins controller. Sequential
stages are Build (`npm ci`, `npm run build`, output verification) → Verify
(parallel: Jest test suite with JUnit reporting, and `npm audit
--audit-level=high`) → Archive (`archiveArtifacts` with fingerprinting) →
Publish (versioned as `semver + git-short-SHA`, authenticated via Jenkins'
`withCredentials` against a Nexus hosted npm repository over the shared
Docker network `kk-ci-net`). Failure at any stage halts the sequence via
Jenkins' default fail-fast stage semantics; `post.always` blocks guarantee
workspace cleanup and diagnostic artifact retention regardless of outcome.

**Same in both:** the sequence and the "stop on failure" guarantee. **Different:**
Nia's version has no proper nouns for tools (Jenkins, Docker, Nexus are all
just "a computer" / "somewhere safe"), no version-string mechanics, and no
mention of the underlying network/container architecture — none of which
changes what the board needs to know, which is simply that nothing broken can
reach production silently.

## Q4: What the Pipeline Cannot Prevent

**Category 1 — logic errors the tests don't cover.** The pipeline is fully
green whenever `npm test` passes, but that only proves the five assertions
written in `index.test.js` are true — it says nothing about business logic
paths nobody thought to test. A bug in, say, currency rounding that no test
exercises would sail through every stage. This is caught by code review and
by expanding test coverage over time, not by CI — CI can only run the tests
that exist; it cannot invent tests for scenarios nobody anticipated.

**Category 2 — supply-chain compromise in a dependency that has no known
CVE yet.** `npm audit --audit-level=high` only flags vulnerabilities already
in the advisory database. A malicious or compromised package version
published today, with no advisory filed yet, passes the audit cleanly and
gets published to Nexus with a green pipeline. This is caught by dependency
pinning discipline, manual review of new dependencies before they're added,
and periodic re-scanning after advisories are eventually filed — none of
which belongs inside the CI pipeline itself, because CI runs at commit time
against a database that is necessarily incomplete for anything not yet
publicly known.
