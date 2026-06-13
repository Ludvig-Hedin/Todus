#!/usr/bin/env bash
# Runs the email model decode-tolerance regression tests against the REAL
# TodusMac/Domain/EmailModels.swift, without needing an Xcode test target.
#
# Covers the "errors when entering email threads" regression: a single malformed
# message / null sender must not abort the whole-thread decode.
#
# Usage: ./scripts/run-email-decode-tests.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS="$DIR/../TodusMac/Domain/EmailModels.swift"
RUNNER="$DIR/email-decode-tests/main.swift"
OUT="$(mktemp -d)/email-decode-tests"

swiftc -o "$OUT" "$MODELS" "$RUNNER"
"$OUT"
