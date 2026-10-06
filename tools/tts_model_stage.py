#!/usr/bin/env python3
"""Stage TypeWhale TTS models under explicit disk and concurrency limits."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
import subprocess
import threading
import urllib.request
from pathlib import Path
from typing import Any


def directory_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    total = 0
    for item in path.rglob("*"):
        try:
            if item.is_file():
                total += item.stat().st_size
        except FileNotFoundError:
            continue
    return total


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expand(path: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(path))).resolve(strict=False)


class Stager:
    def __init__(self, root: Path, budget: int, reserve: int, dry_run: bool):
        self.root = root.resolve(strict=False)
        self.staging = self.root / ".staging"
        self.budget = budget
        self.reserve = reserve
        self.dry_run = dry_run
        self.lock = threading.Lock()
        self.active = 0
        self.peak_active = 0
        self.reserved_bytes = 0

    def capacity_error(self, incoming: int = 0) -> str | None:
        managed = directory_bytes(self.root)
        projected = managed + self.reserved_bytes + incoming
        if projected > self.budget:
            return f"50 GB model budget exceeded: {projected} > {self.budget}"
        probe = self.root if self.root.exists() else self.root.parent
        while not probe.exists():
            probe = probe.parent
        free = shutil.disk_usage(probe).free
        if free - incoming < self.reserve:
            return f"disk reserve would fall below {self.reserve} bytes"
        return None

    def stage(self, model: dict[str, Any]) -> dict[str, Any]:
        model_id = model["id"]
        reserved = 0
        with self.lock:
            self.active += 1
            self.peak_active = max(self.peak_active, self.active)
        try:
            if self.dry_run:
                return {
                    "id": model_id,
                    "state": "dry-run",
                    "source": model.get("acquisition", {}).get("source", ""),
                }
            destination = self.root / model_id
            acquisition = model["acquisition"]
            kind = acquisition["kind"]
            if destination.is_dir():
                existing_missing = [
                    relative
                    for relative in model["requiredPaths"]
                    if not (destination / relative).exists()
                ]
                if not existing_missing:
                    return {
                        "id": model_id,
                        "state": "already-promoted",
                        "bytes": directory_bytes(destination),
                    }
            if kind == "local-copy":
                reserved = directory_bytes(expand(acquisition["source"]))
                reserved += sum(
                    directory_bytes(expand(extra["source"]))
                    for extra in acquisition.get("extras", [])
                )
            with self.lock:
                error = self.capacity_error(reserved)
                if error:
                    reserved = 0
                    return {"id": model_id, "state": "blocked", "error": error}
                self.reserved_bytes += reserved
            if kind == "existing":
                work = destination
                if not work.exists():
                    return {"id": model_id, "state": "failed", "error": "existing model missing"}
            else:
                work = self.staging / model_id
                if work.exists() and kind == "local-copy":
                    shutil.rmtree(work)
                work.mkdir(parents=True, exist_ok=True)
                if kind == "local-copy":
                    source = expand(acquisition["source"])
                    if not source.is_dir():
                        return {"id": model_id, "state": "failed", "error": f"source missing: {source}"}
                    shutil.copytree(source, work, dirs_exist_ok=True)
                    for extra in acquisition.get("extras", []):
                        extra_source = expand(extra["source"])
                        if not extra_source.is_file():
                            return {"id": model_id, "state": "failed", "error": f"extra missing: {extra_source}"}
                        shutil.copy2(extra_source, work / extra["destination"])
                    if license_url := acquisition.get("licenseURL"):
                        with urllib.request.urlopen(license_url, timeout=30) as response:
                            (work / "LICENSE").write_bytes(response.read())
                elif kind == "huggingface":
                    command = shutil.which("hf") or shutil.which("huggingface-cli")
                    if not command:
                        return {"id": model_id, "state": "failed", "error": "hf CLI missing"}
                    arguments = [
                        command,
                        "download",
                        acquisition["repo"],
                        "--local-dir",
                        str(work),
                        "--max-workers",
                        "1",
                    ]
                    completed = subprocess.run(arguments, capture_output=True, text=True)
                    if completed.returncode != 0:
                        return {
                            "id": model_id,
                            "state": "failed",
                            "error": (completed.stderr or completed.stdout).strip(),
                        }
                    for companion in acquisition.get("companions", []):
                        companion_arguments = [
                            command,
                            "download",
                            companion["repo"],
                            "--local-dir",
                            str(work / companion["destination"]),
                            "--max-workers",
                            "1",
                        ]
                        completed = subprocess.run(
                            companion_arguments,
                            capture_output=True,
                            text=True,
                        )
                        if completed.returncode != 0:
                            return {
                                "id": model_id,
                                "state": "failed",
                                "error": (completed.stderr or completed.stdout).strip(),
                            }
                    if license_url := acquisition.get("licenseURL"):
                        with urllib.request.urlopen(license_url, timeout=30) as response:
                            (work / "LICENSE").write_bytes(response.read())
                elif kind == "ttskit-prefetch":
                    command = shutil.which("hf") or shutil.which("huggingface-cli")
                    if not command:
                        return {"id": model_id, "state": "failed", "error": "hf CLI missing"}
                    variant = acquisition["variant"]
                    pattern = f"qwen3_tts/*/12hz-{variant}-customvoice/**"
                    arguments = [
                        command,
                        "download",
                        "argmaxinc/ttskit-coreml",
                        "--include",
                        pattern,
                        "--local-dir",
                        str(work),
                        "--max-workers",
                        "1",
                    ]
                    completed = subprocess.run(arguments, capture_output=True, text=True)
                    if completed.returncode != 0:
                        return {
                            "id": model_id,
                            "state": "failed",
                            "error": (completed.stderr or completed.stdout).strip(),
                        }
                    tokenizer_arguments = [
                        command,
                        "download",
                        "Qwen/Qwen3-0.6B",
                        "tokenizer.json",
                        "tokenizer_config.json",
                        "config.json",
                        "--local-dir",
                        str(work / "tokenizer"),
                    ]
                    completed = subprocess.run(
                        tokenizer_arguments,
                        capture_output=True,
                        text=True,
                    )
                    if completed.returncode != 0:
                        return {
                            "id": model_id,
                            "state": "failed",
                            "error": (completed.stderr or completed.stdout).strip(),
                        }
                    license_url = "https://raw.githubusercontent.com/QwenLM/Qwen3-TTS/main/LICENSE"
                    with urllib.request.urlopen(license_url, timeout=30) as response:
                        (work / "LICENSE").write_bytes(response.read())
                    (work / "typewhale-prefetch.json").write_text(
                        json.dumps(
                            {
                                "repository": "argmaxinc/ttskit-coreml",
                                "variant": variant,
                                "include": pattern,
                            },
                            indent=2,
                        )
                        + "\n",
                        encoding="utf-8",
                    )
                else:
                    return {"id": model_id, "state": "failed", "error": f"unsupported acquisition: {kind}"}

            missing = [
                relative
                for relative in model["requiredPaths"]
                if not (work / relative).exists()
            ]
            if missing:
                return {"id": model_id, "state": "failed", "error": f"missing required paths: {missing}"}

            files = {
                str(item.relative_to(work)): {
                    "bytes": item.stat().st_size,
                    "sha256": sha256(item),
                }
                for item in work.rglob("*")
                if item.is_file() and item.name != "typewhale-model.json"
            }
            manifest = {
                "id": model_id,
                "displayName": model["displayName"],
                "tier": model["tier"],
                "runtime": model["runtime"],
                "license": model["license"],
                "licensePath": model["licensePath"],
                "upstream": model["upstream"],
                "requiredPaths": model["requiredPaths"],
                "files": files,
                "qualification": {"status": "unverified"},
            }
            if "defaultSpeakerID" in model:
                manifest["defaultSpeakerID"] = model["defaultSpeakerID"]
            (work / "typewhale-model.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            if kind != "existing":
                if destination.exists():
                    shutil.rmtree(destination)
                os.replace(work, destination)
            return {"id": model_id, "state": "promoted", "bytes": directory_bytes(destination)}
        finally:
            with self.lock:
                self.reserved_bytes -= reserved
                self.active -= 1


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--only")
    parser.add_argument("--max-concurrency", type=int, default=3)
    parser.add_argument("--budget-gb", type=float, default=50)
    parser.add_argument("--budget-bytes", type=int)
    parser.add_argument("--reserve-free-gb", type=float, default=15)
    parser.add_argument("--reserve-free-bytes", type=int)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    catalog = json.loads(arguments.catalog.read_text(encoding="utf-8"))
    selected = {item.strip() for item in (arguments.only or "").split(",") if item.strip()}
    models = catalog if arguments.all else [model for model in catalog if model["id"] in selected]
    if not models:
        raise SystemExit("No models selected; pass --all or --only")
    budget = arguments.budget_bytes or int(arguments.budget_gb * 1024**3)
    reserve = arguments.reserve_free_bytes
    if reserve is None:
        reserve = int(arguments.reserve_free_gb * 1024**3)
    stager = Stager(arguments.root, budget, reserve, arguments.dry_run)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, arguments.max_concurrency)) as executor:
        results = list(executor.map(stager.stage, models))
    payload = {"peakActive": stager.peak_active, "models": results}
    if arguments.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        for item in results:
            print(f"{item['id']}: {item['state']} {item.get('error', '')}".rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
