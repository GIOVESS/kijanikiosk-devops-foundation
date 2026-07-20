# Week 5 Friday — Reflection

## Q1: Where two requirements were in tension

Thursday's implementation of the Principle 4 improvement (archiving the
`npm audit` output for diagnostic visibility) directly conflicted with
Requirement 2's demand for a clean, correctly-versioned artifact: archiving
`audit-report.json` caused it to be included inside the *published npm
package itself*, alongside the Jenkinsfile and test files that had been
leaking in unnoticed since Monday. The tension was between "give developers
full diagnostic visibility into every run" and "ship only what belongs in
the artifact" — and improving one directly broke the other, silently, until
a file literally named "audit" made the leak visible in the Publish stage's
tarball-contents log. I prioritized fixing the artifact cleanliness
immediately (via `.npmignore`) over keeping the audit report inside the
package, because Requirement 2's artifact-correctness guarantee is the more
fundamental promise this pipeline makes — diagnostic files belong in
Jenkins' own archived artifacts, not inside what gets published to
production consumers of the package.

## Q2: Same sentence, two audiences

**Board version:** "Once a version is stored under that label, it can never
be quietly replaced by something else with the same name."

**Technical version (Jenkinsfile comment / conversation with Osei):** "The
`npm-kijanikiosk` Nexus repository currently has `writePolicy: ALLOW` for
this week's lab setup; in production this would be `writePolicy` set to
disable redeploy, so a second `npm publish` attempt against an existing
`<semver>-<git-sha>` version is rejected by Nexus with a `403`, rather than
silently overwriting the existing blob."

**Same in both:** the underlying guarantee — a published version, once it
exists, cannot be silently replaced. **Different:** the technical version
names the actual mechanism (`writePolicy`, `ALLOW` vs. disabled redeploy,
the specific HTTP rejection), while the board version states only the
outcome and its consequence, with zero implementation detail. The board
doesn't need to know *how* immutability is enforced, only that it is.

## Q3: What breaks first at 4 → 40 developers

`disableConcurrentBuilds()` in the `options` block. Osei flagged this
directly on Wednesday: this setting doesn't queue simultaneous builds, it
*cancels* the second one outright. At four developers, two people pushing
within the same build window is rare enough to be a non-issue. At forty,
with commits landing constantly across many feature branches, builds would
start getting silently dropped multiple times a day — a developer would
push, see no corresponding build ever run, and have no idea their change was
never verified at all. This needs to change to a real queuing strategy
(Jenkins' default build queue behavior, or an explicit
`throttleJobProperty` if concurrent builds sharing the same Docker agent
network become a resource problem) so that every push is eventually built,
in order, rather than some pushes being silently skipped. The underlying
cause is that `disableConcurrentBuilds()` was a reasonable simplification
for a four-person team's collision rate, not a setting anyone chose because
it was correct at scale — it was correct for the team size that existed
when it was written, which is exactly the kind of assumption that breaks
first as a team grows.
