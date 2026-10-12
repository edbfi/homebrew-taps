# This cask is updated by the tap pipeline (pipelines/updater-probe/).
# Do not edit the version or sha256 lines manually.
cask "updater-probe" do
  version "0.0.2"
  sha256 "56b842bf7a382fa3596af509c169b8c2fffc1540b2fa0ce012221280d3375770"

  url "https://github.com/edbfi/homebrew-taps/releases/download/updater-probe-latest/UpdaterProbe-#{version}.dmg"
  name "Updater Probe"
  desc "Test app that drives one updater push; not for installation"
  homepage "https://github.com/edbfi/edbfi-ci-playground"

  depends_on macos: :monterey

  app "Updater Probe.app"
end
