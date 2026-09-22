# This cask is auto-updated by the update-casks workflow (pipelines/qbittorrent/).
# Do not edit the version or sha256 lines manually.
cask "qbittorrent" do
  version "5.2.3"
  sha256 "9e37f6c7ff848c7bdd3c10167614c0cb78c00e2ddcc323f1ad3ac6c008a0481f"

  url "https://github.com/edbfi/homebrew-taps/releases/download/qbittorrent-latest/qBittorrent-#{version}.dmg"
  name "qBittorrent"
  desc "BitTorrent client"
  homepage "https://www.qbittorrent.org/"

  conflicts_with cask: [
    "c0re100-qbittorrent",
    "qbittorrent@lt20",
  ]
  depends_on macos: :ventura

  app "qbittorrent.app", target: "qBittorrent.app"

  postflight_steps do
    # Strip quarantine from the installed bundle so Gatekeeper lets the app launch.
    run "/usr/bin/xattr",
        args:         ["-r", "-d", "com.apple.quarantine", "{{appdir}}/qBittorrent.app"],
        must_succeed: false
  end

  zap trash: [
    "~/.config/qBittorrent",
    "~/Library/Application Support/qBittorrent",
    "~/Library/Caches/qBittorrent",
    "~/Library/Preferences/org.qbittorrent.qBittorrent.plist",
    "~/Library/Preferences/qBittorrent",
    "~/Library/Saved Application State/org.qbittorrent.qBittorrent.savedState",
  ]

  caveats <<~EOS
    Enjoying qBittorrent? Remember to support the project:
      https://www.qbittorrent.org/donate
  EOS
end
