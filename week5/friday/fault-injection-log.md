# Fault Injection Log — kk-payments-ci (Friday, 6-stage pipeline)

Five faults injected, one at a time, each observed then reverted before the
next. Raw logs for each are in `fault-injection-lint.txt`,
`fault-injection-build.txt`, `fault-injection-test.txt`,
`fault-injection-archive.txt`, `fault-injection-publish.txt`.

| Stage faulted | Fault introduced | Expected behaviour | Observed? |
|---|---|---|---|
| Lint | Added unused variable to `index.js` | Build, Verify, Archive, Publish all skip | **Y** — real `no-unused-vars` ESLint error; everything downstream skipped; `post.changed` fired (green→red) |
| Build | Added nonexistent dependency to `package.json`, mismatched with lockfile | Verify, Archive, Publish all skip | **Y** — but landed in the **Lint** stage, since `npm ci` now runs there, not Build (structural consequence of adding Lint as the first stage — documented in the fault log) |
| Test (in Verify, parallel) | Deliberate failing assertion | Security Audit runs to completion; Archive, Publish skip | **Y** — Test failed (1/6), Security Audit completed independently in the same run (`AUDIT_EXIT=0`), confirming no `failFast`; Archive and Publish skipped |
| Archive | Artifact pattern changed to a nonexistent directory | Publish skips; artifact never produced | **Y** — Lint, Build, and both Verify branches all succeeded; Archive was the sole failure point; Jenkins even suggested the likely correct pattern in its own error message |
| Publish | Wrong `credentialsId` | Archive ran; artifact in Jenkins but not in Nexus | **Y** — Lint, Build, Verify, and Archive all succeeded with fingerprinting; Publish failed at credential resolution before any Nexus network call |

## Cross-cutting observations

- **`post.changed` fired correctly on every single transition** — green→red for
  each of the five faults, and red→green for each of the five reverts (10
  transitions total, all captured in individual build logs #39–48).
- **A structural surprise**: "faulting the Build stage" in the brief's sense
  (breaking `npm ci`) now surfaces in the Lint stage, because Lint became the
  pipeline's first stage and absorbed the `npm ci` step. This is exactly the
  kind of thing fault injection is meant to catch — a design change elsewhere
  in the pipeline silently moved where a known failure mode actually
  manifests, and only re-running the fault confirmed it.
- Every fault was introduced and reverted in its own isolated commit; no two
  faults were ever combined, per Osei's rule.
- SCM polling fired at least one build automatically mid-sequence (build #46,
  "Started by an SCM change"), confirming the trigger still works after a
  full week of pipeline changes.
