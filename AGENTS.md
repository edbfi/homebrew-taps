# AGENTS.md

This file provides guidance to AI coding agents when working with code in this
repository.

## What this is

`engels74/taps` re-hosts upstream macOS casks and builds native Linux formulae.
Application source stays upstream; this repository contains recipes, release
automation and packaging regression/GUI tests. Components:

1. `Casks/<category>/<token>.rb`, the casks. Categories are folders only; Homebrew
   loads `Casks/**/*.rb` and the token is the filename.
2. `pipelines/<token>/` plus `scripts/`, the update pipeline. One resolver per cask,
   everything else shared.
3. `Formula/`, Linux-only source recipes for qview, fredtv, fcast-sender and the
   supporting pipewire-gstreamer plugin. `scripts/resolve-formula.sh` pins source
   commits; `write-formula.py` updates source metadata without touching resources.
4. `.github/workflows/`, the schedule (`update-casks.yml`), the reusable per-cask
   pipeline (`_update-cask.yml`), validation (`lint.yml`) and the cron keepalive
   (`immortality.yml`), plus native dual-architecture builds and releases
   (`formulae.yml`).

## The contract that spans files

- A cask's `url` points at **this** repo's rolling release `<token>-latest`, asset
  `<ASSET_PREFIX>-#{version}.dmg`. `ASSET_PREFIX` lives in `pipelines/<token>/config.env`
  and the release tag is derived from the token in `scripts/lib/common.sh`
  (`load_pipeline`). Change the cask `url` and `ASSET_PREFIX` together, then
  dispatch the workflow and confirm the release really holds the new filename.
- `version` and `sha256` in every cask are machine-owned. To move them run
  `gh workflow run update-casks.yml -f cask=<token>`; never hand-edit. If you must,
  hash the DMG from this repo's `<token>-latest` release, not the upstream file.
- Those two lines must keep exactly two leading spaces with the quoted value on the
  same line. `scripts/write-cask.sh` rewrites them with an anchored `sed` and, unlike
  the old per-repo workflows, **fails loudly** if the rewrite did not take effect.

## Adding a cask

1. `Casks/<category>/<token>.rb` with `url` as above and a donation `caveats` block
   (see the existing casks; qView and FCast Sender show the wording for upstreams
   with no donation page).
2. `pipelines/<token>/config.env` with `DISPLAY_NAME`, `UPSTREAM_REPO`, `UPSTREAM_URL`,
   `ASSET_PREFIX`, `DONATE_LINKS` (`Label: URL|Label: URL`, may be empty).
3. `pipelines/<token>/resolve.sh`. It runs with `lib/common.sh` helpers and the
   `config.env` variables loaded and must `kv "$RESOLVE_OUT" …` the keys documented
   at the top of `scripts/resolve.sh` (`version`, `download_url`, `ref`,
   `changes_url`, optional `archive_member`, or `skip true`). Validate the upstream
   tag with a strict regex before it becomes a version; `scripts/resolve.sh`
   re-checks against `^[A-Za-z0-9][A-Za-z0-9._+-]*$` as a last line of defence.
4. Test locally: `GH_TOKEN=$(gh auth token) bash scripts/resolve.sh <token>` must
   print the expected version. `bash scripts/discover.sh` must list the token.
5. Add the app to the README tables (Apps, Support, License).
6. Add its verified bundle name, identifier and architectures to `APPS` in
   `scripts/inspect-macos.py`. Inspection must pass against the actual DMG.

No workflow edit is needed; `update-casks.yml` discovers `pipelines/*` at run time.

## Verifying changes locally

`brew style` and `brew audit` refuse bare paths, so link the working copy in as the
tap, run the checks, and unlink:

```bash
T="$(brew --repository)/Library/Taps/engels74"; mkdir -p "$T"; ln -sfn "$PWD" "$T/homebrew-taps"
brew readall --no-simulate engels74/taps
brew style engels74/taps          # rubocop on casks + shfmt/shellcheck on scripts
brew audit --cask --tap engels74/taps
rm "$T/homebrew-taps"
```

`brew style` runs shellcheck with all checks enabled and fails on info-level
findings; keep `.shellcheckrc` in mind before disabling checks inline. `actionlint`
validates the workflows. `lint.yml` runs the same checks in CI.

## Footguns

- **An upstream re-release under an existing version is never picked up.**
  `check-update.sh` says `needed=false` when the cask version matches and the
  rolling release already holds the asset, and `publish-release.sh` leaves a
  same-named asset in place. Recovery: delete that asset from `<token>-latest`, then
  dispatch the workflow for that cask.
- **No automatic release pruning.** Keep binaries and corresponding sources
  together. Casks use rolling releases with versioned assets; Linux bottles use
  immutable run-specific releases. `publish-release.sh` downloads the hosted DMG
  and rejects mismatched bytes before its checksum can enter a cask.
- **Resolver guards are load-bearing, not defensive noise**: the tag regexes, the
  exact asset-name matches (`qView-<v>.dmg` excludes `qView-<v>-legacy.dmg`;
  `Fred.TV_<v>_universal.dmg` excludes other architectures), the exact expected URL
  checks, and FCast's `sender-` prefix filter (several products share one tag
  namespace upstream). Add guards; do not remove them.
- **FCast: a 404 on the derived `dl.fcast.org` URL is deliberately a skip**, not a
  failure. The GitHub release and the CDN upload land at different times.
- **Paicord: the version must end in exactly 7 hex chars** (`YYYY-MM-DD-sha7`); the
  "Changes" compare link is built from that suffix.
- **Flixor's app bundle is `FlixorMac.app` / `com.flixor.mac`** although the token
  is `flixor`; **Fred TV's bundle id is upstream's `dev.fredol.open-tv`**. Every `zap`
  path keys off those. Verify against an installed build before editing.
- **fcast-sender has no `postflight_steps` quarantine strip by design** (signed and
  notarized) and `depends_on arch: :arm64` because upstream ships aarch64 only. The
  other four casks strip `com.apple.quarantine` with `must_succeed: false`; keep that.
- **Step outputs enter shell only through `env:`.** Never interpolate `${{ }}` inside
  a `run:` block; the old flixor and paicord workflows did and it was a script
  injection path.
- `_update-cask.yml` runs casks with `max-parallel: 1`. Raising it reintroduces push
  races and VirusTotal rate-limit failures.
- The `virustotal-scan` job no-ops when `secrets.VT_API_KEY` is unset; missing scan
  results in release notes is expected, not a bug.
- `immortality.yml` needs `secrets.PERSONAL_TOKEN`; `github.token` cannot re-enable a
  workflow GitHub disabled for inactivity. If the 6-hour cron silently stops, check
  that secret first.
- `scripts/vendor/gh-workflow-immortality.sh` is vendored third-party MIT code
  (Daniel Rudolf, v1.1.1) in an AGPL-3.0 repo. Re-vendor from upstream rather than
  patching in place; its header points at a "LICENSE file" that here holds the AGPL
  text.

## Conventions

- Conventional Commits for human commits; pipeline commits are
  `chore(<token>): update to <version>`.
- `README.md` is the user-facing description of the cadence, re-hosting, donation
  links and migration path. Keep it in sync when any of those change.

## Linux packaging and validation

- `PACKAGE_KINDS` defaults to `cask`; set `cask,formula` for apps with both, or
  `formula` for the PipeWire plugin. `bash scripts/discover.sh '' formula` discovers
  formulae. The build workflow's dependency order and GUI app list are explicit;
  update both when adding a formula.
- `pipelines/bottles.json` is the binary publication allowlist. Fred TV is source-only
  pending GPL-2.0/OpenSSL 3 linking permission clarification. Keep testing its source
  build on both architectures, but do not upload its binaries without resolving that
  licensing question. The verifier rejects unapproved binary assets.
- Formula `url`, `version`, `sha256`, and generated `bottle` blocks are machine-owned
  after bootstrap. A scheduled/manual `formulae.yml` resolves candidates without
  changing main, builds and tests both architectures, uploads a complete release,
  verifies downloaded checksums, then commits. Same-version source changes fail
  for manual review. Keep explicit source versions and immutable commit archive URLs.
  Increment `revision` for same-version packaging or dependency/ABI fixes so
  installed users receive them with `brew upgrade`; rebuilding bottles alone
  does not make the application version outdated.
- Build and bottle each formula sequentially, immediately after its tests. Homebrew
  records prefix changes between build and bottling; unrelated installs in between
  can contaminate a bottle. Never run simultaneous brew installs in one prefix.
- `pipewire-gstreamer` builds only PipeWire's GStreamer plugin against core PipeWire.
  Do not replace or start the user's distribution audio server or portal.
- Fred TV uses Node 20 for Angular 17. Keep Cargo/npm lockfiles effective. FCast must
  build `senders/desktop`, not a similarly named receiver, CLI or SDK.
- `python3 -m unittest discover -s scripts/tests -v` checks resolver guards, source
  rewriting and complete bottle releases. `actionlint` checks all workflows.
- On Linux, `bash scripts/test-linux-gui.sh [qview fredtv fcast-sender]` uses private
  homes, D-Bus sessions, Xvfb and headless Weston. Required host tools: xvfb, xauth,
  weston and dbus-run-session. It renders test images and verifies windows/surface
  buffers. It does not prove audio, media playback, capture permissions or portals.
- `scripts/inspect-macos.py TOKEN DMG` mounts read-only, verifies bundle identity and
  all Mach-O slices, then detaches. The cask updater performs this before publishing.
  Architecture policy changes require inspecting actual bundles, not asset labels.
- Keep `docs/platform-support.md` honest about tested hardware and feature coverage.
  Never infer Intel Mac runtime support from universal slices or Linux ARM support
  from an x86_64 build. Do not overwrite an existing local tap when linking a test
  checkout; use a temporary tap name and remove only your symlink afterwards.
