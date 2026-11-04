#!/usr/bin/env bash
set -euo pipefail

MODE=run
CONFIGURATION=Debug
SCHEME="Bamboo Pulse Live"
EXPLICIT_SCHEME=false
DEVELOPER_SIGNING=false
for option in "$@"; do
  case "$option" in
    --live) SCHEME="Bamboo Pulse Live"; EXPLICIT_SCHEME=true ;;
    --preview) SCHEME="Bamboo Pulse Preview"; EXPLICIT_SCHEME=true ;;
    --release) CONFIGURATION=Release ;;
    --signed) DEVELOPER_SIGNING=true ;;
    --build-only|--test|--verify|--logs|--debug) MODE="$option" ;;
    run) MODE=run ;;
    *) echo "usage: $0 [--live|--preview] [--build-only|--test|--verify|--logs|--debug] [--release|--signed]" >&2; exit 2 ;;
  esac
done
if [[ "$DEVELOPER_SIGNING" == true && "$CONFIGURATION" != Debug ]]; then
  echo "--signed is for local Debug builds. Release signing requires its own reviewed workflow." >&2
  exit 2
fi
if [[ "$MODE" == --debug && "$EXPLICIT_SCHEME" == false ]]; then SCHEME="Bamboo Pulse Preview"; fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BAMBOO_PULSE_BUILD_ROOT:-${TMPDIR:-/private/tmp}/bamboo-pulse-xcode-$(id -u)}"
mkdir -p "$BUILD_ROOT"
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd -P)"
APP_BUNDLE="$BUILD_ROOT/Build/Products/$CONFIGURATION/Bamboo Pulse.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Bamboo Pulse"
LEGACY_BINARY="$ROOT_DIR/dist/Bamboo Pulse Debug.app/Contents/MacOS/BambooPulse"
PID_FILE="$ROOT_DIR/dist/debug.pid"
SCHEME_FILE="$ROOT_DIR/BambooPulse.xcodeproj/xcshareddata/xcschemes/$SCHEME.xcscheme"
LAUNCH_ARGUMENT="$(/usr/bin/xmllint --xpath 'string(/Scheme/LaunchAction/CommandLineArguments/CommandLineArgument[@isEnabled="YES"]/@argument)' "$SCHEME_FILE")"
case "$LAUNCH_ARGUMENT" in --live|--preview) ;; *) echo "Invalid scheme launch argument" >&2; exit 2 ;; esac
cd "$ROOT_DIR"

if [[ "$MODE" != --build-only && "$MODE" != --test && -f "$PID_FILE" ]]; then
  PREVIOUS_PID="$(cat "$PID_FILE")"
  if [[ "$PREVIOUS_PID" =~ ^[0-9]+$ ]]; then
    PREVIOUS_BINARY="$(/bin/ps -p "$PREVIOUS_PID" -o comm= || true)"
    case "$PREVIOUS_BINARY" in
      "$BUILD_ROOT/Build/Products/Debug/Bamboo Pulse.app/Contents/MacOS/Bamboo Pulse"|\
      "$BUILD_ROOT/Build/Products/Release/Bamboo Pulse.app/Contents/MacOS/Bamboo Pulse"|\
      "$LEGACY_BINARY") kill "$PREVIOUS_PID" ;;
    esac
  fi
fi

BUILD_ARGS=(-project BambooPulse.xcodeproj -scheme "$SCHEME" -configuration "$CONFIGURATION"
  -destination 'platform=macOS' -derivedDataPath "$BUILD_ROOT"
  -clonedSourcePackagesDirPath "$BUILD_ROOT/SourcePackages")
if [[ "$DEVELOPER_SIGNING" == false ]]; then
  BUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi
if [[ "$MODE" == --test ]]; then
  mkdir -p "$BUILD_ROOT/TestResults"
  exec xcodebuild "${BUILD_ARGS[@]}" -parallel-testing-enabled NO \
    -resultBundlePath "$BUILD_ROOT/TestResults/$(date +%Y%m%d-%H%M%S).xcresult" test
fi
xcodebuild "${BUILD_ARGS[@]}" build
if [[ "$DEVELOPER_SIGNING" == true ]]; then
  /usr/bin/codesign --verify --strict "$APP_BUNDLE"
  SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
  SIGNING_TEAM="$(printf '%s\n' "$SIGNATURE_INFO" | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
  if [[ -z "$SIGNING_TEAM" || "$SIGNING_TEAM" == 'not set' ]]; then
    echo "The build has no signing team. Select your Apple Development team in Xcode's app target." >&2
    exit 1
  fi
  echo "Verified local development signature: team $SIGNING_TEAM"
fi
if [[ "$MODE" == --build-only ]]; then echo "Built $SCHEME ($CONFIGURATION): $APP_BUNDLE"; exit 0; fi
if [[ "$MODE" == --debug ]]; then exec lldb -- "$APP_BINARY" "$LAUNCH_ARGUMENT"; fi
/usr/bin/open -n "$APP_BUNDLE" --args "$LAUNCH_ARGUMENT"
mkdir -p "$ROOT_DIR/dist"
sleep 1
RUNNING_PID="$(/bin/ps -axo pid=,comm= | /usr/bin/awk -v expected="$APP_BINARY" '{ pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == expected) print pid }' | head -1)"
if [[ -n "$RUNNING_PID" ]]; then echo "$RUNNING_PID" > "$PID_FILE"; fi
if [[ "$MODE" == --verify ]]; then
  test -n "$RUNNING_PID"
  COMMAND="$(/bin/ps -p "$RUNNING_PID" -o command=)"
  [[ "$COMMAND" == "$APP_BINARY $LAUNCH_ARGUMENT" ]]
  echo "Verified $SCHEME: PID $RUNNING_PID, $LAUNCH_ARGUMENT"
fi
if [[ "$MODE" == --logs ]]; then
  exec /usr/bin/log stream --info --style compact --predicate 'process == "Bamboo Pulse"'
fi
