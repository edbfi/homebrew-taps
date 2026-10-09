# This cask is updated by the tap pipeline (pipelines/flixor/).
# Do not edit the version or sha256 lines manually.
cask "flixor" do
  version "beta2.4.0"
  sha256 "2b87d3bc7f7313e45a4d32270fc82d824f10995230d72885124f102e58998b9a"

  url "https://github.com/edbfi/homebrew-taps/releases/download/flixor-latest/Flixor-#{version}.dmg"
  name "Flixor"
  desc "Native Plex media client with a Netflix-like UI"
  homepage "https://github.com/Flixorui/flixor"

  depends_on macos: :ventura

  app "FlixorMac.app"

  postflight_steps do
    # Upstream ships unsigned builds; strip the quarantine attribute so Gatekeeper lets the app launch.
    run "/usr/bin/xattr",
        args:         ["-r", "-d", "com.apple.quarantine", "{{appdir}}/FlixorMac.app"],
        must_succeed: false
  end

  zap trash: [
    "~/Library/Application Support/com.flixor.mac",
    "~/Library/Caches/com.flixor.mac",
    "~/Library/HTTPStorages/com.flixor.mac",
    "~/Library/Preferences/com.flixor.mac.plist",
    "~/Library/Saved Application State/com.flixor.mac.savedState",
    "~/Library/WebKit/com.flixor.mac",
  ]

  caveats <<~EOS
    Enjoying Flixor? Remember to donate to the developer who builds it:
      Ko-fi: https://ko-fi.com/flixor
  EOS
end
