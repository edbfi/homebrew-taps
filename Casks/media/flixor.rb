# This cask is updated by the tap pipeline (pipelines/flixor/).
# Do not edit the version or sha256 lines manually.
cask "flixor" do
  version "1.9.6"
  sha256 "da92479540b20159b4b82c8a34e2a8916e44fa74223cc2f04a52ce629214141f"

  url "https://github.com/edbfi/homebrew-taps/releases/download/flixor-latest/Flixor-#{version}.dmg"
  name "Flixor"
  desc "Native Plex media client with a Netflix-like UI"
  homepage "https://github.com/Flixorui/flixor"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Flixor.app"

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
