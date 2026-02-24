#!/usr/bin/env bash
set -euo pipefail

EXIT_PASS=0
EXIT_FAIL=1
EXIT_PREFLIGHT=2
EXIT_TIMEOUT=124

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUOTIO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$QUOTIO_ROOT/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$QUOTIO_ROOT/Quotio.xcodeproj}"
SCHEME="${XCODE_SCHEME:-Quotio}"
DESTINATION="${XCODE_DESTINATION:-platform=macOS}"
CONFIGURATION="${XCODE_CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/.runtime-cache/build/quotio-xcode-test-stable-deriveddata}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$REPO_ROOT/.runtime-cache/test_output/quotio-xcode-test-stable/$STAMP"
LOG_FILE="$RUN_DIR/xcode-test.log"
SUMMARY_FILE="$RUN_DIR/result-summary.txt"
PREFLIGHT_LOG="$RUN_DIR/preflight.log"

mkdir -p "$RUN_DIR" "$DERIVED_DATA_PATH"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG_FILE"
}

preflight() {
  : > "$PREFLIGHT_LOG"
  echo "project=$PROJECT_PATH" >> "$PREFLIGHT_LOG"
  echo "scheme=$SCHEME" >> "$PREFLIGHT_LOG"
  echo "destination=$DESTINATION" >> "$PREFLIGHT_LOG"
  echo "configuration=$CONFIGURATION" >> "$PREFLIGHT_LOG"
  echo "derived_data=$DERIVED_DATA_PATH" >> "$PREFLIGHT_LOG"
  echo "timeout_seconds=$TIMEOUT_SECONDS" >> "$PREFLIGHT_LOG"

  command -v xcodebuild >/dev/null 2>&1 || {
    echo "xcodebuild not found" | tee -a "$PREFLIGHT_LOG"
    return "$EXIT_PREFLIGHT"
  }

  command -v python3 >/dev/null 2>&1 || {
    echo "python3 not found" | tee -a "$PREFLIGHT_LOG"
    return "$EXIT_PREFLIGHT"
  }

  [[ -d "$PROJECT_PATH" ]] || {
    echo "project path not found: $PROJECT_PATH" | tee -a "$PREFLIGHT_LOG"
    return "$EXIT_PREFLIGHT"
  }

  if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT_SECONDS" -le 0 ]]; then
    echo "invalid TIMEOUT_SECONDS: $TIMEOUT_SECONDS" | tee -a "$PREFLIGHT_LOG"
    return "$EXIT_PREFLIGHT"
  fi

  xcodebuild -version >> "$PREFLIGHT_LOG" 2>&1
  xcodebuild -list -project "$PROJECT_PATH" >> "$PREFLIGHT_LOG" 2>&1
}

write_summary() {
  local status="$1"
  local exit_code="$2"
  {
    echo "status=$status"
    echo "exit_code=$exit_code"
    echo "log_file=$LOG_FILE"
    echo "preflight_log=$PREFLIGHT_LOG"
    echo "timeout_seconds=$TIMEOUT_SECONDS"
    echo "timestamp=$STAMP"
  } > "$SUMMARY_FILE"
}

run_test_with_timeout() {
  python3 - "$TIMEOUT_SECONDS" "$LOG_FILE" "$PROJECT_PATH" "$SCHEME" "$DESTINATION" "$CONFIGURATION" "$DERIVED_DATA_PATH" <<'PY'
import os
import select
import signal
import subprocess
import sys
import time

timeout_seconds = int(sys.argv[1])
log_file = sys.argv[2]
project = sys.argv[3]
scheme = sys.argv[4]
destination = sys.argv[5]
configuration = sys.argv[6]
derived_data = sys.argv[7]

cmd = [
    "xcodebuild",
    "-project", project,
    "-scheme", scheme,
    "-configuration", configuration,
    "-destination", destination,
    "-derivedDataPath", derived_data,
    "test",
]

deadline = time.time() + timeout_seconds

def emit(handle, text):
    handle.write(text)
    handle.flush()
    sys.stdout.write(text)
    sys.stdout.flush()

with open(log_file, "a", encoding="utf-8", errors="replace") as log:
    emit(log, "=== xcode-test-stable: command ===\n")
    emit(log, " ".join(cmd) + "\n")
    emit(log, f"timeout_seconds={timeout_seconds}\n")
    emit(log, "=== xcode-test-stable: output ===\n")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )

    assert proc.stdout is not None
    fd = proc.stdout.fileno()

    timed_out = False
    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            timed_out = True
            break

        wait_for = min(1.0, max(0.05, remaining))
        ready, _, _ = select.select([fd], [], [], wait_for)
        if ready:
            chunk = os.read(fd, 4096)
            if chunk:
                emit(log, chunk.decode("utf-8", errors="replace"))

        rc = proc.poll()
        if rc is not None:
            while True:
                ready_tail, _, _ = select.select([fd], [], [], 0)
                if not ready_tail:
                    break
                tail = os.read(fd, 4096)
                if not tail:
                    break
                emit(log, tail.decode("utf-8", errors="replace"))
            emit(log, f"\n=== xcode-test-stable: finished rc={rc} ===\n")
            sys.exit(rc)

    if timed_out:
        emit(log, "\n=== xcode-test-stable: timeout reached, terminating process ===\n")
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        emit(log, "=== xcode-test-stable: forced timeout exit ===\n")
        sys.exit(124)
PY
}

main() {
  : > "$LOG_FILE"
  log "run_dir=$RUN_DIR"

  if ! preflight; then
    local rc=$?
    write_summary "preflight-fail" "$rc"
    log "preflight failed (exit=$rc)"
    log "summary=$SUMMARY_FILE"
    exit "$rc"
  fi

  log "preflight passed"
  log "starting xcodebuild test with timeout=${TIMEOUT_SECONDS}s"

  set +e
  run_test_with_timeout
  local rc=$?
  set -e

  case "$rc" in
    0)
      write_summary "pass" "$EXIT_PASS"
      log "result=pass"
      ;;
    124)
      write_summary "timeout" "$EXIT_TIMEOUT"
      log "result=timeout"
      ;;
    *)
      write_summary "fail" "$EXIT_FAIL"
      log "result=fail (xcodebuild_exit=$rc)"
      rc="$EXIT_FAIL"
      ;;
  esac

  log "summary=$SUMMARY_FILE"
  log "log_file=$LOG_FILE"
  exit "$rc"
}

main "$@"
