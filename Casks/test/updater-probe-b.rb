# This cask is updated by the tap pipeline (pipelines/updater-probe-b/).
# Do not edit the version or sha256 lines manually.
cask "updater-probe-b" do
  version "0.0.2"
  sha256 "01ce64a1a5d9a29c2a8ebeb50dac85cb0ea59418aa01212bbeb41d2b58c59088"

  url "https://github.com/edbfi/homebrew-taps/releases/download/updater-probe-b-latest/UpdaterProbeB-#{version}.dmg"
  name "Updater Probe B"
  desc "Test app that drives updater runs; not for installation"
  homepage "https://github.com/edbfi/edbfi-ci-playground"

  depends_on macos: :monterey

  app "Updater Probe B.app"
end
