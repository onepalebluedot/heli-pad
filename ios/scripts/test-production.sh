#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/helipad-tests.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT
swiftc -O -parse-as-library \
  HeliPad/HeliPad/Domain/*.swift \
  HeliPad/HeliPad/Services/*.swift \
  HeliPad/HeliPad/App/AppConfig.swift \
  HeliPad/HeliPad/Core/Theme/TimeFormat.swift \
  HeliPad/HeliPad/Features/Go/GoViewModel.swift \
  Tests/ProductionRegressionTests.swift \
  -o "$output_dir/production-tests"
"$output_dir/production-tests"
