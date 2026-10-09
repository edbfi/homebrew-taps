#!/usr/bin/env bash
# Decide whether TOKEN needs an update. Prints key=value lines for GITHUB_OUTPUT:
#   previous_version, needed, reason
#
# An update is needed only when upstream is newer than the cask (sort -V; edbfi-ci
# design/d8.md rule 10). Failures, for a human to look at:
#   - upstream differs from the cask but isn't newer (a downgrade, or an
#     unorderable version such as a same-day Paicord build);
#   - the cask is current but its rolling release or asset is missing: restore the
#     hosted file by hand, since the updater never republishes an old version;
#   - GitHub can't be asked (anything but a 404 for a missing release).
#
# Usage: scripts/check-update.sh TOKEN NEW_VERSION ASSET
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

load_pipeline "${1:?usage: check-update.sh TOKEN NEW_VERSION ASSET}"
new_version="${2:?NEW_VERSION}"
asset="${3:?ASSET}"

current_version="$(cask_version "${REPO_ROOT}/${CASK_FILE}")"
log "Cask ${CASK_TOKEN}: current=${current_version} upstream=${new_version} asset=${asset}"
echo "previous_version=${current_version}"

if [[ "${current_version}" != "${new_version}" ]]
then
  version_newer "${new_version}" "${current_version}" ||
    die "Upstream ${new_version} is not newer than ${current_version} (sort -V); update ${CASK_TOKEN} by hand"
  echo "needed=true"
  echo "reason=version changed"
  exit 0
fi

tmp="$(mktemp)"
release_json "${RELEASE_TAG}" "${tmp}" || die "Rolling release ${RELEASE_TAG} is missing; restore it by hand"
jq -e --arg name "${asset}" '[.assets[] | select(.name == $name)] | length == 1' "${tmp}" >/dev/null ||
  die "Rolling release ${RELEASE_TAG} lacks ${asset}; restore it by hand"
rm -f "${tmp}"
echo "needed=false"
echo "reason=up to date"
