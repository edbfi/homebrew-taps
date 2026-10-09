"""A fake `gh` for the updater tests: releases and run artifacts live under $FAKE_GH.

Layout: releases/<tag>/<asset> (a missing tag directory is HTTP 404),
artifacts/<name>/<files>. Every call is appended to calls.jsonl. FAKE_GH_API_STATUS
makes the release API fail with that HTTP status.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

state = Path(os.environ["FAKE_GH"])
args = sys.argv[1:]
with (state / "calls.jsonl").open("a") as calls:
    calls.write(json.dumps(args) + "\n")


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def option(name):
    return args[args.index(name) + 1]


releases = state / "releases"
if args[:1] == ["api"] and "/releases/tags/" in args[1]:
    tag = args[1].rsplit("/", 1)[1]
    status = os.environ.get("FAKE_GH_API_STATUS")
    if status:
        fail(f"gh: Server Error (HTTP {status})")
    if not (releases / tag).is_dir():
        fail("gh: Not Found (HTTP 404)")
    assets = [{"name": f.name, "state": "uploaded",
               "digest": "sha256:" + hashlib.sha256(f.read_bytes()).hexdigest()}
              for f in sorted((releases / tag).iterdir())]
    print(json.dumps({"tag_name": tag, "assets": assets}))
elif args[:1] == ["api"] and "/artifacts" in args[-3 if "--jq" in args else -1]:
    for artifact in sorted((state / "artifacts").iterdir()) if (state / "artifacts").is_dir() else []:
        print(artifact.name)
elif args[:2] == ["release", "download"]:
    source = releases / args[2] / option("--pattern")
    if not source.is_file():
        fail("no assets match the file pattern")
    target = Path(option("--dir"))
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy(source, target / source.name)
elif args[:2] in (["release", "upload"], ["release", "create"]):
    (releases / args[2]).mkdir(parents=True, exist_ok=True)
    asset = Path(args[3])
    if (releases / args[2] / asset.name).exists() and "--clobber" not in args:
        fail(f"asset {asset.name} already exists")
    shutil.copy(asset, releases / args[2] / asset.name)
elif args[:2] == ["release", "edit"]:
    pass
elif args[:2] == ["run", "download"]:
    source = state / "artifacts" / option("-n")
    if not source.is_dir():
        fail("no valid artifacts found to download")
    shutil.copytree(source, option("-D"), dirs_exist_ok=True, symlinks=True)
else:
    fail(f"fake gh: unhandled {args}")
