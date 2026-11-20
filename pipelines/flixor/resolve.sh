#!/usr/bin/env bash
# Flixor publishes the desktop app and server in the same release feed.
# shellcheck source=SCRIPTDIR/../../scripts/lib/common.sh
source "$(dirname "$0")/../../scripts/lib/common.sh"
load_pipeline "$(basename "$(cd "$(dirname "$0")" && pwd)")"
: "${RESOLVE_OUT:?RESOLVE_OUT (output file) is required}"

releases="$(mktemp)"
trap 'rm -f "${releases}"' EXIT
page=1
while true
do
  status="$(gh_api "repos/${UPSTREAM_REPO}/releases?per_page=100&page=${page}" "${releases}")"
  require_2xx "${status}" "listing ${UPSTREAM_REPO} releases (page ${page})" "${releases}"
  release="$(jq -c 'first(.[] | select(.draft == false and .prerelease == false)
    | select(.tag_name | startswith("macos-v"))) // empty' "${releases}")"
  [[ -z "${release}" ]] || break
  [[ "$(jq length "${releases}")" -eq 100 ]] || die "No stable macos-v release found in ${UPSTREAM_REPO}."
  page=$((page + 1))
done

tag="$(jq -r '.tag_name' <<<"${release}")"
tag_re='^macos-v[0-9]+\.[0-9]+\.[0-9]+$'
[[ "${tag}" =~ ${tag_re} ]] || die "Unexpected upstream tag format: ${tag}"

version="${tag#macos-v}"
name="Flixor-${version}.dmg"
url="${UPSTREAM_URL}/releases/download/${tag}/${name}"
jq -e --arg name "${name}" --arg url "${url}" '
  [.assets[] | select(.name == $name)] | length == 1 and .[0].browser_download_url == $url
' <<<"${release}" >/dev/null || die "Expected exactly one ${name} at ${url}"

kv "${RESOLVE_OUT}" version "${version}"
kv "${RESOLVE_OUT}" download_url "${url}"
kv "${RESOLVE_OUT}" ref "${tag}"
kv "${RESOLVE_OUT}" changes_url "${UPSTREAM_URL}/releases/tag/${tag}"
