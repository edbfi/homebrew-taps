# This cask is auto-updated by the update-casks workflow (pipelines/paicord/).
# Do not edit the version or sha256 lines manually.
cask "paicord" do
  version "2026-08-05-473c780"
  sha256 "009956d1e922232dc5e858aba9219d90f3fba23ea99255253db1771dcefe61d7"

  url "https://github.com/edbfi/homebrew-taps/releases/download/paicord-latest/Paicord-#{version}.dmg"
  name "Paicord"
  desc "Native Discord client, written in Swift"
  homepage "https://github.com/llsc12/Paicord"

  depends_on macos: :sonoma

  app "Paicord.app"

  postflight_steps do
    # Upstream ships unsigned builds; strip the quarantine attribute so Gatekeeper lets the app launch.
    run "/usr/bin/xattr",
        args:         ["-r", "-d", "com.apple.quarantine", "{{appdir}}/Paicord.app"],
        must_succeed: false
  end

  zap trash: [
    "~/Library/Application Support/com.llsc12.Paicord",
    "~/Library/Caches/com.llsc12.Paicord",
    "~/Library/HTTPStorages/com.llsc12.Paicord",
    "~/Library/Preferences/com.llsc12.Paicord.plist",
    "~/Library/Saved Application State/com.llsc12.Paicord.savedState",
    "~/Library/WebKit/com.llsc12.Paicord",
  ]

  caveats <<~EOS
    Paicord is an unofficial, third-party Discord client.
    Using it is a violation of Discord's Terms of Service.
    Your account may be suspended or banned. Use at your own risk.

    Enjoying Paicord? Remember to donate to the developer who builds it:
      GitHub Sponsors: https://github.com/sponsors/llsc12
  EOS
end
