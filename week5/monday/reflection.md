# Week 5 Monday Reflection

## Q1: What's missing for this to be "real" CI?

Today's pipeline proves the mechanical link between a git push and an automated
build, but it stops short of real CI in several ways. There is no test suite
running yet — the pipeline only checks that Node and npm are present, not that
the application behaves correctly. There is no build artifact produced or
archived, so a passing pipeline currently proves nothing about deployability.
Feedback also isn't immediate: SCM polling checks every 5 minutes rather than
triggering the instant a commit lands, so the "immediate feedback" property of
CI is only approximated here, not achieved. Finally, this pipeline runs against
a single feature branch manually pointed to in the job config — real CI
integrates continuously against a shared integration branch (develop), and
today's setup doesn't yet prove that multiple developers' changes converge
without conflict. Today establishes the trigger mechanism; the actual
verification content comes Tuesday.

## Q2: Broken-build contract exception scenario

The broken-build contract says a failing build blocks everything downstream —
no merge, no deploy, no exceptions — because a red build means the codebase is
in an unknown state. The one legitimate exception is a build failure caused by
infrastructure outside the code itself: for example, if the Jenkins container's
Docker daemon becomes unreachable, or GitHub has an outage during the fetch
step, the build fails but the code the developer pushed may be perfectly valid.
In that case, the team can document the infrastructure failure, verify manually
that the code passes tests locally, and proceed with a recorded exception
rather than blocking work on a Jenkins-side outage. This is different from
skipping the contract for convenience — the exception exists only when the
build's red status demonstrably does not reflect the code's correctness.

## Q3: Why Jenkinsfile-in-repo, not Jenkins UI

Storing the pipeline definition in `Jenkinsfile` inside the repository means the
build process is versioned exactly like the code it builds. If a Jenkinsfile
change breaks the pipeline, `git log` and `git diff` show exactly what changed
and when, and reverting the code revert also reverts the pipeline logic that
went with it. A pipeline defined only in the Jenkins UI has no such history —
changes are invisible to anyone not looking directly at the Jenkins job
configuration, and there's no way to see what the pipeline looked like for a
build three months ago. It also means every branch can carry its own pipeline
definition: this repo's `feature/week5-monday-jenkins-ci` branch's Jenkinsfile
is independent of `develop`'s, which matters when experimenting with pipeline
changes without affecting the main branch's builds.

## Q4: Webhook vs. polling tradeoff at scale

Polling checks for changes on a fixed interval regardless of whether anything
happened, which wastes resources on quiet repos and adds latency up to the
polling interval before a build starts — in today's setup, up to 5 minutes.
Webhooks push notifications immediately when a change occurs, so builds start
within seconds of a commit, and there's no wasted polling overhead on idle
repos. At scale, on a team with many repos and frequent commits, webhooks are
the only approach that scales cleanly — polling every repo every few minutes
multiplies load on both Jenkins and the git host as team and repo count grow.
Today's setup uses polling not by choice but because this Jenkins instance runs
in a Docker container on a host-only VirtualBox network, unreachable from
GitHub's servers. In a real deployment reachable from the internet (or via a
reverse proxy/tunnel), webhooks would be the correct choice.
