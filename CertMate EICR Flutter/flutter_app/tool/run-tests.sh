#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."

flutter_bin="${FLUTTER_BIN:-flutter}"
mkdir -p test-results
stamp=$(date -u '+%Y-%m-%dT%H-%M-%SZ')
run=$(mktemp -d "test-results/${stamp}-XXXXXX")
printf 'Test artifacts: %s/%s\n' "$PWD" "$run"

result=0
stage() {
  local name=$1 status
  shift
  if "$@" > "$run/$name.stdout" 2> "$run/$name.stderr"; then
    status=0
  else
    status=$?
    result=1
  fi
  printf '%s exit code: %s\n' "$name" "$status" | tee -a "$run/summary.txt"
}

printf 'Started (UTC): %s\n' "$(date -u '+%FT%TZ')" > "$run/summary.txt"
stage version "$flutter_bin" --version
stage dependencies "$flutter_bin" pub get
stage analysis "$flutter_bin" analyze --no-pub
mkdir -p "$run/screenshots"
flutter_executable=$(command -v "$flutter_bin" || printf '%s' "$flutter_bin")
flutter_bin_dir=$(dirname "$flutter_executable")
font_dir="${FLUTTER_SCREENSHOT_FONTS:-$flutter_bin_dir/cache/artifacts/material_fonts}"
stage tests "$flutter_bin" test --no-pub --machine --reporter expanded \
  --dart-define="CERTMATE_SCREENSHOT_FONTS=$font_dir" \
  --dart-define="CERTMATE_SCREENSHOTS=$PWD/$run/screenshots" \
  --file-reporter "expanded:$run/tests.txt" --coverage \
  --coverage-path "$run/lcov.info"
stage review python3 tool/test-report.py "$run"
printf 'Finished (UTC): %s\nOverall exit code: %s\n' "$(date -u '+%FT%TZ')" "$result" | tee -a "$run/summary.txt"
exit "$result"
