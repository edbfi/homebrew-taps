# This cask is updated by the tap pipeline (pipelines/qview/).
# Do not edit the version or sha256 lines manually.
cask "qview" do
  version "7.1"
  sha256 "fa34d0e54601b8557f4e879527b9bb1e728ace5c7c1c69cf126700ca4d0b5817"

  url "https://github.com/edbfi/homebrew-taps/releases/download/qview-latest/qView-#{version}.dmg"
  name "qView"
  desc "Practical and minimal image viewer"
  homepage "https://github.com/jurplel/qView/"

  depends_on macos: :monterey

  app "qView.app"

  postflight_steps do
    # Upstream ships unsigned builds; strip the quarantine attribute so Gatekeeper lets the app launch.
    run "/usr/bin/xattr",
        args:         ["-r", "-d", "com.apple.quarantine", "{{appdir}}/qView.app"],
        must_succeed: false
  end

  zap trash: [
    "~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.interversehq.qview.sfl*",
    "~/Library/Preferences/com.interversehq.qView.plist",
    "~/Library/Preferences/com.qview.qView.plist",
    "~/Library/Saved Application State/com.interversehq.qView.savedState",
  ]

  caveats <<~EOS
    Enjoying qView? Remember to support the project.
    qView has no donation page, so star it, report bugs, or contribute:
      https://github.com/jurplel/qView
  EOS
end
