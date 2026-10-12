#!/usr/bin/env bash
# List the pipeline packages of one kind as JSON: {"cask":["a","b"],"matrix":[...]}
# or {"formula":[...]}. Every pipelines/<token>/ directory whose PACKAGE_KINDS
# includes the kind (default cask) is one entry. Pass a token to select only it.
# matrix is the cask updater's job matrix (cask_matrix in lib/common.sh).
#
# Usage: scripts/discover.sh [TOKEN] [cask|formula]
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

filter="${1:-}"
kind="${2:-cask}"
[[ "${kind}" = cask || "${kind}" = formula ]] || die "Expected cask or formula"
casks=()

for dir in "${REPO_ROOT}"/pipelines/*/
do
  cask="$(basename "${dir}")"
  PACKAGE_KINDS=cask
  # shellcheck disable=SC1091
  source "${dir}/config.env"
  [[ ",${PACKAGE_KINDS}," = *",${kind},"* ]] || continue
  load_pipeline "${cask}" "${kind}" >/dev/null
  if [[ -z "${filter}" ]] || [[ "${filter}" = "${cask}" ]]
  then
    casks+=("${cask}")
  fi
done

[[ "${#casks[@]}" -gt 0 ]] || die "No pipeline matches '${filter}'"
if [[ "${kind}" = cask ]]
then
  matrix="$(cask_matrix "${casks[@]}")"
else
  matrix=null
fi
printf '%s\n' "${casks[@]}" | jq -R . |
  jq -cs --arg kind "${kind}" --argjson matrix "${matrix}" '{($kind): .} + if $matrix then {matrix: $matrix} else {} end'
