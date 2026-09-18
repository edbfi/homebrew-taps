# This cask is auto-updated by the update-casks workflow (pipelines/fcast-sender/).
# Do not edit the version or sha256 lines manually.
cask "fcast-sender" do
  version "0.0.3"
  sha256 "53ca328abc4f267e29077ffba96a1933867be91e2ee8164b9ed24eb9a3f09204"

  url "https://github.com/edbfi/homebrew-taps/releases/download/fcast-sender-latest/FCastSender-#{version}.dmg"
  name "FCast Sender"
  desc "Cast video and audio to FCast receivers"
  homepage "https://fcast.org/"

  depends_on arch: :arm64
  depends_on :macos

  app "FCast Sender.app"

  zap trash: [
    "~/Library/Application Support/org.fcast.FCastSender",
    "~/Library/Caches/org.fcast.FCastSender",
    "~/Library/HTTPStorages/org.fcast.FCastSender",
    "~/Library/Preferences/org.fcast.FCastSender.plist",
    "~/Library/Saved Application State/org.fcast.FCastSender.savedState",
  ]

  caveats <<~EOS
    Enjoying FCast Sender? Remember to support the project.
    FCast has no donation page, so star it, report bugs, or contribute:
      https://github.com/futo-org/fcast
  EOS
end
