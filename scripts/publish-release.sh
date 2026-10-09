#!/usr/bin/env bash
# Attach ASSET_PATH to TOKEN's rolling release and verify the hosted bytes match.
# Published downloads are never replaced, and earlier assets stay in place.
#
# If the release already serves an asset of that name, its bytes must equal
# ASSET_PATH and nothing is changed (a retry publishes nothing twice); different
# bytes fail for review. Otherwise the asset is uploaded and the notes updated.
#
# Usage: scripts/publish-release.sh TOKEN ASSET_PATH NOTES_FILE
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

load_pipeline "${1:?usage: publish-release.sh TOKEN ASSET_PATH NOTES_FILE}"
asset_path="${2:?ASSET_PATH}"
notes_file="${3:?NOTES_FILE}"
asset="$(basename "${asset_path}")"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# hosted_matches — download the hosted asset and compare it with ASSET_PATH.
hosted_matches() {
  rm -rf "${work}/hosted"
  gh release download "${RELEASE_TAG}" --pattern "${asset}" --dir "${work}/hosted"
  cmp -s "${asset_path}" "${work}/hosted/${asset}"
}

if release_json "${RELEASE_TAG}" "${work}/release.json"
then
  count="$(jq --arg name "${asset}" '[.assets[] | select(.name == $name)] | length' "${work}/release.json")"
  if [[ "${count}" -eq 1 ]]
  then
    hosted_matches || die "Hosted ${asset} differs from upstream; review the re-release before updating"
    log "Release ${RELEASE_TAG} already serves identical ${asset}; nothing to publish."
    exit 0
  fi
  [[ "${count}" -eq 0 ]] || die "Release ${RELEASE_TAG} lists ${asset} ${count} times"
  gh release upload "${RELEASE_TAG}" "${asset_path}"
  gh release edit "${RELEASE_TAG}" --title "${RELEASE_TITLE}" --notes-file "${notes_file}"
else
  gh release create "${RELEASE_TAG}" "${asset_path}" \
    --title "${RELEASE_TITLE}" \
    --notes-file "${notes_file}" \
    --latest=false
fi

# The cask URL must resolve, and to these bytes, before any cask names them.
hosted_matches || die "Hosted ${asset} differs from upstream; review the re-release before updating"
log "Rolling release ${RELEASE_TAG} now serves ${asset}."
