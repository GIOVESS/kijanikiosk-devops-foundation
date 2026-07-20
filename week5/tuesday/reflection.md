# Week 5 Tuesday Reflection

## Q1: What does the red/green proof actually demonstrate?

The deliberate failure test proved that a broken build genuinely stops the
pipeline rather than just logging a warning and continuing. When the test
`expect(1 + 1).toBe(3)` failed, the Test stage went red, its `post.always`
block still ran (junit results were recorded even though the stage failed —
this is the "diagnostic output on failure" principle in practice), and the
Archive stage was explicitly skipped with the message "Stage 'Archive' skipped
due to earlier failure(s)." This confirms Jenkins' default behaviour: a failed
stage halts the sequential chain, and no artifact from a broken build reaches
the archive. Reverting the test and rerunning produced a clean green build with
all three stages passing and artifacts fingerprinted. Without this proof, a
"passing" pipeline would be an assumption rather than a verified property.

## Q2: `npm ci` vs `npm install` — the team-drift scenario

Locally, both commands produced nearly identical timing (~3.2s vs ~3.4s) on a
warm cache, so the difference isn't really about speed in a small project —
it's about correctness guarantees. `npm ci` deletes `node_modules` first and
installs strictly from `package-lock.json`, failing immediately if the lockfile
and `package.json` are out of sync. `npm install` will silently update the
lockfile to resolve any mismatch. In CI, this matters because a lockfile drift
that `npm install` would quietly paper over is exactly the kind of thing a
pipeline should catch and fail loudly on — if one developer bumps a dependency
version locally without regenerating the lockfile correctly, `npm ci` in
Jenkins will fail the Build stage with a clear error, while `npm install` would
have installed a different dependency tree than what's actually committed,
masking a real discrepancy between what's declared and what gets deployed.

## Q3: Directory scoping and the multi-service repo layout

Today's real engineering problem wasn't in the brief: `npm ci` initially failed
with `EUSAGE` because Jenkins checks out the entire repository to the workspace
root, but `package-lock.json` only exists under `services/kk-payments-stub/`.
Every `sh` step in the Jenkinsfile runs from the workspace root by default, not
from the Jenkinsfile's own directory. The fix was wrapping every stage's steps
in a `dir("${SERVICE_DIR}")` block to explicitly scope execution. This is a
direct consequence of keeping `kk-payments-stub` as a subdirectory inside the
main `kijanikiosk-devops-foundation` repo instead of giving it its own
repository — the brief's assumption of a single-service `kijanikiosk-payments`
repo doesn't carry the same requirement. This scoping pattern will need to
extend to every future stage (Publish on Wednesday, Docker agent config on
Thursday) since nothing about the workspace root changes as the pipeline grows.

## Q4: What Wednesday's Nexus stage will need from today

Today's Archive stage proves the artifact exists and is fingerprinted, but it
only stores the artifact inside Jenkins itself — accessible through the build
record, not through any external system. Wednesday's requirement is to publish
that same `dist/` output to a real artifact registry (Nexus) with a proper
version string, which means the Build stage's output becomes an input to a new
Publish stage rather than the pipeline's final product. The `dir()` scoping
pattern established today carries forward unchanged, and the `BUILD_DIR`/
`SERVICE_DIR` environment variables already in place mean Wednesday's stage
can reuse the same conventions rather than introducing new ones.
