#!/usr/bin/env bash
# Run both offline unittest trees: tests/ (cask rewrite, discovery, publishing)
# and scripts/tests/ (resolvers, formula writer, bottles, GUI harness).
# They fake curl and gh on PATH and need python3, jq and Ruby.
#
# Usage: scripts/test-tooling.sh
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in python3 jq ruby
do
  command -v "${tool}" >/dev/null || {
    printf 'ERROR: %s is required\n' "${tool}" >&2
    exit 1
  }
done

python3 -m unittest discover -s tests
python3 -m unittest discover -s scripts/tests
