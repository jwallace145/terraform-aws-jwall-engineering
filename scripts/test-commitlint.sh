#!/usr/bin/env bash
# Runs commitlint against fixture messages and checks each one is accepted or
# rejected as expected. Used by CI and `npm run test:commitlint`.
#
# tests/commitlint/valid/*.txt   must pass
# tests/commitlint/invalid/*.txt must fail
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
run_case() {
  local file="$1" expect="$2" result
  if npx --no-install commitlint < "$file" > /dev/null 2>&1; then
    result=pass
  else
    result=fail
  fi
  if [[ "$result" == "$expect" ]]; then
    printf '  ok    %-5s %s\n' "$expect" "$file"
  else
    printf '  FAIL  expected %s, got %s: %s\n' "$expect" "$result" "$file"
    npx --no-install commitlint < "$file" || true
    fail=1
  fi
}

echo "commitlint fixtures:"
for f in tests/commitlint/valid/*.txt; do run_case "$f" pass; done
for f in tests/commitlint/invalid/*.txt; do run_case "$f" fail; done

if [[ "$fail" -ne 0 ]]; then
  echo "commitlint fixture tests FAILED"
  exit 1
fi
echo "commitlint fixture tests passed"
