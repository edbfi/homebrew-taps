#!/usr/bin/env bash
# Rewrite the machine-owned "  version" and "  sha256" lines of a cask file and
# verify the result. Fails loudly if the anchored sed did not take effect (the
# old per-repo workflows silently no-op'd in that case) or if the file no longer
# parses as Ruby.
#
# Usage: scripts/write-cask.sh CASK_FILE VERSION SHA256
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

cask_file="${1:?CASK_FILE}"
version="${2:?VERSION}"
sha256="${3:?SHA256}"

require_safe_version "${version}"
[[ "${sha256}" =~ ^[0-9a-f]{64}$ ]] || die "Not a SHA256: ${sha256}"
[[ -f "${cask_file}" && ! -L "${cask_file}" ]] || die "No such cask file: ${cask_file}"
command -v ruby >/dev/null 2>&1 || die "Ruby is required to validate ${cask_file}"
[[ "$(grep -c '^  version "' "${cask_file}")" -eq 1 && "$(grep -c '^  sha256 "' "${cask_file}")" -eq 1 ]] ||
  die "${cask_file} must have exactly one version and one sha256 line"

# No `sed -i`: its syntax differs between GNU and BSD sed, and the old workflows'
# in-place edit could silently no-op. Write to a temp file, then replace.
tmp="$(mktemp)"
sed -e "s/^\(  version \)\".*\"/\1\"${version}\"/" \
  -e "s/^\(  sha256 \)\".*\"/\1\"${sha256}\"/" "${cask_file}" >"${tmp}"
mv -f "${tmp}" "${cask_file}"

grep -Fxq "  version \"${version}\"" "${cask_file}" || die "version line was not rewritten in ${cask_file}; check its formatting"
grep -Fxq "  sha256 \"${sha256}\"" "${cask_file}" || die "sha256 line was not rewritten in ${cask_file}; check its formatting"

ruby -c "${cask_file}" >/dev/null || die "${cask_file} is not valid Ruby after rewrite"

log "Updated ${cask_file} to ${version} (${sha256})"
cat "${cask_file}" >&2
