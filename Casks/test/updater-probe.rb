# This cask is updated by the tap pipeline (pipelines/updater-probe/).
# Do not edit the version or sha256 lines manually.
cask "updater-probe" do
  version "0.0.1"
  sha256 "f9e64f0dd543ae04f051f44f3b3c13582287216396efee31bcd71b7f720f7d41"

  url "https://github.com/edbfi/homebrew-taps/releases/download/updater-probe-latest/UpdaterProbe-#{version}.dmg"
  name "Updater Probe"
  desc "Test app that drives one updater push; not for installation"
  homepage "https://github.com/edbfi/edbfi-ci-playground"

  depends_on macos: :monterey

  app "Updater Probe.app"
end
