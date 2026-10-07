#!/bin/bash
# Generates the Xcode project and builds the Mac app. Prints only errors,
# warnings from our own sources, and the result.
#
#   ./scripts/build.sh                 # Debug build in .build/main
#   ./scripts/build.sh release         # Release build, copied to build/Clipnote.app
#   ./scripts/build.sh test            # anything else goes to xcodebuild (default: build)
#   ./scripts/build.sh bench [test]    # Whisper load and speed benchmarks (ModelLoadBenchmark)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -s Models/Whisper/model/VARIANT ]; then
  echo "The Whisper model is missing. Run ./scripts/fetch-models.sh first."
  exit 1
fi

CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-$ROOT/.build/main}"
RELEASE=0
if [ "${1:-}" = "bench" ]; then
  # ./scripts/build.sh bench [testName]
  shift
  export TEST_RUNNER_CLIPNOTE_BENCH=1
  TARGET="ClipnoteTests/ModelLoadBenchmark"
  if [ -n "${1:-}" ]; then TARGET="$TARGET/$1()"; shift; fi
  set -- test "-only-testing:$TARGET" "$@"
fi
if [ "${1:-}" = "release" ]; then
  shift
  RELEASE=1
  CONFIG=Release
  DERIVED="$ROOT/.build/release"
fi
mkdir -p "$DERIVED"
LOG="$DERIVED/build.log"
ACTION=("$@")
[ ${#ACTION[@]} -eq 0 ] && ACTION=(build)

xcodegen generate --quiet || exit 1

xcodebuild -project Clipnote.xcodeproj -scheme Clipnote -configuration "$CONFIG" \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation -skipMacroValidation \
  "${ACTION[@]}" >"$LOG" 2>&1
STATUS=$?

grep -E "^$ROOT/(Clipnote|ClipnoteTests)/.*(error|warning):" "$LOG" | sort -u
grep -E "^(error|fatal error):|Test .*(passed|failed)|recorded an issue|✘|✔ Test run|^BENCH " "$LOG" | sort -u | head -80
if [ $STATUS -eq 0 ] && [ $RELEASE -eq 1 ]; then
  mkdir -p build
  rm -rf build/Clipnote.app
  cp -R "$DERIVED/Build/Products/Release/Clipnote.app" build/
  echo "App: $ROOT/build/Clipnote.app"
fi
if [ $STATUS -eq 0 ]; then echo "SUCCEEDED (${ACTION[*]})"; else echo "FAILED (full log: $LOG)"; fi
exit $STATUS
