#!/usr/bin/env bash
# Resolver: qBittorrent's stable desktop DMG (not the lt20 variant or CLI).

# shellcheck source=SCRIPTDIR/../../scripts/lib/common.sh
source "$(dirname "$0")/../../scripts/lib/common.sh"
load_pipeline "$(basename "$(cd "$(dirname "$0")" && pwd)")"
: "${RESOLVE_OUT:?RESOLVE_OUT (output file) is required}"

status="$(gh_api "repos/${UPSTREAM_REPO}/releases/latest" release.json)"
if [[ "${status}" = "404" ]]
then
  log "No upstream release found."
  kv "${RESOLVE_OUT}" skip true
  exit 0
fi
require_2xx "${status}" "fetching latest ${UPSTREAM_REPO} release" release.json

jq -e '.draft == false and .prerelease == false' release.json >/dev/null || die "Expected a stable published release."
tag="$(jq -r '.tag_name // empty' release.json)"
tag_re='^release-[0-9]+\.[0-9]+\.[0-9]+$'
[[ "${tag}" =~ ${tag_re} ]] || die "Unexpected upstream tag format: ${tag}"

version="${tag#release-}"
expected_name="qbittorrent-${version}.dmg"
# Exclude lt20, signatures, sources and builds for other platforms.
count="$(jq --arg name "${expected_name}" '[.assets[] | select(.name == $name)] | length' release.json)"
[[ "${count}" -eq 1 ]] || die "Expected exactly one ${expected_name} asset in ${tag}, found ${count}."
download_url="$(jq -r --arg name "${expected_name}" '.assets[] | select(.name == $name) | .browser_download_url' release.json)"
expected_url="https://github.com/${UPSTREAM_REPO}/releases/download/${tag}/${expected_name}"
[[ "${download_url}" = "${expected_url}" ]] || die "Unexpected DMG download URL: ${download_url} (expected ${expected_url})"
rm -f release.json

kv "${RESOLVE_OUT}" version "${version}"
kv "${RESOLVE_OUT}" download_url "${download_url}"
kv "${RESOLVE_OUT}" ref "${tag}"
kv "${RESOLVE_OUT}" changes_url "${UPSTREAM_URL}/releases/tag/${tag}"
