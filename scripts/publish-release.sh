#!/usr/bin/env bash
# Upsert the rolling release for TOKEN with ASSET_PATH attached, verify the
# asset is present afterwards, preserve all existing release assets.
#
# Existing assets with the same name are left in place (the checksum in the cask
# was computed from the freshly downloaded upstream file, so a stale re-hosted
# copy must be deleted by hand before re-running).
#
# Usage: scripts/publish-release.sh TOKEN ASSET_PATH NOTES_FILE
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

load_pipeline "${1:?usage: publish-release.sh TOKEN ASSET_PATH NOTES_FILE}"
asset_path="${2:?ASSET_PATH}"
notes_file="${3:?NOTES_FILE}"
asset="$(basename "${asset_path}")"

if gh release view "${RELEASE_TAG}" --json assets --jq '.assets[].name' >existing-assets.txt 2>/dev/null
then
  if grep -Fxq "${asset}" existing-assets.txt
  then
    log "Release ${RELEASE_TAG} already contains ${asset}; leaving the existing asset in place."
  else
    gh release upload "${RELEASE_TAG}" "${asset_path}" --clobber
  fi
  gh release edit "${RELEASE_TAG}" --title "${RELEASE_TITLE}" --notes-file "${notes_file}"
else
  gh release create "${RELEASE_TAG}" "${asset_path}" \
    --title "${RELEASE_TITLE}" \
    --notes-file "${notes_file}" \
    --latest=false
fi

# The cask URL must resolve after this step.
if ! gh release view "${RELEASE_TAG}" --json assets --jq '.assets[].name' | grep -Fxq "${asset}"
then
  die "Release ${RELEASE_TAG} does not contain ${asset} after upload."
fi

# Never propose a checksum for bytes different from the hosted download.
verify_dir="$(mktemp -d)"
trap 'rm -rf "${verify_dir}"' EXIT
gh release download "${RELEASE_TAG}" --pattern "${asset}" --dir "${verify_dir}"
cmp -s "${asset_path}" "${verify_dir}/${asset}" || die "Hosted ${asset} differs from upstream; review the re-release before updating"

# Preserve published assets while generated cask PRs await manual review.

log "Rolling release ${RELEASE_TAG} now serves ${asset}."
