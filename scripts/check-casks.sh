#!/usr/bin/env bash
# Native cask checks (macOS): tap this checkout as edbfi/taps, require that
# every Casks/**/<token>.rb loads under its token, then run brew readall,
# brew style and brew audit --cask. Fails if they change a tracked file.
#
# Usage: scripts/check-casks.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${root}"
# shellcheck source=SCRIPTDIR/lib/tap.sh
source scripts/lib/tap.sh
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1

tap_checkout "${root}"

# macOS runners ship Bash 3.2: no mapfile.
tokens=()
while IFS= read -r token
do
  tokens+=("${token}")
done < <(find Casks -type f -name '*.rb' -exec basename {} .rb \; | sort)
[[ "${#tokens[@]}" -gt 0 ]] || {
  echo "ERROR: no casks found" >&2
  exit 1
}
expected="$(printf '%s\n' "${tokens[@]}" | jq -R . | jq -cs sort)"

brew readall --no-simulate edbfi/taps
loaded="$(brew info --json=v2 --cask "${tokens[@]/#/edbfi/taps/}" | jq -c '[.casks[].token] | sort')"
if [[ "${loaded}" != "${expected}" ]]
then
  echo "ERROR: the tap loads ${loaded}, but Casks/**/*.rb holds ${expected}" >&2
  exit 1
fi
brew style edbfi/taps
brew audit --cask --tap edbfi/taps
git diff --exit-code
echo "Casks OK: ${tokens[*]}"
