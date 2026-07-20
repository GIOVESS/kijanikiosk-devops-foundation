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
inside the Publish stage itself, before the outer `cleanWs()` even runs.

## Principle 4: Make diagnostic output available even on failure

**PASS** (upgraded from PARTIAL) — Both Verify branches now have `post.always`
blocks: Test records JUnit results via `junit allowEmptyResults: true`, and
Security Audit runs `npm audit --json > audit-report.json` with a `set +e` /
capture-exit-code / `set -e` / re-raise pattern so the JSON is always written
to disk before the stage's real pass/fail status is honored, then archives it
via `archiveArtifacts allowEmptyArchive: true`.

Implementing this surfaced a real bug, not just a documentation gap: the
audit report initially got included inside the *published npm package itself*
(`npm notice 362B audit-report.json` appeared in the Publish stage's tarball
contents), because nothing told `npm publish` to exclude it. Fixed with a
`.npmignore` excluding `audit-report.json`, `junit.xml`, `Jenkinsfile`,
`*.test.js`, and `jest.config.js` — none of which belong in a published
package. This also retroactively fixed a latent issue present since Monday:
every prior publish this week had been shipping `Jenkinsfile` and the test
files inside the tarball too, just unnoticed until a file with "audit" in the
name made the leak obvious. Confirmed via `npm pack --dry-run` locally and the
actual Publish stage log: tarball now contains only `dist/index.js`,
`dist/package.json`, `index.js`, `package.json`.

## Principle 5: The 10-minute rule

**PASS** — Full pipeline runtime remains roughly 30-45 seconds end to end.
Comfortably under the 10-minute threshold.

## Summary

All 5 principles now fully met. Principle 4's improvement (audit report
archiving) was implemented and, in the process of implementing it, surfaced
and fixed a real artifact-hygiene bug (CI files leaking into the published
npm package) that had existed unnoticed all week — this is the "one
improvement implemented and described" deliverable for Friday.
