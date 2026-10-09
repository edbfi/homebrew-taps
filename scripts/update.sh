#!/usr/bin/env bash
# The cask updater's stages, run by .github/workflows/update-casks.yml (edbfi-ci
# design/d8.md rules 8-13).
#
# A claim is a file holding exactly "version=…" and "sha256=…"; it crosses jobs as
# the artifact claim-TOKEN-ATTEMPT, then checked-TOKEN-ATTEMPT. publish and push
# handle each cask in its own process: a failing cask fails the stage at the end
# and never stops the others. Both refuse re-runs, which would read an earlier
# attempt's artifacts; a new run is the retry, and it re-derives everything.
#
# Usage:
#   scripts/update.sh check TOKEN OUTDIR    job 1 (macOS): resolve, download, inspect and
#                                           validate; write OUTDIR/claim.env when TOKEN
#                                           needs an update. Prints claim=true|false.
#   scripts/update.sh plan CASKS_JSON       the tokens with a claim artifact in this
#                                           attempt. Prints casks=<json>.
#   scripts/update.sh publish CASKS_JSON    job 2: re-derive each claim and publish the
#                                           rolling release. Prints published=<json>.
#   scripts/update.sh verify TOKEN OUTDIR   job 3 (macOS): fetch the published download
#                                           through the rewritten cask; copy the claim
#                                           to OUTDIR.
#   scripts/update.sh push CASKS_JSON       job 4: rewrite and push each verified cask
#                                           from a fresh clone of $UPDATER_REMOTE's main.
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

self="${REPO_ROOT}/scripts/update.sh"
# Per-cask deadlines (seconds) for the Linux stages, so one stalled download can't
# use up the job. All casks together must fit the publish and push jobs' timeouts;
# tests/test_updater.py checks that as casks are added.
PUBLISH_DEADLINE="${PUBLISH_DEADLINE:-540}"
PUSH_DEADLINE="${PUSH_DEADLINE:-150}"

# field KEY FILE — the value of the KEY=… line of a key=value FILE.
field() { sed -n "s/^$1=//p" "$2" | head -n 1; }

# json_array [ITEM...] — the items as a compact JSON array of strings.
json_array() {
  if [[ $# -eq 0 ]]
  then
    echo '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -cs .
  fi
}

# tokens_from JSON — the JSON array's entries, each one a discovered cask token.
tokens_from() {
  local json="$1" known token
  jq -e 'type == "array" and all(.[]; type == "string")' <<<"${json}" >/dev/null ||
    die "Expected a JSON array of cask tokens"
  known="$(bash "${REPO_ROOT}/scripts/discover.sh" | jq -r '.cask[]')"
  while IFS= read -r token
  do
    [[ -n "${token}" ]] || continue
    grep -Fxq -- "${token}" <<<"${known}" || die "Unknown cask token: ${token}"
    printf '%s\n' "${token}"
  done < <(jq -r '.[]' <<<"${json}")
}

first_attempt() {
  [[ "${GITHUB_RUN_ATTEMPT:-1}" == 1 ]] || die "Re-runs read an earlier attempt's artifacts; start a new run instead"
}

# resolve_into DIR TOKEN — run the resolver and the update check in DIR, leaving
# resolved.txt and, unless the resolver skipped, check.txt.
resolve_into() {
  local dir="$1" token="$2" skip member
  (cd "${dir}" && bash "${REPO_ROOT}/scripts/resolve.sh" "${token}") >"${dir}/resolved.txt"
  skip="$(field skip "${dir}/resolved.txt")"
  [[ "${skip}" != true ]] || return 0
  member="$(field archive_member "${dir}/resolved.txt")"
  [[ -z "${member}" ]] || die "${token}: the updater doesn't take archive downloads"
  bash "${REPO_ROOT}/scripts/check-update.sh" "${token}" \
    "$(field version "${dir}/resolved.txt")" "$(field asset "${dir}/resolved.txt")" >"${dir}/check.txt"
}

# fetch_into DIR — download the resolved asset into DIR and print its sha256.
fetch_into() {
  local dir="$1"
  (cd "${dir}" && bash "${REPO_ROOT}/scripts/fetch-asset.sh" \
    "$(field download_url "${dir}/resolved.txt")" "$(field asset "${dir}/resolved.txt")") |
    sed -n 's/^sha256=//p'
}

stage_check() {
  local token="$1" out="$2" work skip needed=false version sha
  load_pipeline "${token}"
  work="$(mktemp -d)"
  resolve_into "${work}" "${token}"
  skip="$(field skip "${work}/resolved.txt")"
  [[ "${skip}" == true ]] || needed="$(field needed "${work}/check.txt")"
  if [[ "${needed}" != true ]]
  then
    log "${token}: no update."
    echo "claim=false"
    return 0
  fi
  version="$(field version "${work}/resolved.txt")"
  sha="$(fetch_into "${work}")"
  python3 "${REPO_ROOT}/scripts/inspect-macos.py" "${token}" "${work}/$(field asset "${work}/resolved.txt")" >&2
  cp "${REPO_ROOT}/${CASK_FILE}" "${work}/recipe.rb"
  bash "${REPO_ROOT}/scripts/write-cask.sh" "${work}/recipe.rb" "${version}" "${sha}"
  mkdir -p "${out}"
  printf 'version=%s\nsha256=%s\n' "${version}" "${sha}" >"${out}/claim.env"
  read_claim "${out}/claim.env"
  log "${token}: claim ${version} (${sha})."
  echo "claim=true"
}

stage_plan() {
  local names tokens token selected=()
  tokens="$(tokens_from "$1")"
  names="$(gh api --paginate "repos/${GH_REPO:?GH_REPO is required}/actions/runs/${GITHUB_RUN_ID:?}/artifacts?per_page=100" \
    --jq '.artifacts[] | select(.expired | not) | .name')"
  while IFS= read -r token
  do
    [[ -n "${token}" ]] || continue
    if grep -Fxq -- "claim-${token}-${GITHUB_RUN_ATTEMPT:?}" <<<"${names}"
    then
      selected+=("${token}")
    fi
  done <<<"${tokens}"
  echo "casks=$(json_array ${selected[@]+"${selected[@]}"})"
}

publish_one() {
  local token="$1" claim work skip version needed newer sha
  load_pipeline "${token}"
  claim="$(intake_claim "claim-${token}-${GITHUB_RUN_ATTEMPT:?}")"
  read_claim "${claim}"
  work="$(mktemp -d)"
  resolve_into "${work}" "${token}"
  skip="$(field skip "${work}/resolved.txt")"
  [[ "${skip}" != true ]] || die "${token}: upstream no longer resolves"
  version="$(field version "${work}/resolved.txt")"
  [[ "${version}" == "${CLAIM_VERSION}" ]] || die "${token}: upstream is ${version}, the claim ${CLAIM_VERSION}"
  needed="$(field needed "${work}/check.txt")"
  [[ "${needed}" == true ]] || die "${token}: ${version} needs no update"
  newer="$(version_newer "${version}" "$(field previous_version "${work}/check.txt")")"
  [[ "${newer}" == true ]] || die "${token}: ${version} is not newer"
  sha="$(fetch_into "${work}")"
  [[ "${sha}" == "${CLAIM_SHA256}" ]] || die "${token}: the download hashes to ${sha}, the claim to ${CLAIM_SHA256}"
  VERSION="${version}" PREV_VERSION="$(field previous_version "${work}/check.txt")" \
  REF="$(field ref "${work}/resolved.txt")" CHANGES_URL="$(field changes_url "${work}/resolved.txt")" \
  ASSET="$(field asset "${work}/resolved.txt")" DOWNLOAD_URL="$(field download_url "${work}/resolved.txt")" \
    bash "${REPO_ROOT}/scripts/release-notes.sh" "${token}" >"${work}/notes.md"
  (cd "${work}" && bash "${REPO_ROOT}/scripts/publish-release.sh" "${token}" \
    "${work}/$(field asset "${work}/resolved.txt")" "${work}/notes.md") >&2
}

stage_publish() {
  local tokens token failed=0 published=()
  first_attempt
  tokens="$(tokens_from "$1")"
  echo "published=[]"
  while IFS= read -r token
  do
    [[ -n "${token}" ]] || continue
    if timeout --kill-after=10s "${PUBLISH_DEADLINE}" bash "${self}" _publish "${token}"
    then
      published+=("${token}")
      # Output as we go: the last line wins, even if a later cask fails.
      echo "published=$(json_array "${published[@]}")"
    else
      failed=$((failed + 1))
      log "${token}: not published."
    fi
  done <<<"${tokens}"
  [[ "${failed}" -eq 0 ]] || die "${failed} cask(s) failed to publish"
}

stage_verify() {
  local token="$1" out="$2" claim root cached url
  load_pipeline "${token}"
  claim="$(intake_claim "claim-${token}-${GITHUB_RUN_ATTEMPT:?}")"
  read_claim "${claim}"
  root="$(cd "${REPO_ROOT}" && pwd -P)"
  bash "${REPO_ROOT}/scripts/write-cask.sh" "${root}/${CASK_FILE}" "${CLAIM_VERSION}" "${CLAIM_SHA256}"
  # shellcheck source=SCRIPTDIR/lib/tap.sh
  source "${REPO_ROOT}/scripts/lib/tap.sh"
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1
  HOMEBREW_CACHE="$(mktemp -d)"
  export HOMEBREW_CACHE
  tap_checkout "${root}"
  url="https://github.com/${GH_REPO:?}/releases/download/${RELEASE_TAG}/${ASSET_PREFIX}-${CLAIM_VERSION}.dmg"
  brew info --json=v2 --cask "edbfi/taps/${token}" |
    jq -e --arg v "${CLAIM_VERSION}" --arg s "${CLAIM_SHA256}" --arg u "${url}" \
      '.casks | length == 1 and .[0].version == $v and .[0].sha256 == $s and .[0].url == $u' >/dev/null ||
    die "${token}: the tapped cask doesn't load as ${CLAIM_VERSION} from ${url}"
  # brew fetch checks the download against the cask's sha256.
  brew fetch --cask --force "edbfi/taps/${token}" >&2
  cached="$(brew --cache --cask "edbfi/taps/${token}")"
  [[ -f "${cached}" && ! -L "${cached}" ]] || die "${token}: no fetched download at ${cached}"
  [[ "$(shasum -a 256 "${cached}" | awk '{print $1}')" == "${CLAIM_SHA256}" ]] || die "${token}: the fetched download doesn't match"
  python3 "${REPO_ROOT}/scripts/inspect-macos.py" "${token}" "${cached}" >&2
  mkdir -p "${out}"
  cp "${claim}" "${out}/claim.env"
  log "${token}: ${url} serves the claimed bytes."
}

# recipe_body FILE — a cask without its machine-owned version and sha256 lines.
recipe_body() { grep -Ev '^  (version|sha256) "' "$1"; }

push_one() {
  local token="$1" claim asset release found verified verified_body clone tries main_body current current_sha newer changed err
  load_pipeline "${token}"
  claim="$(intake_claim "checked-${token}-${GITHUB_RUN_ATTEMPT:?}")"
  read_claim "${claim}"
  asset="${ASSET_PREFIX}-${CLAIM_VERSION}.dmg"
  release="$(mktemp)"
  found="$(release_json "${RELEASE_TAG}" "${release}")"
  [[ "${found}" == found ]] || die "${token}: rolling release ${RELEASE_TAG} is missing"
  jq -e --arg name "${asset}" --arg digest "sha256:${CLAIM_SHA256}" \
    '[.assets[] | select(.name == $name)] | length == 1 and .[0].state == "uploaded" and .[0].digest == $digest' \
    "${release}" >/dev/null || die "${token}: ${RELEASE_TAG} doesn't serve ${asset} with the claimed sha256"
  # Job 3 verified the cask of VERIFIED_SHA; main's must still be that recipe.
  verified="$(mktemp)"
  gh api "repos/${GH_REPO:?}/contents/${CASK_FILE}?ref=${VERIFIED_SHA:?VERIFIED_SHA is required}" --jq .content |
    base64 -d >"${verified}"
  [[ -s "${verified}" ]] || die "${token}: can't read the verified ${CASK_FILE}"
  verified_body="$(recipe_body "${verified}")"
  for tries in 1 2 3
  do
    clone="$(mktemp -d)"
    git -c core.hooksPath=/dev/null clone --quiet --depth 1 --branch main "${UPDATER_REMOTE:?}" "${clone}"
    main_body="$(recipe_body "${clone}/${CASK_FILE}")"
    [[ "${main_body}" == "${verified_body}" ]] ||
      die "${token}: ${CASK_FILE} changed on main since it was verified; the next run redoes it"
    current="$(cask_version "${clone}/${CASK_FILE}")"
    current_sha="$(sed -n 's/^  sha256 "\(.*\)"$/\1/p' "${clone}/${CASK_FILE}")"
    if [[ "${current}" == "${CLAIM_VERSION}" ]]
    then
      [[ "${current_sha}" == "${CLAIM_SHA256}" ]] || die "${token}: main has ${current} with a different sha256"
      log "${token}: main already has ${current}."
      return 0
    fi
    newer="$(version_newer "${CLAIM_VERSION}" "${current}")"
    [[ "${newer}" == true ]] || die "${token}: ${CLAIM_VERSION} is not newer than main's ${current}"
    bash "${REPO_ROOT}/scripts/write-cask.sh" "${clone}/${CASK_FILE}" "${CLAIM_VERSION}" "${CLAIM_SHA256}"
    [[ "$(git -C "${clone}" -c core.hooksPath=/dev/null status --porcelain)" == " M ${CASK_FILE}" ]] ||
      die "${token}: the rewrite changed more than ${CASK_FILE}"
    changed="$(git -C "${clone}" -c core.hooksPath=/dev/null diff -U0 -- "${CASK_FILE}" |
      grep -E '^[-+]' | grep -Ev '^(---|\+\+\+) ' | grep -Ev '^[-+]  (version|sha256) "[^"]*"$' || true)"
    [[ -z "${changed}" ]] || die "${token}: the rewrite touched more than version and sha256"
    git -C "${clone}" -c core.hooksPath=/dev/null add -- "${CASK_FILE}"
    git -C "${clone}" -c core.hooksPath=/dev/null \
      -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit --quiet --signoff -m "chore(${token}): update to ${CLAIM_VERSION}"
    if err="$(git -C "${clone}" -c core.hooksPath=/dev/null push --quiet origin HEAD:refs/heads/main 2>&1)"
    then
      log "${token}: pushed ${CLAIM_VERSION} to main."
      return 0
    fi
    log "${err}"
    grep -Eq 'non-fast-forward|fetch first|\[rejected\]' <<<"${err}" || die "${token}: the push failed"
    log "${token}: main moved (try ${tries}); retrying from a fresh clone."
  done
  die "${token}: main kept moving; giving up"
}

stage_push() {
  local tokens token failed=0
  first_attempt
  tokens="$(tokens_from "$1")"
  while IFS= read -r token
  do
    [[ -n "${token}" ]] || continue
    timeout --kill-after=10s "${PUSH_DEADLINE}" bash "${self}" _push "${token}" || {
      failed=$((failed + 1))
      log "${token}: not pushed."
    }
  done <<<"${tokens}"
  [[ "${failed}" -eq 0 ]] || die "${failed} cask(s) failed to push"
}

case "${1:-}" in
  check) stage_check "${2:?TOKEN}" "${3:?OUTDIR}" ;;
  plan) stage_plan "${2:?CASKS_JSON}" ;;
  publish) stage_publish "${2:?CASKS_JSON}" ;;
  _publish) publish_one "${2:?TOKEN}" ;;
  verify) stage_verify "${2:?TOKEN}" "${3:?OUTDIR}" ;;
  push) stage_push "${2:?CASKS_JSON}" ;;
  _push) push_one "${2:?TOKEN}" ;;
  *) die "usage: update.sh check|plan|publish|verify|push …" ;;
esac
