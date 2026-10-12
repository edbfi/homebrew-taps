#!/usr/bin/env bash
# Resolver: updater test probes.
#
# The playground holds several probes' releases, so /releases/latest can belong to
# another probe: take the newest published <token>-vX.Y.Z release instead, and
# require the exact asset <prefix>-<version>.dmg at the exact expected URL.

# shellcheck source=SCRIPTDIR/../../scripts/lib/common.sh
source "$(dirname "$0")/../../scripts/lib/common.sh"
load_pipeline "$(basename "$(cd "$(dirname "$0")" && pwd)")"
: "${RESOLVE_OUT:?RESOLVE_OUT (output file) is required}"

status="$(gh_api "repos/${UPSTREAM_REPO}/releases?per_page=100" releases.json)"
require_2xx "${status}" "listing ${UPSTREAM_REPO} releases" releases.json

tag_re="^${CASK_TOKEN}-v[0-9]+\\.[0-9]+\\.[0-9]+\$"
tag="$(jq -r --arg re "${tag_re}" '.[] | select((.draft or .prerelease) | not) | .tag_name | select(test($re))' releases.json |
  LC_ALL=C sort -V | tail -n 1)"
if [[ -z "${tag}" ]]
then
  log "No upstream release found."
  kv "${RESOLVE_OUT}" skip true
  exit 0 # resolvers run in a subshell; this ends only the resolver
fi

version="${tag#"${CASK_TOKEN}"-v}"
expected_name="${ASSET_PREFIX}-${version}.dmg"
download_url="$(jq -er --arg tag "${tag}" --arg name "${expected_name}" \
  '[.[] | select(.tag_name == $tag) | .assets[] | select(.name == $name)] | if length == 1 then .[0].browser_download_url else error("Expected one matching DMG") end' releases.json)"
expected_url="https://github.com/${UPSTREAM_REPO}/releases/download/${tag}/${expected_name}"
[[ "${download_url}" = "${expected_url}" ]] || die "Unexpected DMG download URL: ${download_url} (expected ${expected_url})"
rm -f releases.json

kv "${RESOLVE_OUT}" version "${version}"
kv "${RESOLVE_OUT}" download_url "${download_url}"
kv "${RESOLVE_OUT}" ref "${tag}"
kv "${RESOLVE_OUT}" changes_url "${UPSTREAM_URL}/releases/tag/${tag}"
