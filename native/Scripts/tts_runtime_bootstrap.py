#!/usr/bin/env python3
"""Create or record reproducible TypeWhale experimental TTS runtimes."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


RUNTIMES = {
    "voxcpm2": {
        "directory": "voxcpm2-2.0.3-py312",
        "python": "3.12",
        "packages": ["voxcpm==2.0.3"],
        "source": None,
    },
    "cosyvoice3": {
        "directory": "cosyvoice3-main-py310",
        "python": "3.10",
        "packages": [],
        "source": {
            "url": "https://github.com/FunAudioLLM/CosyVoice.git",
            "commit": "074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc",
        },
    },
}


def run(arguments: list[str]) -> None:
    subprocess.run(arguments, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adapter", choices=RUNTIMES, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--uv", type=Path, default=Path("/opt/homebrew/bin/uv"))
    parser.add_argument("--record-existing", action="store_true")
    parser.add_argument("--offline-after-install", action="store_true")
    arguments = parser.parse_args()

    root = arguments.root.expanduser().resolve()
    config = RUNTIMES[arguments.adapter]
    runtime = (root / config["directory"]).resolve()
    if runtime.parent != root:
        raise SystemExit("runtime escaped managed root")
    python = runtime / "bin/python3"

    if not arguments.record_existing:
        run([str(arguments.uv), "venv", "--python", config["python"], str(runtime)])
        for package in config["packages"]:
            run([
                str(arguments.uv),
                "pip",
                "install",
                "--python",
                str(python),
                package,
            ])
        if config["source"]:
            raise SystemExit(
                "CosyVoice3 requires the checked compatibility recipe; "
                "use --record-existing after provisioning it"
            )
    if not python.is_file():
        raise SystemExit(f"managed Python missing: {python}")

    freeze = subprocess.run(
        [
            str(arguments.uv),
            "pip",
            "freeze",
            "--python",
            str(python),
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    source_revision = None
    source = config["source"]
    if source:
        checkout = runtime / "src/CosyVoice"
        source_revision = subprocess.run(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if source_revision != source["commit"]:
            raise SystemExit(
                f"unexpected CosyVoice revision: {source_revision}"
            )
    manifest = {
        "adapter": arguments.adapter,
        "python": subprocess.run(
            [str(python), "--version"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip(),
        "sourceRevision": source_revision,
        "packagesSHA256": hashlib.sha256(freeze.encode()).hexdigest(),
        "packages": freeze.splitlines(),
        "offlineAfterInstall": arguments.offline_after_install,
    }
    (runtime / "typewhale-runtime.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
