# Fault Injection Log — kk-payments-ci

Three faults injected, one at a time, each observed then reverted before
the next. Full raw logs for each are in `fault-injection-build.txt`,
`fault-injection-test.txt`, `fault-injection-publish.txt`.

| Stage faulted | Fault introduced | Expected behaviour | Observed? |
|---|---|---|---|
| Build | Added `this-package-does-not-exist-anywhere@^99.99.99` to `package.json`, mismatched with `package-lock.json` | Verify, Archive, Publish all skip | **Y** — `npm ci` failed with `E404`; Verify, Archive, Publish all showed "skipped due to earlier failure(s)"; `post.always cleanWs` still ran |
| Test (in Verify, parallel) | Deliberate failing assertion `expect(1+1).toBe(3)` in `index.test.js` | Security Audit runs to completion; Archive, Publish skip | **Y** — Test failed (1/6 tests), Security Audit completed independently in the same run (`found 0 vulnerabilities`), confirming `failFast` is not set; Archive and Publish both skipped |
| Publish | Wrong `credentialsId` (`wrong-credential-id` instead of `nexus-credentials`) | Archive ran; artifact in Jenkins but not in Nexus | **Y** — Build, Verify (both branches), and Archive all succeeded with artifact fingerprinted; Publish failed immediately at credential resolution (`Could not find credentials entry with ID 'wrong-credential-id'`), no Nexus network call attempted |

## Scope note on the brief's 4-row table

The brief's reference table (from the Fault Injection page) includes a fourth
row for a Lint stage fault. This pipeline has no separate Lint stage — Build's
fail-fast position (first in sequence) already catches syntax/dependency
errors for this minimal service, and adding a Lint stage purely to complete
the table would be artificial rather than a genuine engineering decision.
This is documented as a deliberate scope choice, not an oversight.

## Cross-cutting observations

- Every fault correctly triggered `post.always` blocks (`cleanWs`, and for the
  Test fault, `junit` results recording) regardless of pipeline failure —
  confirming Principle 4 (diagnostic output available on failure) holds for
  at least the Test branch; the Security Audit branch has no equivalent
  `post.always`, flagged separately in `pipeline-design-review.md`.
- All three faults were introduced and reverted via separate, isolated
  commits — no fault was ever combined with another, per Osei's rule against
  accumulating multiple faults simultaneously.
- SCM polling correctly triggered at least one of these builds automatically
  (build 30, "Started by an SCM change"), confirming the Monday-established
  trigger mechanism still works after four days of pipeline changes.
