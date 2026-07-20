# KijaniKiosk Payments Pipeline — Board Summary

## What this is

When a developer finishes a change to the payments code, a computer picks it
up automatically and runs it through a series of checks before that code is
ever allowed to be used anywhere. If any check fails, the process stops
immediately and nothing gets shipped. If every check passes, the finished
package is stored somewhere safe, labeled with a version number, ready to be
installed.

## What gets checked, in order

1. **Style and correctness** — the code is scanned for obvious mistakes and
   inconsistent formatting before anything else happens, because these are
   the cheapest problems to catch early.
2. **Build** — the code is assembled into a runnable package.
3. **Two checks at once** — the package is tested against every scenario
   we've written a test for, and separately scanned for known security
   vulnerabilities in anything it depends on. These run side by side to save
   time.
4. **Packaging** — once everything above has passed, the finished package is
   labeled with a permanent, unique version number and a record of it is
   kept.
5. **Publishing** — the labeled package is uploaded to a secure storage
   system, ready for the next stage (installing it on a live server) to pick
   it up later.

## Why this matters

- **Nothing broken reaches the storage system.** A single failed check at any
  point halts the entire process — there is no partial or "good enough"
  outcome.
- **Every version is permanent.** Once a version is stored, it can never be
  silently replaced or overwritten. If something goes wrong later, we can
  always point to the exact version that was running and roll back to a
  previous one with total confidence about what's in it.
- **No passwords or secrets are ever visible**, not in the code, not in any
  log a developer could read. We verified this with five separate checks
  this week, and all five passed.
- **We deliberately broke the process five different ways** — bad code style,
  a missing dependency, a failing test, a missing file, and a wrong password
  — to prove it stops correctly every single time, not just when everything
  goes right.

## What this does not do (yet)

This process catches every problem we've thought to test for. It does not
catch business logic mistakes nobody wrote a test for, and it does not catch
a compromised dependency that hasn't been publicly reported yet. Those are
caught by code review and by keeping our test coverage current — no automated
process can substitute for either.

## Bottom line

The payments code that reaches our storage system this week has been checked
five separate ways, is permanently version-labeled, and can be traced back to
the exact commit and moment it was built. Nothing gets there by accident.
