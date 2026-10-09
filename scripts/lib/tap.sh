#!/usr/bin/env bash
# Tap a checkout as edbfi/taps for the native checks. Source this file; do not
# execute it. Bash 3.2 compatible: macOS runners use it.

# tap_checkout ROOT — make edbfi/taps resolve to ROOT and trust it. An existing
# edbfi/taps tap is used only if it already points at ROOT; any other tap fails
# rather than being clobbered. A symlink created here is removed on exit.
tap_checkout() {
  local root="$1" tap_dir
  tap_dir="$(brew --repository)/Library/Taps/edbfi"
  TAP_LINK="${tap_dir}/homebrew-taps"
  if [[ -e "${TAP_LINK}" || -L "${TAP_LINK}" ]]
  then
    [[ "$(cd "${TAP_LINK}" && pwd -P)" == "${root}" ]] || {
      printf 'ERROR: edbfi/taps is already tapped at %s, not %s\n' "${TAP_LINK}" "${root}" >&2
      return 1
    }
  else
    mkdir -p "${tap_dir}"
    ln -s "${root}" "${TAP_LINK}"
    trap 'rm -f "${TAP_LINK}"' EXIT
  fi
  brew trust edbfi/taps
}
