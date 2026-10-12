# This cask is updated by the tap pipeline (pipelines/updater-probe/).
# Do not edit the version or sha256 lines manually.
cask "updater-probe" do
  version "0.0.2"
  sha256 "de8e45b4f9ba040483483583b8e059c7246720fa056b584a27f3191313868aec"

  url "https://github.com/edbfi/homebrew-taps/releases/download/updater-probe-latest/UpdaterProbe-#{version}.dmg"
  name "Updater Probe"
  desc "Test app that drives updater runs; not for installation"
  homepage "https://github.com/edbfi/edbfi-ci-playground"

  depends_on macos: :monterey

  app "Updater Probe.app"
end
