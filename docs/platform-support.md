> This document records the original Linux feature validation from 6 September
> 2026. The edbfi integration uses local validation and source installation; no Linux
> publication workflow is enabled. Historical bottle publication/automatic-update
> descriptions below are design context, not active behavior. Current operational
> policy is in README.md. New validation receipts are recorded privately.

# Platform support and validation

Original assessment: September 2026, with qBittorrent added on 22 September 2026.
Historical validation establishes only the stated scope.

## Compatibility decisions

“Universal” below means the inspected macOS executable and bundled Mach-O
libraries contain both ARM64 and x86_64. It does not establish Intel runtime
compatibility. Linux formulae deliberately reject macOS; use the existing casks.

| App/version assessed | macOS | Linux ARM64 / x86_64 | Evidence and remaining work |
| --- | --- | --- | --- |
| FCast Sender 0.0.3 beta | Support existing ARM64 cask; retain Intel restriction | Support with native formula, GStreamer plugin and desktop session requirements | The [desktop sender](https://github.com/futo-org/fcast/tree/sender-0.0.3-beta/senders/desktop) is Rust/Slint, not the Electron receiver or terminal sender. [Upstream's Flatpak recipe](https://github.com/flathub/org.fcast.Sender/blob/master/org.fcast.Sender.yaml) documents Linux dependencies. Screen/audio capture needs real-session validation. |
| Flixor beta2.4.0 | Retain universal cask, macOS 13+ | Retain restriction | [Flixor source](https://github.com/Flixorui/flixor) contains multiple variants. `FlixorMac.app` / `com.flixor.mac` uses SwiftUI, AppKit and native media frameworks. Shipping its web variant would change the packaged application. Porting the native variant requires substantial upstream work. |
| Fred TV 1.9.1 | Support universal cask; install missing external media tools | Support source-only formula with Node 20, Rust/Tauri, GTK3/WebKitGTK 4.1 and media tools | [Pinned source/build configuration](https://github.com/Fredolx/open-tv/tree/v1.9.1) supports Linux. Binary redistribution needs GPL-2.0/OpenSSL 3 clarification; the formula builds locally. It embeds the Angular frontend and wraps `mpv`, `ffmpeg`, `yt-dlp` paths. Node 20 matches Angular 17; an upstream frontend toolchain upgrade is needed before removing that build dependency. |
| Paicord 2026-08-05-473c780 | Support universal cask, macOS 14+ | Retain restriction | [Source](https://github.com/llsc12/Paicord) and build workflow package a SwiftUI macOS app; Linux support is unfinished upstream. The resolver now binds a successful build run to its immutable release tag, exact asset and source commit. |
| qView 7.1 | Support universal cask, macOS 12+ | Support native Qt 6 formula | [Release source](https://github.com/jurplel/qView/tree/7.1) uses qmake (current development uses a different build system). Reuse core Qt base, SVG, image-format and Wayland packages. Validate real image decoding, not just `--version`. |
| qBittorrent 5.2.3 | Universal desktop cask, macOS 13+ | Not packaged by this tap | The standard [upstream DMG](https://github.com/qbittorrent/qBittorrent/releases/tag/release-5.2.3) contains `qbittorrent.app` / `org.qbittorrent.qBittorrent`. Read-only inspection verified ARM64 and x86_64 in every Mach-O file and `LSMinimumSystemVersion=13.0`. Intel launch and torrent transfers remain untested. |

FCast's canonical repository is [FUTO GitLab](https://gitlab.futo.org/videostreaming/fcast).
The formula pins an immutable commit archive from its GitHub mirror.

### Homebrew requirements and package choice

Use the [official Linux installation requirements](https://docs.brew.sh/Homebrew-on-Linux)
and [support tiers](https://docs.brew.sh/Support-Tiers), rather than old Linuxbrew
guidance. The intended bottle configuration is Ubuntu 24.04+ with glibc 2.39+,
ARM64 or x86_64, at `/home/linuxbrew/.linuxbrew`. Intel macOS is Tier 3; a cask's
app minimum OS does not guarantee a supported Homebrew installation.

The original premise that casks are categorically macOS-only is no longer true
in current Homebrew: its [cask DSL](https://docs.brew.sh/Cask-Cookbook) includes
Linux/AppImage support. These tap definitions remain macOS app-bundle
casks. Native Linux formulae are appropriate here because the selected source
variants build against Homebrew libraries, have normal launch commands and
desktop files, and can receive independently tested bottles for both architectures.
No AppImage extraction, FUSE requirement or system-library guessing is needed.

Core dependencies are reused. The only additional support recipe is
`pipewire-gstreamer`: core [PipeWire's recipe](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/p/pipewire.rb)
disables its GStreamer plugin. This tap compiles only that plugin against installed
PipeWire/GStreamer. It does not configure or start an audio server; the desktop
continues to provide its own session services.

## What “working” means

A supported release must install from a clean formula/bottle, resolve its linked
libraries, expose launch commands and desktop files, and render an actual window
under both X11 and Wayland. Reinstalling from the produced bottles must pass the
same checks. Removal must remove packaged files while preserving user data.

Feature acceptance adds the following manual checks:

| App | Desktop acceptance beyond CI |
| --- | --- |
| qView | Open PNG, SVG and animated GIF; navigate images, zoom, fullscreen; verify file association and desktop-menu launch |
| Fred TV | Import a permitted M3U source, play a stream with sound, seek, record with ffmpeg, exercise a supported yt-dlp URL, quit and reopen without losing the source |
| FCast Sender | Discover and connect to a real receiver; cast a permitted file/URL; screen and audio capture on X11; Wayland ScreenCast portal permission, cancellation and reconnect |
| Flixor | Launch the native app, authenticate to a permitted Plex server, play media with sound, quit/reopen |
| Paicord | Launch, then authenticated operations only with an explicitly provided test account; no credentials are needed for packaging checks |

### Evidence collected

- qBittorrent 5.2.3 was added on 22 September 2026 using the shared resolver,
  download, bundle-inspection, release-notes and publisher scripts locally: the
  Actions publisher intentionally requires a successfully checked `main` revision,
  where the new cask does not exist until merge. The publisher downloaded the
  [re-hosted DMG](https://github.com/edbfi/homebrew-taps/releases/tag/qbittorrent-latest)
  back and verified byte equality. `write-cask.sh` generated the initial version
  and SHA-256 from the resolved release and a fresh download of the hosted asset.
  Homebrew installed it into a temporary application directory on macOS 26.6.2
  ARM64. Recursive inspection confirmed no quarantine attributes remained, and
  LaunchServices started it with a disposable profile without a manual Gatekeeper
  override. This was a launch smoke check, not a torrent-transfer test. Intel
  runtime behavior and VirusTotal scanning were not tested during bootstrap.
- All five original tap DMGs were downloaded and checked against their declared
  SHA256. `scripts/inspect-macos.py` verified actual bundle identifiers and every
  included Mach-O architecture. FCast's main executable is ARM64 only; the other
  four bundles are universal. No cask version or checksum was manually changed.
- On a separate Linux x86_64 validation host: qView, Fred TV and FCast Sender built from
  source and passed Xvfb/X11 and headless Weston/Wayland launch tests in disposable
  homes. qView rendered PNG and SVG fixtures (checked pixels), and opened a GIF.
  Fred TV rendered its initial source-setup screen. PipeWire source/sink plugins
  loaded successfully in Homebrew GStreamer.
- FCast Sender rendered its receiver-discovery interface under both display
  backends. Tests loaded PipeWire/X11/PulseAudio capture elements, VP8, Opus and
  WebRTC, and ran a synthetic VP8/RTP encoding pipeline. No real receiver was used.
- Source archives were generated for all four formulae. The archived Fred TV and
  FCast Cargo dependency graphs resolved offline using their vendored sources.
- Fred TV's formula test generated a short synthetic video with ffmpeg, decoded
  it with mpv's null outputs, and invoked yt-dlp. This verifies the external tools
  without claiming playback through the app or a real audio device.
- A separate manual test used the bottled Fred TV UI to import an M3U URL served
  on localhost and play a generated video. Visible video frames rendered in mpv
  under Xvfb with test-profile parameters `--vo=x11 --hwdec=no --ao=null`. Default
  GPU output failed on this displayless host. This proves the import/player flow
  with software video, not audible playback or acceleration. The profile and
  local server were disposable; no account or third-party stream was used.
- The host is bare metal without a connected display or usable GPU render node.
  Virtual-display tests use software rendering. They do not establish GPU,
  audible playback, receiver discovery or portal capture behavior.
- Native Ubuntu 24.04 ARM64 and x86_64 runners built all four formulae, passed
  formula/linkage/audit checks and X11/Wayland GUI tests, then uninstalled and
  reinstalled the three eligible bottles and repeated the tests. Fred TV remained
  installed from source. See the [validated native run](https://github.com/edbfi/homebrew-taps/actions/runs/34064114038)
  at commit `1dfbe55` and its GUI/log artifacts.
- [macOS CI](https://github.com/edbfi/homebrew-taps/actions/runs/34064281327)
  passed Homebrew parsing, style and audits, all five downloaded bundle checks,
  shell/workflow validation and all 19 regression tests at the same commit.
- The downloaded CI artifacts passed completeness and checksum verification:
  six approved bottles, six metadata files and four source archives. Archived
  provenance and recipes match the pinned formulae. Homebrew merged both
  architectures into each eligible formula and those generated definitions passed
  style checks. No Fred TV binary was present. These were validation artifacts only;
  merging this integration does not enable Linux publication.
- No Intel Mac runtime, authenticated Flixor/Paicord session, live IPTV source or
  physical FCast receiver was available. Those feature checks remain manual.

Run the repeatable checks with:

```bash
python3 -m unittest discover -s scripts/tests -v
actionlint
# On Linux with the formulae installed and host xvfb/xauth/weston/dbus tools:
bash scripts/test-linux-gui.sh
# On macOS, inspect a downloaded artifact without installing or launching it:
python3 scripts/inspect-macos.py qview /path/to/qView.dmg
```

The Wayland harness starts a fresh headless Weston compositor and D-Bus session
for each application, retaining its compositor log alongside the client logs.
Early client exits remain failures and retain their complete output.

The GUI harness uses private HOME/XDG directories and isolated D-Bus/display
sessions. Evidence is written to `/tmp/tap-gui-results`. X11 checks window titles
and image pixels; Wayland checks that a live client submits surface buffers.
A static GIF fixture proves loading, not animation timing. Manual upgrade checks
should additionally start with real prior-version settings and verify persistence.

## Release and license controls

Any future Linux publication design must require successful builds of all four
formulae on both architectures and formula/linkage/GUI checks, reinstall of eligible bottles, matching versions/checksums,
and a corresponding source archive for each formula. The source archive contains
the exact pinned source, Cargo-vendored dependencies, Fred TV's npm packages,
license files and tap build recipes. Bottle JSON records build provenance and
separately installed Homebrew dependencies; those dependencies are not repackaged
inside these application archives. Binaries and sources are retained together.
Same-version packaging/ABI fixes require a formula `revision` bump to trigger
upgrades; a fresh bottle checksum alone is insufficient.

qView (GPL-3.0), Paicord (GPL-3.0), and the MIT-licensed
PipeWire plugin permit redistribution subject to their notices and source
obligations. FCast's top-level code is MIT, while the Linux desktop distribution
uses [GPL-3.0](https://github.com/futo-org/fcast/blob/master/senders/extra/LICENSE-GPL)
with Slint's GPL option; treating the combined binary as MIT-only is incorrect.
See the README license table and the dependency licenses preserved in the sources.

Fred TV remains source-only for Linux binary publication. Its pinned tree contains
[GPL-2.0 terms](https://github.com/Fredolx/open-tv/blob/v1.9.1/LICENSE), and the
compiled binary directly requires `libssl.so.3` and `libcrypto.so.3` via reqwest's
native TLS backend. [OpenSSL 3 uses Apache-2.0](https://openssl-library.org/source/license/),
which the [FSF identifies as incompatible with GPL-2.0-only](https://www.gnu.org/licenses/license-list.html#apache2).
No upstream linking exception or explicit later-version grant was found. Whether
a system-library exception applies to this Homebrew combination is unresolved;
the tap does not assume it. Local source installation and tests remain available.
Before enabling Fred TV bottles, obtain upstream clarification/permission or
implement and validate a compatible dependency configuration. Existing upstream
macOS cask support is retained: `otool -L` on both slices of that executable showed
Apple system frameworks, including Security, and no OpenSSL dependency.

[Flixor's custom license](https://github.com/Flixorui/flixor/blob/main/LICENSE.md)
adds noncommercial and public-source conditions to AGPL terms. Retain upstream
binaries and license notices, make the matching source accessible, and obtain
upstream permission before commercial use/distribution. This change does not
introduce a Flixor Linux build or assume that a standard AGPL grant applies.

VirusTotal reports are optional and informational. The release pipeline verifies
bytes and completeness independently of whether a scan key is configured.

## Follow-up platform work

1. Fred TV's Angular 17 toolchain requires follow-up before Homebrew disables
   [node@20](https://formulae.brew.sh/formula/node@20) on 28 October 2026. Node 20 is
   already deprecated. Upgrade and validate the frontend toolchain upstream (or
   carry a narrowly reviewed compatibility patch) before that deadline; the tap
   must not silently rely on an unsupported replacement Node major.
2. Complete the manual media/audio/portal matrix on ordinary Linux desktops before
   claiming full feature parity. Keep Xvfb and Weston: each exercises a different
   backend, and neither requires a connected monitor.
3. For Intel FCast, upstream's [macOS packaging task](https://github.com/futo-org/fcast/blob/sender-0.0.3-beta/xtask/src/sender.rs)
   builds the host target, bundles GStreamer and names the result `macos-aarch64`.
   SDK x86_64 jobs are not proof of desktop Sender support. Build the actual
   `desktop-sender` on Intel with compatible GStreamer, inspect every dylib,
   then test launch, receiver playback and capture. Signing/notarization and an
   architecture-specific asset/resolver contract are prerequisites for expanding
   the cask. This is feasible work to investigate, not verified Intel support.
4. Track upstream native Linux progress for Paicord and Flixor. Do not silently
   substitute a web client under an existing native-app token.
