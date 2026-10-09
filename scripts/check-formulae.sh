#!/usr/bin/env bash
# Build and test the tap's changed Linux formulae natively on this host (CI runs
# it on x86_64 and ARM64). Formulae it builds stay installed.
#
# Selection: formulae whose Formula/<token>.rb differs from BASE_SHA. In GitHub
# Actions, BASE_SHA defaults to the PR base (pull_request) or the previous tip
# (push). Without a usable base (schedule, dispatch, a local run) every formula
# is selected, and so is every formula when this build harness changes. A
# selected formula also selects the tap formulae that depend on it.
#
# Each selected formula, dependencies first: build from source, brew test,
# brew linkage --test and brew audit --strict. Formulae installing a desktop
# entry then run the X11 and Wayland checks of scripts/test-linux-gui.sh, which
# need xvfb, xauth, weston, Mesa EGL (weston's GL renderer) and dbus-x11 from the host.
#
# Usage: scripts/check-formulae.sh [--list]
#   --list  print the selection, one token per line, and build nothing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${root}"

list_only=false
case "${1:-}" in
  "") ;;
  --list) list_only=true ;;
  *)
    echo "Usage: scripts/check-formulae.sh [--list]" >&2
    exit 2
    ;;
esac

harness=(scripts/check-formulae.sh scripts/test-linux-gui.sh scripts/test-wayland.sh scripts/gui-smoke.py)

formulae=()
for file in Formula/*.rb
do
  formulae+=("$(basename "${file}" .rb)")
done
[[ "${#formulae[@]}" -gt 0 ]] || {
  echo "ERROR: no formulae found" >&2
  exit 1
}

# tap_deps TOKEN — the edbfi/taps formulae TOKEN depends on.
tap_deps() {
  sed -nE 's|^ *depends_on "edbfi/taps/([a-z0-9-]+)".*|\1|p' "Formula/$1.rb"
}

base="${BASE_SHA:-}"
if [[ -z "${base}" && -n "${GITHUB_EVENT_PATH:-}" ]]
then
  case "${GITHUB_EVENT_NAME:-}" in
    pull_request) base="$(jq -r '.pull_request.base.sha // empty' "${GITHUB_EVENT_PATH}")" ;;
    push) base="$(jq -r '.before // empty' "${GITHUB_EVENT_PATH}")" ;;
    *) ;;
  esac
fi

declare -A selected=()
# Formulae deleted by the change: never built, but whatever still depends on them is.
declare -A removed=()
if [[ -z "${base}" || "${base}" =~ ^0+$ ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null
then
  echo "No usable base commit: selecting every formula." >&2
  for token in "${formulae[@]}"; do selected["${token}"]=1; done
else
  mapfile -t changed < <(git diff --name-only "${base}" HEAD --)
  for file in "${changed[@]}"
  do
    for path in "${harness[@]}"
    do
      if [[ "${file}" == "${path}" ]]
      then
        echo "${file} changed: selecting every formula." >&2
        for token in "${formulae[@]}"; do selected["${token}"]=1; done
      fi
    done
    if [[ "${file}" =~ ^Formula/([a-z0-9-]+)\.rb$ ]]
    then
      if [[ -f "${file}" ]]; then selected["${BASH_REMATCH[1]}"]=1; else removed["${BASH_REMATCH[1]}"]=1; fi
    fi
  done
fi

# Add dependents until nothing changes.
grown=true
while "${grown}"
do
  grown=false
  for token in "${formulae[@]}"
  do
    [[ -z "${selected[${token}]:-}" ]] || continue
    for dep in $(tap_deps "${token}")
    do
      if [[ -n "${selected[${dep}]:-}" || -n "${removed[${dep}]:-}" ]]
      then
        selected["${token}"]=1
        grown=true
      fi
    done
  done
done

# Order: a formula after the selected formulae it depends on.
order=()
declare -A placed=()
while [[ "${#order[@]}" -lt "${#selected[@]}" ]]
do
  progress=false
  for token in "${formulae[@]}"
  do
    [[ -n "${selected[${token}]:-}" && -z "${placed[${token}]:-}" ]] || continue
    ready=true
    for dep in $(tap_deps "${token}")
    do
      if [[ -n "${selected[${dep}]:-}" && -z "${placed[${dep}]:-}" ]]; then ready=false; fi
    done
    if "${ready}"
    then
      order+=("${token}")
      placed["${token}"]=1
      progress=true
    fi
  done
  "${progress}" || {
    echo "ERROR: dependency cycle among ${!selected[*]}" >&2
    exit 1
  }
done

if "${list_only}"
then
  if [[ "${#order[@]}" -gt 0 ]]; then printf '%s\n' "${order[@]}"; fi
  exit 0
fi
if [[ "${#order[@]}" -eq 0 ]]
then
  echo "No formula changed against ${base}; nothing to build."
  exit 0
fi
echo "Formulae to build: ${order[*]}"

if ! command -v brew >/dev/null && [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]
then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
command -v brew >/dev/null || {
  echo "ERROR: Homebrew is required" >&2
  exit 1
}
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1
# shellcheck source=SCRIPTDIR/lib/tap.sh
source scripts/lib/tap.sh
tap_checkout "${root}"

gui=()
for token in "${order[@]}"
do
  echo "::group::${token}"
  # reinstall when present, so a changed recipe with an unchanged version is really rebuilt.
  if brew list --formula "edbfi/taps/${token}" >/dev/null 2>&1
  then
    brew reinstall --formula --build-from-source "edbfi/taps/${token}"
  else
    brew install --formula --build-from-source "edbfi/taps/${token}"
  fi
  brew test "edbfi/taps/${token}"
  brew linkage --test "edbfi/taps/${token}"
  brew audit --strict --formula "edbfi/taps/${token}"
  echo "::endgroup::"
  if grep -q '"applications/' "Formula/${token}.rb"; then gui+=("${token}"); fi
done

if [[ "${#gui[@]}" -gt 0 ]]
then
  bash scripts/test-linux-gui.sh "${gui[@]}"
fi
echo "Formulae OK: ${order[*]}"
