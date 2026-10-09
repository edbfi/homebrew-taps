#!/usr/bin/env bash
# Run pipelines/TOKEN/resolve.sh and print validated key=value lines for
# GITHUB_OUTPUT.
#
# A resolver is an executable script. It loads lib/common.sh and its own
# config.env itself (see any pipelines/*/resolve.sh header) and receives GH_TOKEN
# and RESOLVE_OUT (a file) from the environment. It must write, via
# `kv "$RESOLVE_OUT" KEY VALUE`:
#   skip          true|false  (true = nothing to do this run, e.g. upstream not published yet)
#   version       the cask version string
#   download_url  where the DMG (or a zip containing it) is fetched from
#   ref           upstream tag or commit, shown in release notes
#   changes_url   link shown under "Changes" in release notes
#   archive_member (optional) path of the DMG inside a downloaded zip
#
# This driver adds: asset, cask_file, release_tag, release_title, display_name.
#
# Usage: scripts/resolve.sh TOKEN
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

load_pipeline "${1:?usage: resolve.sh TOKEN}"

RESOLVE_OUT="$(mktemp)"
export RESOLVE_OUT
: >"${RESOLVE_OUT}"

# shellcheck disable=SC1090,SC1091
bash "${PIPELINE_DIR}/resolve.sh"

# One record per known key, so a resolver can't override or smuggle a field.
keys="$(cut -d= -f1 "${RESOLVE_OUT}")"
dupes="$(printf '%s\n' "${keys}" | sort | uniq -d)"
[[ -z "${dupes}" ]] || die "Resolver set ${dupes//$'\n'/, } more than once"
while IFS= read -r line
do
  [[ "${line}" =~ ^(skip|version|download_url|ref|changes_url|archive_member)= ]] ||
    die "Unexpected resolver record: ${line}"
done <"${RESOLVE_OUT}"

get() { grep -E "^$1=" "${RESOLVE_OUT}" | cut -d= -f2- || true; }

skip="$(get skip)"
if [[ "${skip}" = "true" ]]
then
  log "Resolver for ${CASK_TOKEN} reported skip=true."
  echo "skip=true"
  exit 0
fi

version="$(get version)"
download_url="$(get download_url)"
[[ -n "${version}" ]] || die "Resolver did not set version"
[[ -n "${download_url}" ]] || die "Resolver did not set download_url"
require_safe_version "${version}"
[[ "${download_url}" =~ ^https://[A-Za-z0-9./_~%+=-]+$ ]] || die "Unexpected download_url: ${download_url}"

archive_member="$(get archive_member)"
if [[ -n "${archive_member}" ]]
then
  member_re='^[A-Za-z0-9._/ -]+$'
  [[ "${archive_member}" =~ ${member_re} ]] || die "Unexpected archive_member: ${archive_member}"
fi

{
  echo "skip=false"
  echo "version=${version}"
  echo "download_url=${download_url}"
  echo "ref=$(get ref)"
  echo "changes_url=$(get changes_url)"
  echo "archive_member=${archive_member}"
  echo "asset=${ASSET_PREFIX}-${version}.dmg"
  echo "cask_file=${CASK_FILE}"
  echo "release_tag=${RELEASE_TAG}"
  echo "release_title=${RELEASE_TITLE}"
  echo "display_name=${DISPLAY_NAME}"
}
