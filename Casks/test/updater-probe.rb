# This cask is updated by the tap pipeline (pipelines/updater-probe/).
# Do not edit the version or sha256 lines manually.
cask "updater-probe" do
  version "0.0.3"
  sha256 "fc18022ce1acab18f1eaced8c2def8e7eb80f48776c4257bdd8a4512d6bb1c7d"

  url "https://github.com/edbfi/homebrew-taps/releases/download/updater-probe-latest/UpdaterProbe-#{version}.dmg"
  name "Updater Probe"
  desc "Test app that drives updater runs; not for installation"
  homepage "https://github.com/edbfi/edbfi-ci-playground"

  depends_on macos: :monterey

  app "Updater Probe.app"
end
