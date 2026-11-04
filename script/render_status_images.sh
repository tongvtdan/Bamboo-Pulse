#!/usr/bin/env bash
# Render documentation artwork from the app views without starting monitoring.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_BUILD="$(mktemp -d)"
trap 'rm -rf "$RENDER_BUILD"' EXIT
cd "$ROOT_DIR"

xcrun swiftc -parse-as-library -emit-module -emit-object -module-name PulseCore \
  -module-cache-path "$RENDER_BUILD/cache" \
  -emit-module-path "$RENDER_BUILD/PulseCore.swiftmodule" \
  Sources/PulseCore/SessionState.swift -o "$RENDER_BUILD/SessionState.o"
xcrun swiftc -parse-as-library -I "$RENDER_BUILD" \
  -module-cache-path "$RENDER_BUILD/cache" \
  "$RENDER_BUILD/SessionState.o" \
  Sources/BambooPulse/Models/BambooMotion.swift \
  Sources/BambooPulse/Views/BambooArtwork.swift \
  Sources/BambooPulse/Views/BambooStatusArtwork.swift \
  script/render_status_images.swift -o "$RENDER_BUILD/render-status-images"
"$RENDER_BUILD/render-status-images" "$ROOT_DIR"
