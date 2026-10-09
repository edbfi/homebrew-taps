# This cask is updated by the tap pipeline (pipelines/fredtv/).
# Do not edit the version or sha256 lines manually.
cask "fredtv" do
  version "1.9.1"
  sha256 "7266c11cfafa9bc6b42835db6ab3ec3fd0a7516557f1f43eb867852563523465"

  url "https://github.com/edbfi/homebrew-taps/releases/download/fredtv-latest/FredTV-#{version}.dmg"
  name "Fred TV"
  desc "Ultra-fast, simple and powerful cross-platform IPTV app"
  homepage "https://github.com/Fredolx/open-tv"

  depends_on formula: "ffmpeg"
  depends_on formula: "mpv"
  depends_on formula: "yt-dlp"
  depends_on :macos

  app "Fred TV.app"

  postflight_steps do
    # Upstream ships unsigned builds; strip the quarantine attribute so Gatekeeper lets the app launch.
    run "/usr/bin/xattr",
        args:         ["-r", "-d", "com.apple.quarantine", "{{appdir}}/Fred TV.app"],
        must_succeed: false
  end

  zap trash: [
    "~/Library/Application Support/dev.fredol.open-tv",
    "~/Library/Caches/dev.fredol.open-tv",
    "~/Library/HTTPStorages/dev.fredol.open-tv",
    "~/Library/Preferences/dev.fredol.open-tv.plist",
    "~/Library/Saved Application State/dev.fredol.open-tv.savedState",
    "~/Library/WebKit/dev.fredol.open-tv",
  ]

  caveats <<~EOS
    Enjoying Fred TV? Remember to donate to the developer who builds it:
      GitHub Sponsors: https://github.com/sponsors/Fredolx
      PayPal:          https://paypal.me/fredolx
      Crypto:          https://github.com/Fredolx/open-tv#donate-crypto-thank-you
  EOS
end
