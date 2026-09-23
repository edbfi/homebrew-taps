# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Homebrew tap `edbfi/taps`: macOS casks that re-host upstream DMGs on this repo's releases, plus Linux-only source formulae. No application code lives here; the moving parts are the casks/formulae, a Bash update pipeline (`scripts/`, `pipelines/<token>/`), and GitHub workflows.

## Commands

```bash
bash .github/scripts/check.sh                      # bash -n + shellcheck on all pipeline scripts, then tests/ (cask pipeline fixtures)
python3 -m unittest discover -s scripts/tests -v   # resolver guards, formula writer, bottle verifier, GUI harness
python3 -m unittest discover -s scripts/tests -k test_qview_rejects_legacy_asset   # one test case
python3 -m unittest discover -s tests -p test_pipeline.py -v                       # one file
actionlint                                         # workflows (.github/actionlint.yaml allows the ubuntu-26.04 label)
bash scripts/discover.sh                           # cask matrix JSON; `bash scripts/discover.sh '' formula` for formulae
GH_TOKEN=$(gh auth token) bash scripts/resolve.sh <token>   # live upstream lookup; prints key=value outputs
```

Both test trees are offline (fake `curl`/`gh` on PATH); they need Ruby and jq, and `check.sh` also needs ShellCheck. CI runs both: `tests/` via `check.sh`, `scripts/tests/` directly (`.github/workflows/lint.yml`). Resolver and Linux tests go in `scripts/tests/test_pipeline.py`; `write-cask.sh`/`discover.sh`/`publish-release.sh` fixtures go in `tests/test_pipeline.py`.

Native cask checks (macOS only) need this checkout tapped as `edbfi/taps`, exactly as `lint.yml` does it; don't clobber an existing local `edbfi/homebrew-taps` tap, and remove only your own symlink afterwards:

```bash
T="$(brew --repository)/Library/Taps/edbfi"; mkdir -p "$T"; ln -s "$PWD" "$T/homebrew-taps"; brew trust edbfi/taps
brew readall --no-simulate edbfi/taps && brew style edbfi/taps && brew audit --cask --tap edbfi/taps
```

`brew style` runs ShellCheck with every check enabled (info level fails); `.shellcheckrc` disables only SC2312.

## Cask pipeline contract

- `version` and `sha256` in `Casks/**/<token>.rb` are machine-owned. Move them with `gh workflow run update-casks.yml -f cask=<token>`, which opens a PR on `fix/update-cask-<token>`. It only runs on `main`, and only if `ci` succeeded for that exact SHA.
- `scripts/write-cask.sh` rewrites those lines with an anchored sed and fails if they don't match. Keep them exactly `  version "..."` / `  sha256 "..."` (two spaces, quoted, one line). `version :latest` or reformatting breaks the updater.
- The cask `url` must be `https://github.com/edbfi/homebrew-taps/releases/download/<token>-latest/<ASSET_PREFIX>-#{version}.dmg`. `ASSET_PREFIX` comes from `pipelines/<token>/config.env` and the `<token>-latest` tag from `load_pipeline` in `scripts/lib/common.sh`. Change the url and `ASSET_PREFIX` together.
- `scripts/inspect-macos.py` `APPS` is the source of truth for each cask's `.app` name, bundle id and required architectures. The updater runs it before publishing, and `zap` paths key off the bundle id. Flixor is `FlixorMac.app` / `com.flixor.mac`; Fred TV is `dev.fredol.open-tv`.
- `fcast-sender` is signed (inspect runs `codesign`/`spctl`), so it has no quarantine strip, and it has `depends_on arch: :arm64`. The other four casks strip `com.apple.quarantine` in `postflight_steps` with `must_succeed: false`. Copy that block for new unsigned apps.
- A same-version upstream re-release is never picked up: `check-update.sh` reports `needed=false` once the asset exists, and `publish-release.sh` keeps a same-named asset (it fails if the hosted bytes differ). To recover, delete that asset from the `<token>-latest` release and dispatch `update-casks.yml` for the cask.
- Resolver guards are load-bearing: strict tag regexes, exact asset names (qView rejects `-legacy.dmg`, Fred TV requires `_universal.dmg`, Flixor requires exactly one DMG), exact expected URLs, FCast's `sender-` filter, and Paicord's run/tag/commit binding. `ResolverTests` asserts them. Tighten guards; don't remove them.
- A resolver writes `skip true` when upstream isn't ready (FCast's `dl.fcast.org` 404, a missing Paicord nightly release). That is intentional, not a failure.
- VirusTotal is optional: `virustotal-scan` no-ops without `VT_API_KEY`. Release notes without scan results are expected.

## Adding a cask

README's "three files, no workflow changes" is incomplete. A new token touches:

1. `Casks/<category>/<token>.rb`: copy `Casks/media/qview.rb` (header comment, machine-owned lines, url shape above, donation `caveats`). The category is just a folder, and the token is the filename.
2. `pipelines/<token>/config.env`: `DISPLAY_NAME`, `UPSTREAM_REPO`, `UPSTREAM_URL`, `ASSET_PREFIX`, `DONATE_LINKS` (`Label: URL|Label: URL`, may be empty).
3. `pipelines/<token>/resolve.sh`: copy `pipelines/qview/resolve.sh`. It must `kv "$RESOLVE_OUT"` the keys documented at the top of `scripts/resolve.sh`.
4. `scripts/inspect-macos.py` `APPS` entry. Without it, the updater raises a `KeyError` before publishing.
5. `.github/workflows/lint.yml`: the `brew info` token list and the `jq -e` sorted-token assertion.
6. `scripts/tests/test_pipeline.py`: the cask count in `test_discovery_separates_kinds`, plus a `ResolverTests` case for the new guards.
7. `README.md` tables (Support, Apps, License).

After merge, the first scheduled or dispatched run creates the rolling release and opens the version/sha256 PR, because the missing release counts as "update needed".

## Linux formulae

- `Formula/*.rb` are Linux-only (`depends_on :linux`) and pinned to commit-SHA archive URLs with an explicit `version`. `formulae.yml` builds the checked-in recipes and never updates them. To bump a source by hand (neither script is wired into CI), run from the repo root:
  ```bash
  GH_TOKEN=$(gh auth token) bash scripts/resolve-formula.sh <token> > "$TMPDIR/resolved.json"
  python3 scripts/write-formula.py "$TMPDIR/resolved.json"   # drops the bottle block and revision; refuses changed bytes under the same version
  ```
- For a same-version packaging, dependency or ABI fix, bump `revision`. `verify-bottles.py` expects `version_revision` in bottle metadata.
- `pipelines/bottles.json` is the binary allowlist, and `verify-bottles.py` rejects anything else. Keep `fredtv` out of it (source-only pending GPL-2.0/OpenSSL 3 clarification, per its caveats and `docs/platform-support.md`).
- Adding a formula means editing `Formula/<token>.rb`, adding `formula` to `PACKAGE_KINDS` and a `FORMULA_TAG_RE` in `config.env` (or a `FORMULA_SOURCE` branch in `resolve-formula.sh`), and updating the hard-coded lists in `.github/workflows/formulae.yml`: the inventory `jq -e` assertion, both `for token in ...` loops (dependency order, `pipewire-gstreamer` before `fcast-sender`), and the reinstall artifact paths. Also update `test_discovery_separates_kinds`. GUI apps additionally need the default list in `scripts/test-linux-gui.sh` and the `choices`/expected titles in `scripts/gui-smoke.py`.
- `formulae.yml` builds, tests and bottles each formula immediately, one at a time. Never interleave other `brew install`s into that loop, because Homebrew attributes prefix changes to the bottle being built.
- `pipewire-gstreamer` builds only PipeWire's GStreamer plugin against core `pipewire`. It must not install or start an audio daemon.

## Workflows and dependencies

- In workflow `run:` blocks, pass step outputs and inputs through `env:`, never inline `${{ }}`. Every existing workflow follows this.
- Keep `max-parallel: 1` in `update-casks.yml`; casks are updated one at a time by design.
- `ci / required` gates on `guard`, `quality` (`lint.yml`) and `linux` (`formulae.yml`). `lint.yml` has no push/PR trigger of its own.
- Renovate's `homebrew` manager is disabled on purpose, because the updater owns cask versions. The `Homebrew/actions/setup-homebrew` pins in `formulae.yml` must keep the exact `@<40-hex sha> # YYYY.MM.DD.N` form, or the custom regex manager in `renovate.json` stops matching.
- `scripts/vendor/gh-workflow-immortality.sh` is vendored MIT code (v1.1.1), used unchanged. Re-vendor from upstream instead of patching it. `immortality.yml` needs `WORKFLOW_KEEPALIVE_TOKEN`; if the six-hour cron silently stops, check that secret first.
- PR titles must be Conventional Commits with author-matching DCO sign-offs (`git commit -s`), enforced by `pr-policy.yml`. Updater commits are `chore(<token>): update to <version>`.

## Reference docs

- `CI.md`: required CI gate, Renovate merge ownership, publisher token (`CASK_PUBLISHER_TOKEN`), keepalive. Read before changing `ci.yml`, `_update-cask.yml`, `update-casks.yml`, `pr-policy.yml`, `renovate.json`, secrets or branch protection.
- `docs/platform-support.md`: per-app platform/architecture decisions, licensing constraints, manual acceptance matrix. Read before changing supported architectures, bottle eligibility or Linux formula dependencies. Its "Evidence collected" section is a historical record, not current behavior.
