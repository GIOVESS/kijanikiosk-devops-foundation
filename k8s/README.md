
## Deviation: Image source for kk-payments

The brief specifies pulling `your-registry/kk-payments:v1.1.0` from the Nexus
registry via `--insecure-registry`. During this exercise, repeated pull attempts
triggered Nexus's built-in rate-limiting (HTTP 429 "Too many authentication
attempts"), which did not clear even after fixing the underlying credential
issue and waiting several minutes — the retry storm from replica pods
re-triggered the lockout faster than it could clear.

Workaround: the image was built directly into Minikube's node-local Docker
daemon via `eval $(minikube docker-env)`, tagged `your-registry/kk-payments:v1.1.0`
to match the manifest, with `imagePullPolicy: Never` set in the Deployment.
No registry pull occurs for this deployment.

Production path: the Nexus registry flow (push, insecure-registry config,
imagePullSecrets) was proven working in Week 8 and is still the intended
production mechanism — a docker-registry Secret (`nexus-registry-cred`) was
created and is documented below in case the registry path is re-enabled.
