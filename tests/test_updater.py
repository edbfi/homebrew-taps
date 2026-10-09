"""The cask updater's shell stages against a fake gh, a fake curl and a local origin."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
QVIEW_LATEST = "https://api.github.com/repos/jurplel/qView/releases/latest"
FAKE_CURL = '''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
routes = json.loads(pathlib.Path(os.environ["ROUTES"]).read_text())
status, body = routes.get(args[-1], [404, {}])
if body == "stall":
    import time
    time.sleep(60)
data = body if isinstance(body, str) else json.dumps(body)
pathlib.Path(args[args.index("-o") + 1]).write_text(data)
if "-w" in args:
    print(status, end="")
elif status >= 400:
    sys.exit(22)
'''


def sha(data):
    return hashlib.sha256(data.encode()).hexdigest()


def claim(version, digest):
    return f"version={version}\nsha256={digest}\n"


class UpdaterTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.state = self.tmp / "gh"
        (self.state / "releases").mkdir(parents=True)
        (self.state / "artifacts").mkdir()
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        (bin_dir / "gh").write_text(f'#!/bin/sh\nexec python3 "{ROOT / "tests/fake_gh.py"}" "$@"\n')
        (bin_dir / "curl").write_text(FAKE_CURL)
        for tool in bin_dir.iterdir():
            tool.chmod(0o755)
        self.routes = {}
        self.env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "FAKE_GH": str(self.state), "ROUTES": str(self.tmp / "routes.json"), "GH_TOKEN": "fixture",
                    "GH_REPO": "edbfi/homebrew-taps", "GITHUB_RUN_ID": "1", "GITHUB_RUN_ATTEMPT": "1"}

    def run_script(self, *args, env=None, cwd=None):
        (self.tmp / "routes.json").write_text(json.dumps(self.routes))
        work = cwd or self.tmp / "work"
        work.mkdir(exist_ok=True)
        return subprocess.run(["bash", *map(str, args)], cwd=work, env={**self.env, **(env or {})},
                              capture_output=True, text=True)

    def bash(self, code, env=None):
        return self.run_script("-c", f'source "{ROOT}/scripts/lib/common.sh"; {code}', env=env)

    def calls(self):
        path = self.state / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def release(self, tag, **assets):
        (self.state / "releases" / tag).mkdir(parents=True, exist_ok=True)
        for name, data in assets.items():
            (self.state / "releases" / tag / name).write_text(data)

    def artifact(self, name, files):
        directory = self.state / "artifacts" / name
        directory.mkdir(parents=True)
        for file, data in files.items():
            (directory / file).write_text(data)
        return directory


class HelperTests(UpdaterTestCase):
    def test_kv_rejects_line_breaks(self):
        for value in ("1.0\nskip=true", "1.0\rskip=true"):
            with self.subTest(value=value):
                result = self.bash('kv out version "$VALUE"', env={"VALUE": value})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("multi-line value", result.stderr)
        self.assertEqual(self.bash("kv out version 1.0 && cat out").stdout, "version=1.0\n")

    def test_version_newer_is_sort_v(self):
        cases = [("7.2", "7.1", True), ("7.1", "7.1", False), ("7.0", "7.1", False), ("0.0.10", "0.0.9", True),
                 ("2026-09-27-5c76f36", "2026-09-16-e1f9503", True), ("beta2.5.0", "beta2.4.0", True),
                 # Not chronology: these need a human (check-update.sh).
                 ("1.0.0", "beta2.4.0", False), ("2026-09-27-0aaaaaa", "2026-09-27-fffffff", False),
                 ("2026-09-27-fffffff", "2026-09-27-0aaaaaa", False)]
        for new, old, expected in cases:
            with self.subTest(new=new, old=old):
                result = self.bash(f'version_newer "{new}" "{old}"')
                self.assertEqual(result.returncode == 0, expected)

    def test_read_claim_accepts_only_exact_claims(self):
        good = claim("7.2", "a" * 64)
        path = self.tmp / "work" / "claim.env"
        path.parent.mkdir()
        path.write_text(good)
        result = self.bash('read_claim claim.env && echo "$CLAIM_VERSION $CLAIM_SHA256"')
        self.assertEqual(result.stdout.strip(), "7.2 " + "a" * 64, result.stderr)
        for bad in (good + "extra=1\n", "version=7.2\n", good.replace("sha256", "version"),
                    good.replace("\n", "\r\n"), claim("7.2", "A" * 64), claim("$(id)", "a" * 64),
                    claim("7.2", "a" * 63), "x" * 300 + "\n" + good):
            with self.subTest(claim=bad):
                path.write_text(bad)
                self.assertNotEqual(self.bash("read_claim claim.env").returncode, 0)
        path.unlink()
        (self.tmp / "work" / "real.env").write_text(good)
        path.symlink_to("real.env")
        self.assertNotEqual(self.bash("read_claim claim.env").returncode, 0)

    def test_release_json_tells_missing_from_failing(self):
        self.release("qview-latest", **{"qView-7.1.dmg": "bytes"})
        probe = 'if release_json "$TAG" out.json; then echo found; else echo missing; fi'
        self.assertEqual(self.bash(probe, env={"TAG": "qview-latest"}).stdout.strip(), "found")
        self.assertEqual(self.bash(probe, env={"TAG": "absent"}).stdout.strip(), "missing")
        failing = self.bash(probe, env={"TAG": "qview-latest", "FAKE_GH_API_STATUS": "500"})
        self.assertNotEqual(failing.returncode, 0)
        self.assertEqual(failing.stdout, "")
        self.assertIn("Could not read release", failing.stderr)

    def test_intake_claim_requires_one_regular_claim_file(self):
        self.artifact("good", {"claim.env": claim("7.2", "a" * 64)})
        self.assertTrue(self.bash("intake_claim good").stdout.strip().endswith("/claim.env"))
        self.artifact("two", {"claim.env": "x", "other": "y"})
        self.artifact("renamed", {"other.env": "x"})
        linked = self.artifact("linked", {})
        (linked / "claim.env").symlink_to("/etc/hostname")
        for name in ("two", "renamed", "linked", "absent"):
            with self.subTest(artifact=name):
                self.assertNotEqual(self.bash(f"intake_claim {name}").returncode, 0)


class ResolverRecordTests(UpdaterTestCase):
    def resolve_fake(self, body):
        root = self.tmp / "repo"
        (root / "pipelines/fake").mkdir(parents=True, exist_ok=True)
        (root / "Casks/test").mkdir(parents=True, exist_ok=True)
        (root / "Casks/test/fake.rb").write_text('cask "fake" do\n  version "1.0"\nend\n')
        (root / "pipelines/fake/config.env").write_text('DISPLAY_NAME="Fake"\nUPSTREAM_URL="https://example.invalid"\n'
                                                        'ASSET_PREFIX="Fake"\n')
        (root / "pipelines/fake/resolve.sh").write_text(
            f'source "{ROOT}/scripts/lib/common.sh"\n{body}\n')
        return self.run_script(ROOT / "scripts/resolve.sh", "fake", env={"REPO_ROOT": str(root)})

    def test_resolver_records_cannot_be_overridden_or_smuggled(self):
        url = "https://example.invalid/Fake-1.1.dmg"
        ok = self.resolve_fake(f'kv "$RESOLVE_OUT" version 1.1\nkv "$RESOLVE_OUT" download_url {url}')
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertIn("version=1.1", ok.stdout)
        for body, message in ((f'kv "$RESOLVE_OUT" version 1.1\nkv "$RESOLVE_OUT" skip true\n'
                               f'kv "$RESOLVE_OUT" skip false\nkv "$RESOLVE_OUT" download_url {url}', "more than once"),
                              (f'kv "$RESOLVE_OUT" version 1.1\nkv "$RESOLVE_OUT" download_url {url}\n'
                               'kv "$RESOLVE_OUT" asset evil.dmg', "Unexpected resolver record"),
                              (f'kv "$RESOLVE_OUT" version 1.1\nkv "$RESOLVE_OUT" download_url "{url}\nskip=true"',
                               "multi-line value")):
            with self.subTest(message=message):
                result = self.resolve_fake(body)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertNotIn("skip=true", result.stdout)


class CheckUpdateTests(UpdaterTestCase):
    def check(self, version, **env):
        return self.run_script(ROOT / "scripts/check-update.sh", "qview", version, f"qView-{version}.dmg", env=env)

    def test_only_a_newer_upstream_is_an_update(self):
        newer = self.check("7.2")
        self.assertEqual(newer.returncode, 0, newer.stderr)
        self.assertIn("needed=true", newer.stdout)
        older = self.check("7.0")
        self.assertNotEqual(older.returncode, 0)
        self.assertIn("is not newer", older.stderr)

    def test_current_version_needs_its_hosted_asset(self):
        missing = self.check("7.1")
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("restore it by hand", missing.stderr)
        self.release("qview-latest", **{"qView-7.0.dmg": "old"})
        self.assertIn("lacks qView-7.1.dmg", self.check("7.1").stderr)
        self.release("qview-latest", **{"qView-7.1.dmg": "current"})
        current = self.check("7.1")
        self.assertEqual(current.returncode, 0, current.stderr)
        self.assertIn("needed=false", current.stdout)
        failing = self.check("7.1", FAKE_GH_API_STATUS="502")
        self.assertNotEqual(failing.returncode, 0)
        self.assertIn("Could not read release", failing.stderr)


class PublishReleaseTests(UpdaterTestCase):
    def publish(self, data="new bytes", **env):
        asset = self.tmp / "qView-7.2.dmg"
        asset.write_text(data)
        notes = self.tmp / "notes.md"
        notes.write_text("notes")
        return self.run_script(ROOT / "scripts/publish-release.sh", "qview", asset, notes, env=env)

    def test_creates_or_uploads_without_replacing(self):
        created = self.publish()
        self.assertEqual(created.returncode, 0, created.stderr)
        self.assertTrue(any(c[:2] == ["release", "create"] for c in self.calls()))
        self.release("qview-latest", **{"qView-7.1.dmg": "old"})
        shutil.rmtree(self.state / "releases/qview-latest")
        self.release("qview-latest", **{"qView-7.1.dmg": "old"})
        (self.state / "calls.jsonl").unlink()
        uploaded = self.publish()
        self.assertEqual(uploaded.returncode, 0, uploaded.stderr)
        uploads = [c for c in self.calls() if c[:2] == ["release", "upload"]]
        self.assertEqual(len(uploads), 1)
        self.assertNotIn("--clobber", uploads[0])
        self.assertTrue(any(c[:2] == ["release", "edit"] for c in self.calls()))
        self.assertEqual((self.state / "releases/qview-latest/qView-7.1.dmg").read_text(), "old")

    def test_existing_identical_asset_changes_nothing(self):
        self.release("qview-latest", **{"qView-7.2.dmg": "new bytes"})
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nothing to publish", result.stderr)
        self.assertFalse(any(c[:2] in (["release", "upload"], ["release", "edit"], ["release", "create"])
                             for c in self.calls()))

    def test_different_hosted_bytes_or_api_errors_fail_untouched(self):
        self.release("qview-latest", **{"qView-7.2.dmg": "tampered"})
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("differs from upstream", result.stderr)
        failing = self.publish(FAKE_GH_API_STATUS="500")
        self.assertNotEqual(failing.returncode, 0)
        self.assertFalse(any(c[:2] in (["release", "upload"], ["release", "edit"], ["release", "create"])
                             for c in self.calls()))
        self.assertEqual((self.state / "releases/qview-latest/qView-7.2.dmg").read_text(), "tampered")


class StageTests(UpdaterTestCase):
    def update(self, *args, **env):
        return self.run_script(ROOT / "scripts/update.sh", *args, env=env)

    def qview_upstream(self, version, data):
        url = f"https://github.com/jurplel/qView/releases/download/{version}/qView-{version}.dmg"
        self.routes[QVIEW_LATEST] = [200, {"tag_name": version, "assets": [
            {"name": f"qView-{version}.dmg", "browser_download_url": url}]}]
        self.routes[url] = [200, data]

    def test_check_without_update_claims_nothing(self):
        self.qview_upstream("7.1", "current")
        self.release("qview-latest", **{"qView-7.1.dmg": "current"})
        result = self.update("check", "qview", self.tmp / "claim")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "claim=false")
        self.assertFalse((self.tmp / "claim").exists())

    def test_plan_lists_this_attempts_claims_of_known_casks(self):
        for name in ("claim-qview-1", "claim-flixor-2", "checked-paicord-1"):
            self.artifact(name, {"claim.env": "x"})
        result = self.update("plan", '["qview", "flixor", "paicord"]')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'casks=["qview"]')
        self.assertEqual(self.update("plan", "[]").stdout.strip(), "casks=[]")
        for bad in ('["../x"]', '"qview"', "[1]"):
            with self.subTest(casks=bad):
                self.assertNotEqual(self.update("plan", bad).returncode, 0)

    def test_publish_rederives_each_claim(self):
        self.qview_upstream("7.2", "qview 7.2")
        self.artifact("claim-qview-1", {"claim.env": claim("7.2", sha("qview 7.2"))})
        result = self.update("publish", '["qview"]')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip().splitlines()[-1], 'published=["qview"]')
        self.assertEqual((self.state / "releases/qview-latest/qView-7.2.dmg").read_text(), "qview 7.2")

    def test_publish_rejects_a_claim_upstream_doesnt_back(self):
        self.qview_upstream("7.2", "qview 7.2")
        for name, body in (("wrong checksum", claim("7.2", "b" * 64)), ("wrong version", claim("7.3", sha("qview 7.2")))):
            with self.subTest(name):
                shutil.rmtree(self.state / "artifacts")
                self.artifact("claim-qview-1", {"claim.env": body})
                result = self.update("publish", '["qview"]')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('published=[]', result.stdout)
                self.assertFalse((self.state / "releases/qview-latest").exists())
        rerun = self.update("publish", '["qview"]', GITHUB_RUN_ATTEMPT="2")
        self.assertNotEqual(rerun.returncode, 0)
        self.assertIn("start a new run", rerun.stderr)


    def test_a_stalled_cask_times_out_and_the_rest_publish(self):
        self.routes["https://api.github.com/repos/Flixorui/flixor/releases/latest"] = [200, "stall"]
        self.artifact("claim-flixor-1", {"claim.env": claim("beta2.5.0", "c" * 64)})
        self.qview_upstream("7.2", "qview 7.2")
        self.artifact("claim-qview-1", {"claim.env": claim("7.2", sha("qview 7.2"))})
        result = self.update("publish", '["flixor", "qview"]', PUBLISH_DEADLINE="3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("flixor: not published", result.stderr)
        self.assertEqual(result.stdout.strip().splitlines()[-1], 'published=["qview"]')


class PushStageTests(UpdaterTestCase):
    def setUp(self):
        super().setUp()
        self.origin = self.tmp / "origin.git"
        seed = self.tmp / "seed"
        for cask in ("media/qview.rb", "media/flixor.rb"):
            (seed / "Casks" / cask).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / "Casks" / cask, seed / "Casks" / cask)
        git = ["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "init.defaultBranch=main"]
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(self.origin)], check=True)
        subprocess.run([*git, "init", "-q", "-b", "main", str(seed)], check=True)
        subprocess.run([*git, "-C", str(seed), "add", "."], check=True)
        subprocess.run([*git, "-C", str(seed), "commit", "-q", "-m", "seed"], check=True)
        subprocess.run(["git", "-C", str(seed), "push", "-q", str(self.origin), "main"], check=True)
        shutil.copytree(seed / "Casks", self.state / "contents/Casks")
        self.env.update(UPDATER_REMOTE=str(self.origin), VERIFIED_SHA="seed")

    def origin_file(self, path):
        return subprocess.run(["git", "--git-dir", str(self.origin), "show", f"main:{path}"],
                              capture_output=True, text=True, check=True).stdout

    def commits(self):
        return subprocess.run(["git", "--git-dir", str(self.origin), "log", "--format=%s%n%b", "main"],
                              capture_output=True, text=True, check=True).stdout

    def checked(self, token, prefix, version, data):
        self.release(f"{token}-latest", **{f"{prefix}-{version}.dmg": data})
        self.artifact(f"checked-{token}-1", {"claim.env": claim(version, sha(data))})

    def test_pushes_only_version_and_sha256(self):
        before = self.origin_file("Casks/media/qview.rb")
        self.checked("qview", "qView", "7.2", "qview 7.2")
        result = self.run_script(ROOT / "scripts/update.sh", "push", '["qview"]')
        self.assertEqual(result.returncode, 0, result.stderr)
        after = self.origin_file("Casks/media/qview.rb")
        expected = before.replace('version "7.1"', 'version "7.2"')
        expected = expected.replace(expected.split('sha256 "')[1].split('"')[0], sha("qview 7.2"))
        self.assertEqual(after, expected)
        self.assertIn("chore(qview): update to 7.2", self.commits())
        self.assertIn("Signed-off-by: github-actions[bot]", self.commits())
        again = self.run_script(ROOT / "scripts/update.sh", "push", '["qview"]')
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIn("main already has 7.2", again.stderr)
        self.assertEqual(self.commits().count("chore(qview)"), 1)

    def test_one_failing_cask_does_not_stop_the_others(self):
        self.checked("flixor", "Flixor", "beta2.5.0", "flixor")
        result = self.run_script(ROOT / "scripts/update.sh", "push", '["qview", "flixor"]')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("qview: not pushed", result.stderr)
        self.assertIn('version "beta2.5.0"', self.origin_file("Casks/media/flixor.rb"))

    def test_refuses_unbacked_or_older_claims(self):
        self.release("qview-latest", **{"qView-7.2.dmg": "hosted"})
        self.artifact("checked-qview-1", {"claim.env": claim("7.2", sha("other"))})
        mismatch = self.run_script(ROOT / "scripts/update.sh", "push", '["qview"]')
        self.assertNotEqual(mismatch.returncode, 0)
        self.assertIn("doesn't serve qView-7.2.dmg with the claimed sha256", mismatch.stderr)
        shutil.rmtree(self.state / "artifacts")
        self.checked("qview", "qView", "7.0", "qview 7.0")
        older = self.run_script(ROOT / "scripts/update.sh", "push", '["qview"]')
        self.assertNotEqual(older.returncode, 0)
        self.assertIn("is not newer", older.stderr)
        self.assertNotIn("chore(", self.commits())
        rerun = self.run_script(ROOT / "scripts/update.sh", "push", '["qview"]', env={"GITHUB_RUN_ATTEMPT": "3"})
        self.assertIn("start a new run", rerun.stderr)

    def test_refuses_a_recipe_changed_since_verification(self):
        verified = self.state / "contents/Casks/media/qview.rb"
        verified.write_text(verified.read_text().replace("qview-latest", "qview-old"))
        self.checked("qview", "qView", "7.2", "qview 7.2")
        result = self.run_script(ROOT / "scripts/update.sh", "push", '["qview"]')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed on main since it was verified", result.stderr)
        self.assertNotIn("chore(", self.commits())

    def test_a_rejected_push_fails_without_retrying(self):
        hook = self.origin / "hooks/pre-receive"
        hook.write_text(f'#!/bin/sh\necho x >> "{self.tmp}/hook-calls"\necho "ruleset says no" >&2\nexit 1\n')
        hook.chmod(0o755)
        self.checked("qview", "qView", "7.2", "qview 7.2")
        result = self.run_script(ROOT / "scripts/update.sh", "push", '["qview"]')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("the push failed", result.stderr)
        self.assertEqual((self.tmp / "hook-calls").read_text().count("x"), 1)


if __name__ == "__main__":
    unittest.main()
