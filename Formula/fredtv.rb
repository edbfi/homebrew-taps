class Fredtv < Formula
  desc "Fast and powerful IPTV app"
  homepage "https://github.com/Fredolx/open-tv"
  url "https://github.com/Fredolx/open-tv/archive/8fac47df85d4b242b0de317cb068c509303f89f2.tar.gz"
  version "1.9.1"
  sha256 "acb256f2b42720b94b04d61280eee05a1fca7d866cb347e73c3bb2310664e90b"
  license "GPL-2.0-only"

  depends_on "node@20" => :build # Angular 17's supported upstream build toolchain.
  depends_on "pkgconf" => :build
  depends_on "rust" => :build
  depends_on "cairo"
  depends_on "ffmpeg"
  depends_on "gdk-pixbuf"
  depends_on "glib"
  depends_on "gtk+3"
  depends_on "libsoup"
  depends_on :linux
  depends_on "mpv"
  depends_on "openssl@3"
  depends_on "pango"
  depends_on "webkitgtk"
  depends_on "yt-dlp"

  def install
    # openssl-sys must take openssl@3, not the openssl@4 that other dependencies install.
    ENV["OPENSSL_DIR"] = formula_opt_prefix("openssl@3")
    system "npm", "ci", "--no-audit", "--no-fund"
    system "npm", "run", "tauri", "build", "--", "--no-bundle", "--", "--locked"
    libexec.install "src-tauri/target/release/open_tv"
    (bin/"fredtv").write_env_script libexec/"open_tv",
                                  PATH:                           "#{HOMEBREW_PREFIX}/bin:$PATH",
                                  WEBKIT_DISABLE_DMABUF_RENDERER: "1"
    (share/"applications/dev.fredol.open-tv.desktop").write <<~EOS
      [Desktop Entry]
      Type=Application
      Name=Fred TV
      Exec=#{opt_bin}/fredtv
      Icon=dev.fredol.open-tv
      Categories=AudioVideo;Player;
      Terminal=false
      StartupWMClass=open_tv
    EOS
    (share/"icons/hicolor/128x128/apps").install "src-tauri/icons/128x128.png" => "dev.fredol.open-tv.png"
    (share/"licenses/fredtv").install "LICENSE"
  end

  def caveats
    <<~EOS
      This formula builds from source. Binary redistribution is pending clarification of
      the upstream GPL-2.0 terms with its OpenSSL 3 dependency; no tap bottle is published.
      Launch with fredtv, or add #{HOMEBREW_PREFIX}/share to your desktop session's XDG_DATA_DIRS.
      A running X11 or Wayland session and audio service are required.
      Uninstall preserves settings and recordings.
      Support Fred TV: https://github.com/sponsors/Fredolx
    EOS
  end

  test do
    assert_path_exists libexec/"open_tv"
    assert_match "Exec=#{opt_bin}/fredtv", (share/"applications/dev.fredol.open-tv.desktop").read
    assert_match "mpv", shell_output("#{formula_opt_bin("mpv")}/mpv --version")
    system formula_opt_bin("ffmpeg")/"ffmpeg", "-hide_banner", "-loglevel", "error",
           "-f", "lavfi", "-i", "color=c=red:s=32x32:d=0.1", "-c:v", "ffv1", testpath/"sample.mkv"
    system formula_opt_bin("mpv")/"mpv", "--no-config", "--vo=null", "--ao=null", "--frames=1", testpath/"sample.mkv"
    system formula_opt_bin("yt-dlp")/"yt-dlp", "--version"
  end
end
