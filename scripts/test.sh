#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTIO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$QUOTIO_ROOT/.." && pwd)"
DERIVED_DATA_DIR="$REPO_ROOT/.runtime-cache/build/quotio-tests-deriveddata"
LOG_DIR="$REPO_ROOT/.runtime-cache/test_output/quotio-tests"
COVERAGE_DIR="$REPO_ROOT/.runtime-cache/coverage/quotio-tests"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/test_$STAMP.log"

mkdir -p "$DERIVED_DATA_DIR" "$LOG_DIR" "$COVERAGE_DIR"
export LLVM_PROFILE_FILE="$COVERAGE_DIR/default-%p.profraw"

prune_runtime_cache() {
  if [[ -f "$REPO_ROOT/scripts/runtime-prune.sh" ]]; then
    bash "$REPO_ROOT/scripts/runtime-prune.sh" >/dev/null 2>&1 || true
  fi
}
trap prune_runtime_cache EXIT

echo "[1/3] build-for-testing (derivedDataPath=$DERIVED_DATA_DIR)"
xcodebuild \
  -project "$QUOTIO_ROOT/Quotio.xcodeproj" \
  -scheme Quotio \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build-for-testing > "$LOG_FILE" 2>&1

echo "[2/3] prepare runtime dependencies for xctest bundle"
APP_DIR="$DERIVED_DATA_DIR/Build/Products/Debug/Quotio.app"
BUNDLE="$APP_DIR/Contents/PlugIns/QuotioTests.xctest"
PLUGIN_CONTENTS="$BUNDLE/Contents"
PLUGIN_FRAMEWORKS="$PLUGIN_CONTENTS/Frameworks"

if [[ ! -d "$BUNDLE" ]]; then
  echo "Test bundle not found: $BUNDLE" >&2
  exit 1
fi

mkdir -p "$PLUGIN_FRAMEWORKS"
cp -f "$APP_DIR/Contents/MacOS/Quotio.debug.dylib" "$PLUGIN_FRAMEWORKS/"
cp -Rf "$APP_DIR/Contents/Frameworks/Sparkle.framework" "$PLUGIN_FRAMEWORKS/" 2>/dev/null || true


echo "[3/3] run unit tests"
{
  echo "----- xctest output -----"
  xcrun xctest "$BUNDLE"
} | tee -a "$LOG_FILE"

echo "done: $LOG_FILE"
