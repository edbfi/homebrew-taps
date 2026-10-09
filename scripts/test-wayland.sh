#!/usr/bin/env bash
# Child of test-linux-gui.sh, within a private runtime directory and D-Bus session.
# Weston 13 cannot launch clients with `-- command`; manage its lifetime here.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
: "${XDG_RUNTIME_DIR:?Private runtime directory required}"
: "${1:?Application required}"
app="$1"
# Weston 13's pixman renderer intermittently segfaults while compositing on x86_64
# (edbfi-ci B9); composite with GL on llvmpipe instead.
LIBGL_ALWAYS_SOFTWARE=1 weston --backend=headless --renderer=gl --no-config --idle-time=0 \
  --socket=tap-wayland --log="${XDG_RUNTIME_DIR}/weston.log" &
compositor=$!
cleanup() {
  local status=$?
  kill "${compositor}" 2>/dev/null || true
  wait "${compositor}" 2>/dev/null || true
  local artifacts="${GUI_TEST_ARTIFACTS:-/tmp/tap-gui-results}"
  mkdir -p "${artifacts}"
  cp "${XDG_RUNTIME_DIR}/weston.log" "${artifacts}/weston-${app}.log"
  return "${status}"
}
trap cleanup EXIT
for _ in {1..100}
do
  [[ -S "${XDG_RUNTIME_DIR}/tap-wayland" ]] && break
  if ! kill -0 "${compositor}" 2>/dev/null
  then
    cat "${XDG_RUNTIME_DIR}/weston.log"
    exit 1
  fi
  sleep 0.1
done
[[ -S "${XDG_RUNTIME_DIR}/tap-wayland" ]] || {
  cat "${XDG_RUNTIME_DIR}/weston.log"
  exit 1
}
export WAYLAND_DISPLAY=tap-wayland
python3 "${root}/scripts/gui-smoke.py" --session wayland "$@"
# A compositor crash must also fail when the client happened to finish first.
kill -0 "${compositor}"
