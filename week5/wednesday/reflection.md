# Week 5 Wednesday Reflection

## Q1: Artifact Versioning Under Real Team Conditions

With `PKG_VERSION-GIT_SHORT` versioning, Developer A's build produces
`1.0.0-a3f2c8b` and Developer B's produces `1.0.0-b7d9e2a` — different commits
give different short SHAs even if `package.json` hasn't been bumped, so the two
artifacts never collide as long as the commits themselves differ, which they
do by definition once both are merged. Today's own build confirmed this in
practice: two separate commits to the same unbumped `0.1.0` package produced
`0.1.0-597eb46` and `0.1.0-a895fdf`, both landing in Nexus without conflict.
With `Disable redeploy` set, Developer A's publish of `1.0.0-a3f2c8b` and
Developer B's publish of `1.0.0-b7d9e2a` do not conflict either, because
Nexus's immutability enforcement operates on the exact version string, not on
the base semver. Immutability would only block a *second* publish attempt
under the *same* version string — for example, if Developer A rebuilt and
republished without a new commit, producing an identical `1.0.0-a3f2c8b` a
second time. The SHA suffix is what makes every build's version string unique
per commit; two different commits essentially can't produce the same version
string by accident.

## Q2: The withCredentials Masking Limit

Jenkins masks the literal password string but not derived forms of it — the
exact scenario I hit today was different but adjacent: I based64-encoded
`NEXUS_USER:NEXUS_PASS` into `NEXUS_TOKEN`, and when that variable name
appeared in the log (`NEXUS_TOKEN=YWRtaW46****`), Jenkins still masked the
password portion correctly because it scans for the literal credential value
anywhere it appears in the output stream, not just in variables tagged as
credentials. The genuinely dangerous version of this — the one the question is
asking about — is if the *token itself* were echoed somewhere Jenkins doesn't
know to scan, e.g. written to a file that later gets `cat`'d in a *different*
stage outside the `withCredentials` block, or passed to an external API that
logs its inputs on the far end. Jenkins can't mask what happens outside its
own log stream. The defence is scope discipline: never let a credential or its
transformed form leave the `withCredentials` block's lifetime — the `.npmrc`
file in today's pipeline is deleted via `trap "rm -f .npmrc" EXIT` specifically
so it can't be read, cat'd, or archived in any later stage. That trap is the
actual enforcement point, not the masking itself.

## Q3: The Immutability Requirement

Immutability prevents a specific, quiet failure mode: version `1.2.3` gets
published, some downstream system (Week 7's CD pipeline, or a teammate) pulls
and deploys it, and later someone republishes a *different* artifact under
the same `1.2.3` label — maybe a hotfix that skipped the version bump, or a
CI retry that silently rebuilt with different dependency resolution. Every
system that already has `1.2.3` cached, deployed, or referenced in a ticket
now disagrees about what `1.2.3` actually contains, and there is no way to
detect this from the version number alone. This is dangerous specifically in
multi-team setups because Team A might deploy the old bytes while Team B pulls
the new ones, and a rollback to "known-good 1.2.3" becomes meaningless once
the label itself is ambiguous. Today's setup used `Allow redeploy` to simplify
first-time repository creation; production must use `Disable redeploy` so a
second publish attempt under an existing version string fails loudly instead
of overwriting silently.

## Q4: Credential Rotation

When the Nexus password rotates: in **Nexus**, generate the new password for
the `admin` (or dedicated deploy) user. In **Jenkins**, edit the existing
`nexus-credentials` entry in the credentials store and update the password
value — the credential ID stays `nexus-credentials`. In the **Jenkinsfile**,
nothing changes at all, because the file only ever references the ID string,
never the actual username or password. This is the entire point of the
`credentialsId` indirection: the Jenkinsfile is a pointer to a credential, not
a container for one. The separation is valuable because the Jenkinsfile lives
in version control and is reviewed via PRs — if rotation required editing the
Jenkinsfile, every credential rotation would need a code review and a merge,
turning a routine security operation into a development task with a review
queue. Keeping rotation entirely inside the Jenkins credentials store means it
can happen on a security team's schedule independent of the deployment
pipeline's release cadence.
