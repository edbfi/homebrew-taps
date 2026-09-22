<div align="center">

# edbfi/taps

**One Homebrew tap for macOS apps that homebrew-cask does not carry, kept current automatically.**

[![Update casks](https://img.shields.io/github/actions/workflow/status/edbfi/homebrew-taps/update-casks.yml?branch=main&label=update%20casks&logo=githubactions&logoColor=white)](https://github.com/edbfi/homebrew-taps/actions/workflows/update-casks.yml)
[![Lint](https://img.shields.io/github/actions/workflow/status/edbfi/homebrew-taps/lint.yml?branch=main&label=lint&logo=githubactions&logoColor=white)](https://github.com/edbfi/homebrew-taps/actions/workflows/lint.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Monero: Donate XMR](https://img.shields.io/badge/Monero-Donate%20XMR-F26822?logo=monero&logoColor=white)](#-support-the-developers)

</div>

Every cask here re-hosts an upstream build on this repository's releases, checks it with VirusTotal, and is refreshed every six hours by a shared pipeline. Apps that Gatekeeper would block are de-quarantined on install, so they open like anything else.

## 💛 Support the developers

This tap only re-packages other people's work. If an app earns a place in your Dock, send something to the person who builds it. Each cask prints this reminder on install and on every upgrade.

| App | Support upstream |
| --- | --- |
| **Flixor** | [![Ko-fi: Support Flixor](https://img.shields.io/badge/Ko--fi-Support%20Flixor-ff5f5f?logo=kofi&logoColor=white)](https://ko-fi.com/flixor) |
| **Fred TV** | [![GitHub Sponsors: Fredolx](https://img.shields.io/badge/GitHub%20Sponsors-Fredolx-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/Fredolx) [![PayPal: fredolx](https://img.shields.io/badge/PayPal-fredolx-00457c?logo=paypal&logoColor=white)](https://paypal.me/fredolx) [![Crypto donation](https://img.shields.io/badge/Crypto-Donate-f7931a?logo=bitcoin&logoColor=white)](https://github.com/Fredolx/open-tv#donate-crypto-thank-you) |
| **Paicord** | [![GitHub Sponsors: llsc12](https://img.shields.io/badge/GitHub%20Sponsors-llsc12-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/llsc12) |
| **FCast Sender** | No donation page. [Star the project](https://github.com/futo-org/fcast), file bugs, contribute. |
| **qView** | No donation page. [Star the project](https://github.com/jurplel/qView), file bugs, contribute. |
| **qBittorrent** | [Donate to the developers and server costs](https://www.qbittorrent.org/donate) |

**Support this tap.** The pipeline, hosting, and upkeep are done by [@edbfi](https://github.com/edbfi). Monero is welcome:

[![Monero: Donate XMR](https://img.shields.io/badge/Monero-Donate%20XMR-F26822?logo=monero&logoColor=white)](#-support-the-developers)

```text
8Awh9TSyJPZT99RWbVpd6sDLKNCLAWKm5M6chez7T1emhJDJXdoX583bzVRHjpn2Ej7jFqn3fEzkBMYYBFax5vqj97MvC72
```

## Apps

| App | Install | Requires |
| --- | --- | --- |
| [FCast Sender](https://fcast.org/) | `brew install --cask edbfi/taps/fcast-sender` | Apple Silicon, macOS 11+ |
| [Flixor](https://github.com/Flixorui/flixor) | `brew install --cask edbfi/taps/flixor` | macOS 13+ |
| [Fred TV](https://github.com/Fredolx/open-tv) | `brew install --cask edbfi/taps/fredtv` | macOS, `mpv`, `ffmpeg`, `yt-dlp` (installed for you) |
| [Paicord](https://github.com/llsc12/Paicord) | `brew install --cask edbfi/taps/paicord` | macOS 14+ |
| [qBittorrent](https://www.qbittorrent.org/) | `brew install --cask edbfi/taps/qbittorrent` | macOS 13+ |
| [qView](https://github.com/jurplel/qView) | `brew install --cask edbfi/taps/qview` | macOS 12+ |

Casks live in `Casks/<category>/`: `media/` holds FCast Sender, Flixor, Fred TV and qView; `network/` holds qBittorrent; `social/` holds Paicord. The category is only a folder; the install command never changes.

### App notes

- **qBittorrent** packages the standard stable desktop DMG (Qt 6/libtorrent 1.2), not the separate `qbittorrent-cli` client or `lt20` variant. The universal `qbittorrent.app` is installed as `qBittorrent.app`, with quarantine removed after installation. If migrating from Homebrew's disabled macOS cask, run `brew uninstall --cask homebrew/cask/qbittorrent` without `--zap`, then `brew install --cask edbfi/taps/qbittorrent` to preserve settings and torrent state.
- **FCast Sender** ships only an `aarch64` build, so Intel Macs are not supported. The app is signed and notarized by FUTO, so no quarantine workaround is applied. Versions drop the pre-release suffix the upstream tag carries: `sender-0.0.3-beta` becomes `0.0.3`.
- **Flixor** versions match upstream tags such as `beta2.4.0`. The app bundle is `FlixorMac.app`.
- **Fred TV** depends on the `mpv` formula, which Homebrew installs alongside it. Versions strip a leading `v` (`v1.9.1` becomes `1.9.1`).
- **Paicord** uses the immutable upstream release belonging to the newest successful main build. Each cask version is `YYYY-MM-DD-<short sha>`; the release tag must match that exact build commit.

  > [!WARNING]
  > Paicord is an unofficial, third-party Discord client. Using it violates Discord's Terms of Service and your account may be suspended or banned. **Use at your own risk.**

- **qView** is disabled in the official homebrew-cask repository because of a Gatekeeper check. This cask removes the `com.apple.quarantine` attribute after install, so the app launches without a manual `xattr`.

Flixor, Fred TV, Paicord and qView are distributed unsigned upstream; each of those casks runs a `postflight_steps` block that strips the quarantine attribute from the installed app.

## Install, update, uninstall

Use the cask token from the [Apps](#apps) table (e.g. `fcast-sender`) for `<app>` below.

```bash
# Install (taps the repository automatically)
brew install --cask edbfi/taps/<app>

# Or tap first, then install by short name
brew tap edbfi/taps
brew install --cask <app>

# Update
brew upgrade --cask <app>

# Uninstall
brew uninstall --cask <app>

# Uninstall and remove application data
brew uninstall --cask --zap <app>

# Remove the tap
brew untap edbfi/taps
```

## Linux packages

qView, Fred TV and FCast's desktop Sender also have Linux source formulae for
ARM64 and x86_64. Flixor, Paicord and qBittorrent are packaged only for macOS in this tap. Use an explicit package
kind when a formula and cask share a name:

```sh
brew install --formula edbfi/taps/qview
brew install --formula edbfi/taps/fredtv
brew install --formula edbfi/taps/fcast-sender
```

These build from source; no Linux bottles are published by this rollout. Fred TV
remains source-only pending the existing upstream licensing clarification.
Native CI checks both architectures, formula tests/linkage, X11/Wayland rendering,
and local reinstall of eligible bottle artifacts. CI never publishes Linux releases
or updates the default branch. Formula source updates require a reviewed PR.

Use Homebrew's default Linux prefix on a supported host. Your desktop supplies
X11 or Wayland, D-Bus and audio; FCast capture additionally needs PipeWire and a
compatible ScreenCast portal. The tap installs a GStreamer plugin but starts no
session services. Add `/home/linuxbrew/.linuxbrew/share` to your session's
`XDG_DATA_DIRS` to expose desktop launchers. Uninstall preserves user settings.
See [platform support and historical validation](docs/platform-support.md) for
source versions, desktop requirements and untested hardware features.

## How it works

```mermaid
flowchart LR
    A[Every 6 hours] --> B[discover<br/>pipelines/*]
    B --> C[resolve.sh<br/>per-app upstream lookup]
    C --> D{new version or<br/>missing asset?}
    D -- no --> Z[done]
    D -- yes --> E[download + SHA256]
    E --> F[re-host on<br/>app-latest release]
    F --> G[rewrite cask<br/>version + sha256]
    G --> H[open PR for full CI and manual review]
    H --> I[VirusTotal scan<br/>report in release notes]
```

- [`update-casks.yml`](.github/workflows/update-casks.yml) runs on a six-hour schedule, lists every `pipelines/<app>/` directory, and runs the shared [`_update-cask.yml`](.github/workflows/_update-cask.yml) once per app, one at a time.
- `pipelines/<app>/resolve.sh` is the only app-specific code: it finds the newest upstream build and validates the tag and asset name strictly before anything else runs.
- The DMG is downloaded, hashed, and attached to this repository's rolling `<app>-latest` release, and the cask's `version` and `sha256` lines are rewritten in a PR for full CI and manual review. Every release page carries the upstream reference, the checksum source, and a VirusTotal report.
- [`lint.yml`](.github/workflows/lint.yml) runs `brew style`, `brew audit`, and shellcheck on every change.

Releases: <https://github.com/edbfi/homebrew-taps/releases>

## Adding a cask

Start with the cask and pipeline files; the updater discovers them automatically:

1. `Casks/<category>/<app>.rb` with `url` pointing at `releases/download/<app>-latest/<Prefix>-#{version}.dmg` and a donation `caveats` block.
2. `pipelines/<app>/config.env` with the display name, upstream repo, asset prefix and donation links.
3. `pipelines/<app>/resolve.sh` that writes `version` and `download_url` (see the existing resolvers and the contract at the top of `scripts/resolve.sh`).

Register the inspected bundle identity and architectures in `scripts/inspect-macos.py`,
add resolver fixtures and update the cask list in `.github/workflows/lint.yml`.

`bash scripts/discover.sh` should then list the new app, and `GH_TOKEN=$(gh auth token) bash scripts/resolve.sh <app>` should print its current version. Details in [AGENTS.md](AGENTS.md).

## License and attribution

This is an unofficial, community-maintained tap, not affiliated with any of the upstream developers. The tap itself is licensed under [AGPL-3.0](LICENSE). The apps keep their own licenses:

| App | Upstream license |
| --- | --- |
| FCast Sender | [MIT](https://github.com/futo-org/fcast/blob/master/LICENSE) |
| Flixor | [Flixor Public License](https://github.com/Flixorui/flixor/blob/main/LICENSE.md) |
| Fred TV | [GPL-2.0](https://github.com/Fredolx/open-tv/blob/main/LICENSE) |
| Paicord | [GPL-3.0](https://github.com/llsc12/Paicord/blob/main/LICENSE) |
| qBittorrent | [GPL-3.0-or-later binary distribution, with OpenSSL exception](https://github.com/qbittorrent/qBittorrent/blob/release-5.2.3/COPYING) |
| qView | [GPL-3.0](https://github.com/jurplel/qView/blob/main/LICENSE) |

`scripts/vendor/gh-workflow-immortality.sh` is [gh-workflow-immortality](https://github.com/PhrozenByte/gh-workflow-immortality) by Daniel Rudolf, vendored unchanged under the MIT license.
