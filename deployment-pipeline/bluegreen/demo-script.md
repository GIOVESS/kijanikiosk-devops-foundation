# Demo Script: Automated Deployment Recovery

**Audience**: Board members (non-technical)
**Reader**: Nia
**Format**: Stage directions in brackets, spoken lines follow

---

[Nia stands near the screen. The dashboard shows the current live version of the
payments service.]

"What you're about to see is how we protect the checkout experience when we
release a change. Right now, our customers are being served by our current,
stable version of the payment system."

[Engineer starts the deployment. A new version begins running alongside the old
one, not yet serving customers.]

"We're bringing up a new version of the software. It's running right now, but no
customer traffic is going to it yet — think of it as warming up backstage before
it steps on stage."

[Engineer runs the switch. The dashboard updates to show the new version now
live.]

"Now we move all customer traffic over to the new version. This is the moment a
normal release happens — customers are now using the new software."

[Engineer introduces a deliberate failure into the new version.]

"To prove our safety net actually works, we're now going to break the new
version on purpose — the same way a real bug might."

[The monitoring system detects the failure. The dashboard flips back to the
previous version automatically.]

"Watch the screen. Nobody is touching a keyboard right now. The system noticed
the new version was unhealthy and switched customers straight back to the version
we know works, on its own."

[Dashboard confirms the previous version is live again and healthy.]

"That recovery just happened in six seconds — faster than a person could have
even opened their laptop, let alone diagnosed the problem. That's the difference
between a customer noticing a hiccup and a customer noticing an outage. This is
what lets us release improvements confidently, knowing that if something goes
wrong, the system protects the business before a human even has to react."

---

**Spoken word count**: 216
**Acronyms in spoken sections**: none
**Rollback time cited**: 6 seconds (matches `rollback-evidence.txt`, T0 09:00:49 → T2 09:00:55)
