# Fault Injection Log — kk-payments-ci (6-stage production pipeline)

Five faults injected, one at a time, each observed then reverted before the
next. Raw logs in `fault-injection-lint.txt`, `fault-injection-build.txt`,
`fault-injection-test.txt`, `fault-injection-archive.txt`,
`fault-injection-publish.txt`.

| Stage faulted | Fault introduced | Observed behaviour | Design rationale |
|---|---|---|---|
| Lint | Unused variable added to `index.js` | Real ESLint `no-unused-vars` error; Build, Verify, Archive, Publish all skipped; `post.changed` fired green→red | Style and correctness are the cheapest problems to catch, so they must fail before any dependency installation or network activity happens downstream |
| Build | Nonexistent dependency added to `package.json`, mismatched with lockfile | `npm ci` failed with `E404` — surfaced in the **Lint** stage specifically, since `npm ci` now runs there; everything downstream skipped | Every later stage depends on a resolved dependency tree existing at all; no verification, packaging, or publish step can produce a meaningful result without one |
| Test (parallel, in Verify) | Deliberate failing assertion | Test failed (1/6); Security Audit completed independently in the same run (`exit 0`, clean); Archive and Publish skipped | Parallel branches must be genuinely independent — letting Security Audit finish even when Test fails gives a developer both diagnostic results in one run instead of a truncated one |
| Archive | Artifact pattern pointed at a nonexistent directory | Lint, Build, and both Verify branches all succeeded; Archive itself was the sole failure; Publish skipped | An artifact that can't be archived should never reach the registry — Archive is the last verification gate before anything leaves the Jenkins workspace |
| Publish | Wrong `credentialsId` | Lint, Build, Verify, and Archive all succeeded with fingerprinting; Publish failed at credential resolution before any Nexus network call | A missing or wrong credential ID is a configuration error and must fail loudly and immediately, not retry silently or partially authenticate |

## Cross-cutting observations

- `post.changed` fired correctly on all 10 transitions this produced (5 faults
  × green→red and red→green), confirming it was never actually verified
  before this exercise despite being present in the Jenkinsfile since
  Wednesday.
- The Build fault relocating into Lint (row 2) is a genuine structural
  finding: adding Lint as the pipeline's first stage silently moved where
  `npm ci` — and therefore dependency-resolution failures — actually
  surfaces. Only caught by re-running the identical fault from Thursday.
- Every fault was introduced and reverted in its own isolated commit; none
  were combined.
