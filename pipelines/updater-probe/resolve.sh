#!/usr/bin/env bash
# Resolver: Updater Probe.
#
# Reads /releases/latest of the playground and requires the exact asset
# UpdaterProbe-<version>.dmg at the exact expected URL.

# shellcheck source=SCRIPTDIR/../../scripts/lib/common.sh
source "$(dirname "$0")/../../scripts/lib/common.sh"
load_pipeline "$(basename "$(cd "$(dirname "$0")" && pwd)")"
: "${RESOLVE_OUT:?RESOLVE_OUT (output file) is required}"

status="$(gh_api "repos/${UPSTREAM_REPO}/releases/latest" release.json)"
if [[ "${status}" = "404" ]]
then
  log "No upstream release found."
  kv "${RESOLVE_OUT}" skip true
  exit 0 # resolvers run in a subshell; this ends only the resolver
fi
require_2xx "${status}" "fetching latest ${UPSTREAM_REPO} release" release.json

tag="$(jq -r '.tag_name // empty' release.json)"
tag_re='^updater-probe-v[0-9]+\.[0-9]+\.[0-9]+$'
[[ "${tag}" =~ ${tag_re} ]] || die "Unexpected upstream tag format: ${tag}"

version="${tag#updater-probe-v}"
expected_name="${ASSET_PREFIX}-${version}.dmg"
download_url="$(jq -er --arg name "${expected_name}" \
  '[.assets[] | select(.name == $name)] | if length == 1 then .[0].browser_download_url else error("Expected one matching DMG") end' release.json)"
expected_url="https://github.com/${UPSTREAM_REPO}/releases/download/${tag}/${expected_name}"
[[ "${download_url}" = "${expected_url}" ]] || die "Unexpected DMG download URL: ${download_url} (expected ${expected_url})"
rm -f release.json

kv "${RESOLVE_OUT}" version "${version}"
kv "${RESOLVE_OUT}" download_url "${download_url}"
kv "${RESOLVE_OUT}" ref "${tag}"
kv "${RESOLVE_OUT}" changes_url "${UPSTREAM_URL}/releases/tag/${tag}"
