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
        for content in (CASK.replace('  version "1.0.0"', '  version :latest'),
                        CASK.replace('  version "1.0.0"\n', '  version "1.0.0"\n  version "1.0.0"\n')):
            with self.subTest(content=content):
                result, output = self.rewrite(content=content)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("exactly one version and one sha256 line", result.stderr)
                self.assertEqual(output, content)

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
