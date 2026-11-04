# Bamboo Pulse

Bamboo Pulse is a macOS menu-bar app for following Codex Desktop sessions. See which sessions are working, which need a response, and which have ended. Select a live session to open its chat when the feed provides a valid destination.

**Author** · [Dantino](https://dantino.vn) · [MIT license](LICENSE)

## Try Preview

Use a Mac with Xcode and a Swift 6 toolchain. The app targets macOS 14 or later. From a clone of this repository, run the following command and click the Bamboo Pulse icon in the menu bar.

```sh
./script/build_and_run.sh --preview
```

Preview shows labeled sample sessions. It needs no monitoring setup or developer signing identity. To debug in Xcode, open `BambooPulse.xcodeproj`, select **Bamboo Pulse Preview**, and run. The Swift package builds the core library only.

## Live monitoring

The Live scheme reads a compatible local feed. A plain Xcode build does not bundle the monitoring runtime. Without a feed, Live reports its unavailable state. A packaged app can offer optional setup for Codex Desktop observation. Enabling it changes the current user's shell profile and Codex hooks. Review setup, removal and recovery before testing on an account you use.

## Develop

```sh
swift test
./script/build_and_run.sh --preview --test
./script/build_and_run.sh --live --test
./script/build_and_run.sh --release --build-only
```

Start with [contributor workflow](WORKFLOW.md) for checks and [behavior and architecture](SPEC.md) for source ownership. Report a bug with your macOS version, the scheme and a minimal reproduction using sample data. Keep chat contents and local session identifiers out of public reports.

## Work on the monitoring runtime

[Runtime](Runtime/) contains the Python monitor, local feed, setup and packaging sources. The packaging command supports Apple silicon and verifies the SHA-256 of the full CPython 3.11.15 archive before using it. Download the archive once and set `PULSE_PYTHON_ARCHIVE` to its absolute path. See [dependency versions and notices](docs/dependencies.md).

To stage a disposable payload, use a new output path. The packaged test suite uses temporary homes and sockets. The observer and its desktop-forwarding test currently expect the Codex CLI bundled inside `/Applications/ChatGPT.app`. Opening a chat also requires the registered Codex app. Preview and the native fixture tests work without those desktop integrations.

```sh
export PULSE_TEST_PAYLOAD="$(mktemp -d)/PulseRuntime"
python3 Runtime/pulse-runtime/package.py --python-archive "$PULSE_PYTHON_ARCHIVE" --output "$PULSE_TEST_PAYLOAD"
python3 -B -m unittest discover -s Runtime/pulse-runtime/tests
```

For a local unsigned image, run the following with a new output filename. A public download requires the separate [release checks](docs/release-checks.md).

```sh
Runtime/pulse-runtime/build-review-dmg.sh "$PULSE_PYTHON_ARCHIVE" "$PWD/Bamboo-Pulse-review.dmg"
```
