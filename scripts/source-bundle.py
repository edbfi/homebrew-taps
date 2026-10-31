#!/usr/bin/env python3
"""Archive exact formula sources, vendored Rust/npm dependencies, and tap recipes."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request


def bundle(token, destination):
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", token):
        raise ValueError("Invalid token")
    recipe = Path(f"Formula/{token}.rb")
    text = recipe.read_text()
    fields = {key: re.search(r'^  ' + key + r' "([^"]+)"$', text, re.M)[1]
              for key in ("url", "version", "sha256")}
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="tap-sources-") as scratch:
        work = Path(scratch)
        archive = work / "upstream.tar.gz"
        urllib.request.urlretrieve(fields["url"], archive)
        with archive.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != fields["sha256"]:
                raise ValueError("Upstream source checksum mismatch")
        unpack = work / "unpack"
        with tarfile.open(archive) as tar:
            tar.extractall(unpack, filter="data")
        roots = list(unpack.iterdir())
        if len(roots) != 1 or not roots[0].is_dir():
            raise ValueError("Expected a single source root")
        source = roots[0]
        env = os.environ.copy()
        cache = subprocess.check_output(["brew", "--cache"], text=True).strip()
        env["CARGO_HOME"] = f"{cache}/cargo_cache"
        manifest = source / ("src-tauri/Cargo.toml" if token == "fredtv" else "Cargo.toml")
        if manifest.exists():
            config = subprocess.check_output(
                ["cargo", "vendor", "--locked", "--versioned-dirs", "--manifest-path", str(manifest), "vendor"],
                cwd=source, env=env, text=True,
            )
            (source / ".cargo").mkdir(exist_ok=True)
            with (source / ".cargo/config.toml").open("a") as stream:
                stream.write("\n" + config)
            subprocess.run(["cargo", "metadata", "--locked", "--offline", "--format-version", "1",
                            "--manifest-path", str(manifest)], cwd=source, env=env,
                           check=True, stdout=subprocess.DEVNULL)
        if token == "fredtv":
            node = subprocess.check_output(["brew", "--prefix", "node@24"], text=True).strip()
            env["PATH"] = f"{node}/bin:{env['PATH']}"
            subprocess.run(["npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund"],
                           cwd=source, env=env, check=True)
        recipes = source / "homebrew-packaging"
        recipes.mkdir()
        for directory in ("Formula", "scripts", "pipelines", "docs"):
            if Path(directory).exists():
                shutil.copytree(directory, recipes / directory, ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copy2("LICENSE", recipes / "LICENSE")
        (recipes / "provenance.json").write_text(json.dumps(fields, indent=2) + "\n")
        target = destination / f"{token}-{fields['version']}-source.tar.gz"
        with tarfile.open(target, "w:gz") as tar:
            tar.add(source, arcname=f"{token}-{fields['version']}")
        print(target)


if __name__ == "__main__":
    bundle(sys.argv[1], Path(sys.argv[2]).resolve())
