# Dependencies and notices

The native app uses Apple frameworks and the PulseCore Swift package in this repository. Preview and Swift tests do not require a Python download.

## Interpreter for an Apple silicon bundle

Use CPython 3.11.15, python-build-standalone build 20260602, aarch64-apple-darwin, PGO + LTO, full archive. The full archive contains the interpreter and its distribution notices. [Upstream release](https://github.com/astral-sh/python-build-standalone/releases/tag/20260602) · [Exact archive](https://github.com/astral-sh/python-build-standalone/releases/download/20260602/cpython-3.11.15%2B20260602-aarch64-apple-darwin-pgo%2Blto-full.tar.zst)

SHA-256 is `a04567046dafa60fb75c07054f8c2a8203127689ae5d1c5b8a681ac5e4e28ace`. The [packager](../Runtime/pulse-runtime/package.py) verifies this before extraction. It copies the upstream license directory into `PulseRuntime/licenses/python-distribution/`, keeps the CPython standard-library license, and includes Bamboo Pulse's MIT notice. Third-party components retain their original terms. No Python distribution is vendored in the source repository.

For a binary release, check the final bundle inventory against the component notices, including libraries that the interpreter loads. Record the source revision, archive digest, exact output digest and supported host. Each additional architecture needs its own verified package.
