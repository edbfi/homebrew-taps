#!/usr/bin/env bash
# Shared helpers for the tap update pipeline. Source this file; do not execute it.
#
# Every script in scripts/ and every pipelines/<cask>/resolve.sh runs with these
# helpers loaded. Keep this file small: anything upstream-specific belongs in a
# resolver, anything specific to one pipeline step belongs in that step's script.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

log() { printf '%s\n' "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

# kv FILE KEY VALUE — append "KEY=VALUE" to FILE (GITHUB_OUTPUT compatible).
kv() { printf '%s=%s\n' "$2" "$3" >>"$1"; }

# http_get URL OUTFILE [curl args...] — GET with retries. Prints the HTTP status
# code and never fails on a non-2xx response; callers decide what a status means.
http_get() {
  local url="$1" out="$2"
  shift 2
  curl -sSL --retry 5 --retry-all-errors --retry-max-time 120 \
    -w '%{http_code}' -o "${out}" "$@" "${url}"
}

# gh_api PATH OUTFILE — authenticated GitHub REST GET. Prints the HTTP status code.
gh_api() {
  local path="$1" out="$2"
  http_get "https://api.github.com/${path#/}" "${out}" \
    -H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN is required}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28"
}

# require_2xx STATUS CONTEXT [BODYFILE] — exit 1 with the response body on non-2xx.
require_2xx() {
  local status="$1" ctx="$2" body="${3:-}"
  if [[ "${status}" -lt 200 ]] || [[ "${status}" -ge 300 ]]
  then
    log "HTTP ${status} while ${ctx}."
    if [[ -n "${body}" ]] && [[ -f "${body}" ]]; then cat "${body}" >&2 || true; fi
    exit 1
  fi
}

# require_safe_version STRING — the only shape a version may have before it reaches
# sed, gh, a release tag, or a filename. Resolvers validate upstream tags with their
# own stricter regex; this is the last line of defence.
require_safe_version() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "Unsafe version string: '$1'"
}

# find_cask_file TOKEN — print the repo-relative path of Casks/**/TOKEN.rb.
find_cask_file() {
  local cask="$1" matches count
  matches="$(find "${REPO_ROOT}/Casks" -type f -name "${cask}.rb")"
  count="$(printf '%s\n' "${matches}" | grep -c . || true)"
  [[ "${count}" -eq 1 ]] || die "Expected exactly one Casks/**/${cask}.rb, found ${count}"
  printf '%s\n' "${matches#"${REPO_ROOT}/"}"
}

# cask_version CASK_FILE — the quoted value on the "  version" line.
cask_version() { grep -E '^  version "' "$1" | sed 's/.*"\(.*\)".*/\1/'; }

# load_pipeline TOKEN [cask|formula] — load one package kind from the app pipeline.
load_pipeline() {
  local cask="$1" kind="${2:-cask}"
  [[ "${cask}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Invalid cask token: '${cask}'"
  PIPELINE_DIR="${REPO_ROOT}/pipelines/${cask}"
  [[ -f "${PIPELINE_DIR}/config.env" ]] || die "Missing ${PIPELINE_DIR#"${REPO_ROOT}/"}/config.env"
  PACKAGE_KINDS=cask
  FORMULA_SOURCE=""
  FORMULA_TAG_RE=""
  export FORMULA_SOURCE FORMULA_TAG_RE
  # shellcheck disable=SC1091
  source "${PIPELINE_DIR}/config.env"
  [[ ",${PACKAGE_KINDS}," = *",${kind},"* ]] || die "${cask} has no ${kind} pipeline"
  : "${DISPLAY_NAME:?config.env must set DISPLAY_NAME}"
  : "${UPSTREAM_URL:?config.env must set UPSTREAM_URL}"
  : "${ASSET_PREFIX:?config.env must set ASSET_PREFIX}"
  CASK_TOKEN="${cask}"
  if [[ "${kind}" = cask ]]
  then
    [[ -f "${PIPELINE_DIR}/resolve.sh" ]] || die "Missing cask resolver for ${cask}"
    CASK_FILE="$(find_cask_file "${cask}")"
  else
    FORMULA_FILE="Formula/${cask}.rb"
    [[ -f "${REPO_ROOT}/${FORMULA_FILE}" ]] || die "Missing ${FORMULA_FILE}"
    export FORMULA_FILE
  fi
  RELEASE_TAG="${cask}-latest"
  RELEASE_TITLE="${DISPLAY_NAME} (latest)"
  export PIPELINE_DIR CASK_TOKEN CASK_FILE RELEASE_TAG RELEASE_TITLE
  export DISPLAY_NAME UPSTREAM_URL ASSET_PREFIX
  export UPSTREAM_REPO="${UPSTREAM_REPO:-}" DONATE_LINKS="${DONATE_LINKS:-}"
}
