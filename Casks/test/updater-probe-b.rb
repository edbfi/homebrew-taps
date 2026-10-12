# This cask is updated by the tap pipeline (pipelines/updater-probe-b/).
# Do not edit the version or sha256 lines manually.
cask "updater-probe-b" do
  version "0.0.1"
  sha256 "5f0b2f4c7b1a3e9d8c6a4b2e0f1d3c5b7a9e8d6c4b2a0f1e3d5c7b9a8e6d4c2b"

  url "https://github.com/edbfi/homebrew-taps/releases/download/updater-probe-b-latest/UpdaterProbeB-#{version}.dmg"
  name "Updater Probe B"
  desc "Test app that drives updater runs; not for installation"
  homepage "https://github.com/edbfi/edbfi-ci-playground"

  depends_on macos: :monterey

  app "Updater Probe B.app"
end
