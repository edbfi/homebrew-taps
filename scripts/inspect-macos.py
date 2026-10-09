#!/usr/bin/env python3
"""Verify a DMG's bundle identity and every Mach-O architecture without launching it."""

import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


APPS = {
    "fcast-sender": ("FCast Sender.app", "org.fcast.FCastSender", {"arm64"}),
    "flixor": ("FlixorMac.app", "com.flixor.mac", {"arm64", "x86_64"}),
    "fredtv": ("Fred TV.app", "dev.fredol.open-tv", {"arm64", "x86_64"}),
    "paicord": ("Paicord.app", "com.llsc12.Paicord", {"arm64", "x86_64"}),
    "qbittorrent": ("qbittorrent.app", "org.qbittorrent.qBittorrent", {"arm64", "x86_64"}),
    "qview": ("qView.app", "com.interversehq.qView", {"arm64", "x86_64"}),
}


def inspect(token, dmg):
    app_name, identifier, required = APPS[token]
    with tempfile.TemporaryDirectory(prefix="tap-dmg-") as scratch:
        mount = Path(scratch) / "volume"
        subprocess.run(["hdiutil", "attach", str(dmg.resolve()), "-readonly", "-nobrowse",
                        "-mountpoint", str(mount)], input="Y\n", text=True,
                       check=True, stdout=subprocess.DEVNULL)
        try:
            app = mount / app_name
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            if info["CFBundleIdentifier"] != identifier:
                raise ValueError(f"Unexpected bundle identifier: {info['CFBundleIdentifier']}")
            main = app / "Contents/MacOS" / info["CFBundleExecutable"]
            if not main.is_file():
                raise ValueError("Missing main executable")
            binaries = {}
            for path in app.rglob("*"):
                if not path.is_file() or path.is_symlink():
                    continue
                kind = subprocess.check_output(["file", "-b", str(path)], text=True)
                if "Mach-O" not in kind:
                    continue
                arches = set(subprocess.check_output(["lipo", "-archs", str(path)], text=True).split())
                binaries[str(path.relative_to(app))] = sorted(arches)
                if not required <= arches:
                    raise ValueError(f"{path.relative_to(app)} lacks {required - arches}")
            if str(main.relative_to(app)) not in binaries:
                raise ValueError("Main executable is not Mach-O")
            if token == "fcast-sender":
                subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
                subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
            print(json.dumps({"token": token, "bundle_id": identifier,
                              "minimum_os": info.get("LSMinimumSystemVersion"),
                              "binaries": binaries}, indent=2))
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    inspect(sys.argv[1], Path(sys.argv[2]))
