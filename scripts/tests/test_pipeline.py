"""Regression tests for source updates, variant selection and release integrity."""

import importlib.util
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"scripts/{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class FormulaWriterTests(unittest.TestCase):
    def setUp(self):
        self.writer = module("write-formula")
        self.recipe = ('class Example < Formula\n  url "https://example.org/1.tar.gz"\n'
                       '  version "1"\n  sha256 "' + "a" * 64 + '"\n  revision 2\n\n'
                       '  bottle do\n    sha256 arm64_linux: "old"\n  end\n\n'
                       '  resource "dependency" do\n    sha256 "unchanged"\n  end\nend\n')
        self.release = {"version": "2", "url": "https://example.org/2.tar.gz"}

    def test_updates_only_source_and_removes_stale_bottles(self):
        result = self.writer.rewrite(self.recipe, self.release, "b" * 64)
        self.assertIn('  version "2"', result)
        self.assertIn('    sha256 "unchanged"', result)
        self.assertNotIn("bottle do", result)
        self.assertNotIn("revision", result)

    def test_unchanged_source_preserves_bottles(self):
        release = {"version": "1", "url": "https://example.org/1.tar.gz"}
        self.assertEqual(self.recipe, self.writer.rewrite(self.recipe, release, "a" * 64))

    def test_same_version_changed_bytes_requires_review(self):
        release = {"version": "1", "url": "https://example.org/1.tar.gz"}
        with self.assertRaisesRegex(ValueError, "existing version"):
            self.writer.rewrite(self.recipe, release, "b" * 64)

    def test_injection_and_duplicate_fields_fail(self):
        for release in ({**self.release, "version": '2";system("bad")'},
                        {**self.release, "url": 'https://example.org/#{system("bad")}' }):
            with self.assertRaises(ValueError):
                self.writer.rewrite(self.recipe, release, "b" * 64)
        with self.assertRaises(ValueError):
            self.writer.rewrite(self.recipe + '  version "3"\n', self.release, "b" * 64)


class BottleTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.work = Path(self.scratch.name)
        self.original = Path.cwd()
        os.chdir(self.work)
        self.addCleanup(os.chdir, self.original)
        Path("Formula").mkdir()
        Path("Formula/example.rb").write_text('  version "1"\n')
        Path("pipelines").mkdir()
        Path("pipelines/bottles.json").write_text('["example"]\n')
        self.bottles = self.work / "bottles"
        self.bottles.mkdir()
        self.root_url = "https://example.org/release"
        for arch in ("x86_64_linux", "arm64_linux"):
            local = f"example--1.{arch}.bottle.tar.gz"
            (self.bottles / local).write_bytes(b"binary")
            data = {"edbfi/taps/example": {
                "formula": {"pkg_version": "1"},
                "bottle": {"root_url": self.root_url, "tags": {arch: {
                    "local_filename": local, "filename": local.replace("--", "-"),
                    "sha256": hashlib.sha256(b"binary").hexdigest(),
                }}},
            }}
            (self.bottles / f"example.{arch}.bottle.json").write_text(json.dumps(data))
        (self.bottles / "example-1-source.tar.gz").write_bytes(b"source")
        self.verifier = module("verify-bottles")

    def test_complete_release_normalizes_names_and_hashes_metadata(self):
        self.verifier.verify(self.bottles, self.root_url)
        self.assertTrue((self.bottles / "example-1.arm64_linux.bottle.tar.gz").exists())
        self.assertEqual(len((self.bottles / "SHA256SUMS").read_text().splitlines()), 5)

    def test_missing_architecture_rejects_release(self):
        (self.bottles / "example.arm64_linux.bottle.json").unlink()
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            self.verifier.verify(self.bottles, self.root_url)

    def test_corrupted_bottle_rejects_release(self):
        (self.bottles / "example--1.arm64_linux.bottle.tar.gz").write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "Checksum"):
            self.verifier.verify(self.bottles, self.root_url)

    def test_missing_source_rejects_release(self):
        (self.bottles / "example-1-source.tar.gz").unlink()
        with self.assertRaisesRegex(ValueError, "Missing corresponding"):
            self.verifier.verify(self.bottles, self.root_url)

    def test_wrong_recipe_version_rejects_release(self):
        Path("Formula/example.rb").write_text('  version "2"\n')
        with self.assertRaisesRegex(ValueError, "version differs"):
            self.verifier.verify(self.bottles, self.root_url)

    def test_unapproved_binary_rejects_release(self):
        Path("Formula/other.rb").write_text('  version "1"\n')
        Path("pipelines/bottles.json").write_text('["other"]\n')
        with self.assertRaisesRegex(ValueError, "Unexpected formula"):
            self.verifier.verify(self.bottles, self.root_url)

    def test_unapproved_binary_without_metadata_rejects_release(self):
        (self.bottles / "unapproved.bottle.tar.gz").write_bytes(b"binary")
        with self.assertRaisesRegex(ValueError, "Unexpected release assets"):
            self.verifier.verify(self.bottles, self.root_url)


class ResolverTests(unittest.TestCase):
    def resolve(self, token, routes):
        with tempfile.TemporaryDirectory() as scratch:
            work = Path(scratch)
            (work / "routes.json").write_text(json.dumps(routes))
            curl = work / "curl"
            curl.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
routes = json.loads(pathlib.Path(os.environ["ROUTES"]).read_text())
status, body = routes.get(args[-1], [404, {}])
pathlib.Path(args[args.index("-o") + 1]).write_text(json.dumps(body))
print(status, end="")
''')
            curl.chmod(0o755)
            env = {**os.environ, "PATH": f"{work}:{os.environ['PATH']}", "GH_TOKEN": "fixture",
                   "ROUTES": str(work / "routes.json")}
            return subprocess.run(["bash", str(ROOT / "scripts/resolve.sh"), token],
                                  cwd=work, env=env, capture_output=True, text=True)

    def test_qview_rejects_legacy_asset(self):
        result = self.resolve("qview", {"https://api.github.com/repos/jurplel/qView/releases/latest":
                              [200, {"tag_name": "7.1", "assets": [{"name": "qView-7.1-legacy.dmg"}]}]})
        self.assertNotEqual(result.returncode, 0)

    def qbittorrent_release(self, **overrides):
        name = "qbittorrent-5.2.3.dmg"
        return {"tag_name": "release-5.2.3", "draft": False, "prerelease": False,
                "assets": [{"name": name, "browser_download_url":
                            f"https://github.com/qbittorrent/qBittorrent/releases/download/release-5.2.3/{name}"}],
                **overrides}

    def resolve_qbittorrent(self, release, status=200):
        return self.resolve("qbittorrent", {
            "https://api.github.com/repos/qbittorrent/qBittorrent/releases/latest": [status, release],
        })

    def test_qbittorrent_selects_standard_desktop_dmg(self):
        release = self.qbittorrent_release()
        release["assets"] += [{"name": name} for name in (
            "qbittorrent-5.2.3_lt20.dmg", "qbittorrent-5.2.3.dmg.asc",
            "qbittorrent-5.2.3.tar.xz", "qbittorrent-5.2.3_x86_64.AppImage",
            "qbittorrent_5.2.3_x64_setup.exe")]
        result = self.resolve_qbittorrent(release)
        self.assertEqual(result.returncode, 0, result.stderr)
        fields = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual(fields["version"], "5.2.3")
        self.assertEqual(fields["download_url"], release["assets"][0]["browser_download_url"])
        self.assertEqual(fields["ref"], "release-5.2.3")
        self.assertEqual(fields["changes_url"], "https://github.com/qbittorrent/qBittorrent/releases/tag/release-5.2.3")
        self.assertEqual(fields["asset"], "qBittorrent-5.2.3.dmg")
        self.assertEqual(fields["release_tag"], "qbittorrent-latest")
        self.assertEqual(fields["cask_file"], "Casks/network/qbittorrent.rb")

    def test_qbittorrent_rejects_unsafe_or_unstable_releases(self):
        for tag in ("", "v5.2.3", "release-5.2", "release-5.3.0beta1",
                    "release-5.2.3/evil", 'release-5.2.3\";system(\"bad\")'):
            with self.subTest(tag=tag):
                result = self.resolve_qbittorrent(self.qbittorrent_release(tag_name=tag))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unexpected upstream tag", result.stderr)
        for flag in ("draft", "prerelease"):
            with self.subTest(flag=flag):
                result = self.resolve_qbittorrent(self.qbittorrent_release(**{flag: True}))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("stable published release", result.stderr)

    def test_qbittorrent_rejects_missing_or_duplicate_standard_dmg(self):
        release = self.qbittorrent_release()
        for assets in ([], [{"name": "qbittorrent-5.2.3_lt20.dmg"}], release["assets"] * 2):
            with self.subTest(assets=assets):
                result = self.resolve_qbittorrent({**release, "assets": assets})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Expected exactly one", result.stderr)

    def test_qbittorrent_rejects_unexpected_download_url(self):
        for url in (None, "https://example.org/qbittorrent-5.2.3.dmg",
                    "https://github.com/qbittorrent/qBittorrent/releases/download/release-5.2.2/qbittorrent-5.2.3.dmg",
                    "https://github.com/qbittorrent/qBittorrent/releases/download/release-5.2.3/qbittorrent-5.2.3_lt20.dmg"):
            with self.subTest(url=url):
                release = self.qbittorrent_release()
                release["assets"][0]["browser_download_url"] = url
                result = self.resolve_qbittorrent(release)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unexpected DMG download URL", result.stderr)

    def test_qbittorrent_missing_release_skips_but_api_failure_does_not(self):
        result = self.resolve_qbittorrent({}, status=404)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "skip=true")
        result = self.resolve_qbittorrent({}, status=403)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTP 403", result.stderr)

    def test_fredtv_rejects_nonuniversal_asset(self):
        result = self.resolve("fredtv", {"https://api.github.com/repos/Fredolx/open-tv/releases/latest":
                              [200, {"tag_name": "v1.9.1", "assets": [{"name": "Fred.TV_1.9.1_arm64.dmg"}]}]})
        self.assertNotEqual(result.returncode, 0)

    def test_flixor_rejects_ambiguous_assets(self):
        result = self.resolve("flixor", {"https://api.github.com/repos/Flixorui/flixor/releases/latest":
                              [200, {"tag_name": "beta2.4.0", "assets": [{"name": "a.dmg"}, {"name": "b.dmg"}]}]})
        self.assertIn("Expected exactly one", result.stderr)
        self.assertNotEqual(result.returncode, 0)

    def test_sender_delayed_cdn_is_skip(self):
        result = self.resolve("fcast-sender", {
            "https://api.github.com/repos/futo-org/fcast/releases?per_page=100&page=1":
            [200, [{"draft": False, "tag_name": "sender-0.0.3-beta", "published_at": "2026-01-01"}]],
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "skip=true")

    def paicord_routes(self, matching=True):
        base = "https://api.github.com/repos/llsc12/Paicord"
        sha = "a" * 40
        tag = "paicord-nightly-123"
        url = f"https://github.com/llsc12/Paicord/releases/download/{tag}/Paicord-macOS-aaaaaaa.dmg"
        return {
            base + "/actions/workflows/build.yml/runs?branch=main&event=push&status=success&per_page=1":
            [200, {"total_count": 1, "workflow_runs": [{"head_sha": sha, "id": 123}]}],
            base + f"/releases/tags/{tag}": [200, {"draft": False, "tag_name": tag, "assets": [
                {"name": "Paicord-macOS-aaaaaaa.dmg", "browser_download_url": url}]}],
            base + f"/commits/{tag}": [200, {"sha": sha if matching else "b" * 40}],
            base + f"/commits/{sha}": [200, {"commit": {"author": {"date": "2026-01-02T00:00:00Z"}}}],
        }

    def test_paicord_immutable_release(self):
        result = self.resolve("paicord", self.paicord_routes())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("version=2026-01-02-aaaaaaa", result.stdout)
        self.assertIn("/releases/download/paicord-nightly-123/", result.stdout)
        self.assertNotIn("nightly.link", result.stdout)

    def test_paicord_mismatched_commit_fails(self):
        result = self.resolve("paicord", self.paicord_routes(matching=False))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)

    def test_discovery_separates_kinds(self):
        casks = subprocess.check_output(["bash", str(ROOT / "scripts/discover.sh")], text=True)
        formulae = subprocess.check_output(["bash", str(ROOT / "scripts/discover.sh"), "", "formula"], text=True)
        self.assertEqual(set(json.loads(casks)["cask"]),
                         {"fcast-sender", "flixor", "fredtv", "paicord", "qbittorrent", "qview"})
        self.assertEqual(set(module("inspect-macos").APPS), set(json.loads(casks)["cask"]))
        self.assertEqual(set(json.loads(formulae)["formula"]), {"qview", "fredtv", "fcast-sender", "pipewire-gstreamer"})

    def test_discovery_does_not_hide_missing_package_files(self):
        with tempfile.TemporaryDirectory() as scratch:
            work = Path(scratch)
            (work / "scripts/lib").mkdir(parents=True)
            shutil.copy2(ROOT / "scripts/lib/common.sh", work / "scripts/lib/common.sh")
            shutil.copy2(ROOT / "scripts/discover.sh", work / "scripts/discover.sh")
            pipeline = work / "pipelines/broken"
            pipeline.mkdir(parents=True)
            for kind, message in (("cask", "Missing cask resolver"), ("formula", "Missing Formula")):
                (pipeline / "config.env").write_text(
                    f'PACKAGE_KINDS={kind}\nDISPLAY_NAME=Broken\nUPSTREAM_URL=https://example.org\nASSET_PREFIX=Broken\n')
                result = subprocess.run(["bash", str(work / "scripts/discover.sh"), "", kind],
                                        text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
