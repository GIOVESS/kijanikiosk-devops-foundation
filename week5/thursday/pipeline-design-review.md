# Pipeline Design Review — kk-payments-ci

## Principle 1: Fail fast

**PASS** — Build runs first (fastest failure point: dependency/compile errors),
followed by the parallel Verify stage (Test + Security Audit), then Archive,
then Publish. A syntax error or missing dependency fails in the Build stage
before any time is spent on tests or the network round-trip to Nexus.

One gap: there is no dedicated Lint stage ahead of Build. Today's pipeline
relies on `npm test` to catch syntax errors indirectly (Jest would fail to
even parse a malformed file). A future improvement would add an explicit
`eslint` stage before Build, since lint failures are typically faster to
detect and fix than build/test failures.

## Principle 2: Declare, don't inherit

**PASS** — The Node runtime is now fully declared: `agent { docker { image
'node:18-alpine' } }` pins the exact version, replacing this week's earlier
`agent any` runs that inherited whatever Node was installed on the Jenkins
container itself (which drifted from v18 to v20 partway through the week via
manual `apt-get install nodejs`). Environment variables (`BUILD_DIR`,
`SERVICE_DIR`, `NEXUS_URL`) are all declared in the `environment{}` block.
Credentials are retrieved from the Jenkins store by ID, never inherited from
host environment variables.

## Principle 3: Clean up after every build

**PASS** — `cleanWs()` runs in `post.always`, confirmed in every build log
this week (`[WS-CLEANUP] Deleting project workspace... done`). The `.npmrc`
credential file is also explicitly deleted via `trap "rm -f .npmrc" EXIT`
inside the Publish stage itself, before the outer `cleanWs()` even runs —
belt-and-suspenders cleanup for the one file in the pipeline that actually
contains sensitive material.

## Principle 4: Make diagnostic output available even on failure

**PARTIAL** — `junit allowEmptyResults: true, testResults: 'junit.xml'` runs
in `post.always` for the Test branch, so test results are recorded whether
Test passes or fails. However, the Security Audit branch has no equivalent
`post.always` — if `npm audit` fails, the console log shows the failure, but
there's no structured/archived audit report a developer could review later
without digging through the raw build log. Improvement: pipe `npm audit --json
--audit-level=high > audit-report.json` and archive it via `archiveArtifacts`
in a `post.always` block for that branch.

## Principle 5: The 10-minute rule

**PASS** — Full pipeline runtime today: roughly 30-45 seconds end to end
(Build ~7s including npm ci, Verify parallel branches ~1s each, Archive/Publish
a few seconds). Comfortably under the 10-minute threshold. This is partly a
function of the payments-stub service being intentionally minimal — a real
payments service with a larger dependency tree and broader test suite would
need to be watched carefully as it grows, but there is no reason to add
non-blocking slow checks (integration tests, full security scans) to this
pipeline yet, since nothing currently pushes it anywhere near the limit.

## Summary

4 of 5 principles fully met. Principle 4 improvement identified (audit report
archiving) but not yet implemented — candidate for Friday's "one improvement
implemented and described" requirement.
