"""Run cask rewrite/discovery against temporary data, without release operations."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CASK = 'cask "fixture" do\n  version "1.0.0"\n  sha256 "' + "a" * 64 + '"\n  url "https://example.invalid/fixture.dmg"\nend\n'


class PipelineTests(unittest.TestCase):
    def test_publisher_preserves_existing_downloads(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            fake = work / "gh"
            fake.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\np=Path(os.environ['CALLS'])\nwith p.open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\nup=p.with_suffix('.uploaded')\nif sys.argv[1:3]==['release','upload']: up.write_text(Path(sys.argv[4]).name)\nif sys.argv[1:3]==['release','view']: print(os.environ.get('EXISTING','qView-7.1.dmg')); up.exists() and print(up.read_text())\nif sys.argv[1:3]==['release','download']: (Path(sys.argv[sys.argv.index('--dir')+1])/'qView-7.1.dmg').write_bytes(os.environ.get('HOSTED_BYTES','fixture').encode())\n")
            fake.chmod(0o755)
            asset = work / "qView-7.1.dmg"
            asset.write_bytes(b"fixture")
            notes = work / "notes.md"
            notes.write_text("fixture")
            calls = work / "calls.jsonl"
            env = {**os.environ, "PATH": str(work) + os.pathsep + os.environ["PATH"], "CALLS": str(calls)}
            result = subprocess.run(["bash", str(ROOT / "scripts/publish-release.sh"), "qview", str(asset), str(notes)],
                                    cwd=work, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            commands = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertTrue(any(c[:2] == ["release", "edit"] for c in commands))
            self.assertFalse(any(c[:2] in (["release", "delete-asset"], ["release", "upload"]) for c in commands))
            self.assertTrue(any(c[:2] == ["release", "download"] for c in commands))
            env["HOSTED_BYTES"] = "different"
            mismatch = subprocess.run(["bash", str(ROOT / "scripts/publish-release.sh"), "qview", str(asset), str(notes)],
                                      cwd=work, env=env, capture_output=True, text=True)
            self.assertNotEqual(mismatch.returncode, 0)
            self.assertIn("differs from upstream", mismatch.stderr)
            self.assertEqual(asset.read_bytes(), b"fixture")
            env.pop("HOSTED_BYTES")
            calls.unlink()
            env["EXISTING"] = "qView-7.0.dmg"
            upload = subprocess.run(["bash", str(ROOT / "scripts/publish-release.sh"), "qview", str(asset), str(notes)],
                                    cwd=work, env=env, capture_output=True, text=True)
            self.assertEqual(upload.returncode, 0, upload.stderr)
            uploads = [c for c in map(json.loads, calls.read_text().splitlines()) if c[:2] == ["release", "upload"]]
            self.assertEqual(len(uploads), 1)
            self.assertNotIn("--clobber", uploads[0])

    def rewrite(self, version="1.2.3", digest="b" * 64, content=CASK):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.rb"
            path.write_text(content)
            result = subprocess.run(["bash", str(ROOT / "scripts/write-cask.sh"), str(path), version, digest],
                                    cwd=ROOT, capture_output=True, text=True)
            return result, path.read_text()

    def test_valid_rewrite_changes_only_machine_owned_lines(self):
        self.assertIsNotNone(shutil.which("ruby"), "Ruby syntax validation is required")
        result, output = self.rewrite()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, CASK.replace('version "1.0.0"', 'version "1.2.3"').replace("a" * 64, "b" * 64))

    def test_unsafe_version_and_bad_hash_leave_input_untouched(self):
        for version, digest in [("$(touch unwanted)", "b" * 64), ("1.2.3", "not-a-digest")]:
            with self.subTest(version=version):
                result, output = self.rewrite(version, digest)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output, CASK)

    def test_missing_machine_owned_anchor_fails(self):
        result, _output = self.rewrite(content=CASK.replace('  version "1.0.0"', '  version :latest'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("version line was not rewritten", result.stderr)

    def test_discovery_matches_all_casks_and_rejects_unknown_filter(self):
        result = subprocess.run(["bash", "scripts/discover.sh"], cwd=ROOT, capture_output=True, text=True, check=True)
        tokens = json.loads(result.stdout)["cask"]
        expected = sorted(file.stem for file in (ROOT / "Casks").glob("**/*.rb"))
        self.assertEqual(sorted(tokens), expected)
        self.assertEqual(len(tokens), len(set(tokens)))
        one = subprocess.run(["bash", "scripts/discover.sh", tokens[0]], cwd=ROOT, capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(one.stdout), {"cask": [tokens[0]]})
        unknown = subprocess.run(["bash", "scripts/discover.sh", "missing-fixture"], cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(unknown.returncode, 0)


if __name__ == "__main__":
    unittest.main()
