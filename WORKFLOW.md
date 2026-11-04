# Contributing to Bamboo Pulse

Base contributions on the public repository's main branch. Describe the user-visible outcome, affected files, failure cases and the checks you ran. Open issues and pull requests through [Bamboo Pulse on GitHub](https://github.com/tongvtdan/Bamboo-Pulse).

1. Reproduce the behavior in Preview or with a temporary fixture. Use a disposable account for setup and recovery testing.
2. Change the owning component. Keep UI changes in the app, validation in PulseCore, and runtime changes with their fixtures.
3. Run the commands in the [README](README.md). For documentation, run `python3 scripts/validate_project.py` and `git diff --check`.
4. Include the tested commit, macOS, Xcode version and any untested paths in the pull request. Obtain maintainer review before merge. Changes to local observation, identifiers, hooks, startup, notifications or permissions require human review.

The macOS workflow builds unsigned and tests both schemes. Documentation validation runs separately. Check actual results on the pull request. Release approval requires separate review of the exact source, dependency notices and artifact, plus a clean-Mac install, first real session and removal check. A pull request does not authorize publishing a release.
