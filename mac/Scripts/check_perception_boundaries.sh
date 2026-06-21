#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

report_failure() {
  echo "boundary violation: $1" >&2
  failures=$((failures + 1))
}

check_only_allowed() {
  local pattern="$1"
  shift
  local allowed=("$@")
  local matches
  matches="$(rg -n "$pattern" Sources Tests Package.swift 2>/dev/null || true)"
  [[ -z "$matches" ]] && return 0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local file="${line%%:*}"
    local ok=0
    for allowed_file in "${allowed[@]}"; do
      if [[ "$file" == "$allowed_file" ]]; then
        ok=1
        break
      fi
    done
    if [[ "$ok" -ne 1 ]]; then
      report_failure "$pattern found in $file"
    fi
  done <<< "$matches"
}

check_no_matches() {
  local pattern="$1"
  local scope="$2"
  local matches
  matches="$(rg -n "$pattern" $scope 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    report_failure "$pattern found in forbidden scope: $matches"
  fi
}

check_only_allowed "SCScreenshotManager|SCShareableContent|import ScreenCaptureKit" \
  "Sources/Perception/ScreenCaptureKitCapturer.swift" \
  "Sources/Perception/SCStreamCapturer.swift" \
  "Sources/Perception/SystemAudioCapture.swift"
check_only_allowed "SCContentFilter|SCStreamConfiguration" \
  "Sources/Perception/ScreenCaptureKitCapturer.swift" \
  "Sources/Perception/SCStreamCapturer.swift" \
  "Sources/Perception/SystemAudioCapture.swift"
check_only_allowed "\\bSCStream\\b" \
  "Sources/Perception/SCStreamCapturer.swift" \
  "Sources/Perception/SystemAudioCapture.swift"
check_only_allowed "CGEventSource\\." \
  "Sources/Perception/CGEventSourceIdleDetector.swift"
check_only_allowed "NSWorkspace\\.shared|screensDidSleepNotification|screensDidWakeNotification|willSleepNotification|didWakeNotification" \
  "Sources/Perception/NSWorkspaceFrontAppDetector.swift" \
  "Sources/Perception/ScreenStateMonitor.swift"
check_only_allowed "CGWindowListCopyWindowInfo" \
  "Sources/Perception/NSWorkspaceFrontAppDetector.swift"
check_only_allowed "IOKit\\.ps|IOPS(CopyPowerSourcesInfo|CopyPowerSourcesList|GetPowerSourceDescription)|ProcessInfo\\.processInfo" \
  "Sources/Perception/PowerMonitor.swift"
check_only_allowed "\\bVision\\b|VNRecognizeTextRequest|VNRecognizedTextObservation|VNImageRequestHandler" \
  "Sources/Perception/OCRTextRecognizer.swift"
check_only_allowed "\\bWhisper\\b" \
  "Sources/Perception/WhisperTranscriber.swift"
check_only_allowed "\\b(print|NSLog)\\s*\\(" \
  "Sources/Perception/FileLogger.swift"

check_no_matches "^import DebugTools\\b" "Sources/Perception"

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

echo "Perception boundary check passed."
