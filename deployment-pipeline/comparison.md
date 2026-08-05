# Comparing Our Two Deployment Approaches

## For Nia — reviewed before the board presentation

We now have two working ways to release changes to the payments service safely,
and it's worth being clear about what each one actually gives us, because they
solve overlapping problems in different ways.

The first approach, blue/green switching, runs two full copies of the
application side by side on the same machine. One copy serves customers, the
other sits ready. Releasing a change means starting the new copy, checking it's
healthy, then flipping a switch so traffic moves to it. If something goes wrong,
we watch the new copy closely for the first minute, and if it starts failing, the
system automatically flips traffic back to the previous copy without anyone
touching a keyboard. We proved this happens in seconds, not minutes.

The second approach, containers on a cluster, packages the application into a
small, self-contained unit that can be started, stopped, and replaced
automatically by a management system. Instead of two copies on one machine, we
run multiple identical copies that the cluster watches continuously. If one copy
becomes unhealthy or disappears, the cluster notices and starts a fresh one
without any human involvement, and without needing us to have set up a switch or
a monitor in advance — that behavior is built into how the cluster manages
everything running on it.

### Where they overlap, and where they differ

| Concern | Blue/Green (VMs) | Containers (Kubernetes) |
|---|---|---|
| How a new version goes live | A traffic switch moves all customer requests from one running copy to another, coordinated by a script we wrote and control directly. | A new set of containers is created and gradually replaces the old set, coordinated by the cluster's own release process rather than a custom script. |
| How a bad release is caught and reversed | A dedicated watcher checks the new copy's health for a set window after the switch and automatically reverts traffic if it fails, using logic we built specifically for this purpose. | The cluster continuously checks whether each running copy is healthy and simply stops sending it traffic and replaces it if it isn't — this is a standing capability of the cluster, not something built for this specific release. |
| What happens when something unexpectedly disappears | Nothing recovers on its own outside of a deployment event; an unexpected crash of the live copy is not something our current scripts watch for continuously. | The cluster is always watching. We proved this by deliberately removing a running copy without warning, and a replacement was up and healthy in well under a minute, with no release in progress and no human noticing first. |
| Growing to handle more traffic | Scaling means provisioning another machine and repeating the whole setup by hand — a real amount of manual work each time. | Scaling to more copies of the application is a one-line change; the cluster handles placing and starting the additional copies itself. |

### Two numbers worth sitting with

The self-healing test — deliberately removing a running copy of the application
without any release in progress — showed the cluster detecting the loss and
bringing a healthy replacement online in 31 seconds, with zero manual steps.

Separately, packaging the application efficiently made a real difference in
size: the straightforward way of building the container came out to about 410
megabytes. Rebuilding it more carefully, stripping out everything not needed to
actually run the application, brought that down to under 43 megabytes — roughly
a 90% reduction. Smaller means faster to move around, faster to start, and less
surface area for something to go wrong inside it.

### What this doesn't solve yet, and what's next

Neither approach yet handles a specific and important case: distinguishing a
version that's genuinely broken from one that's just slow to start up. Right
now, both systems make a judgment based on a simple health check, which is a
reasonable first line of defense but not a nuanced one. A service that's healthy
but temporarily overwhelmed looks the same, to both systems, as one that's
truly broken.

The container approach also currently keeps configuration values like ports and
resource limits written directly into the deployment files themselves. That's
fine at our current scale, but it means changing a setting requires editing and
reapplying the deployment itself, rather than adjusting a separate, more
carefully controlled piece of configuration. The next phase of this work
introduces a proper way to separate that configuration from the application
definition, which will make changes safer and more auditable without touching
the core deployment setup at all.

For now, both systems do what we need them to do today: catch a bad release and
recover from it faster than a person could, with real, measured numbers behind
that claim rather than an estimate.
