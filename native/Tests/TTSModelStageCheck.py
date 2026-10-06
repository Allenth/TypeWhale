#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


repo = Path(__file__).resolve().parents[2]
tool = repo / "tools/tts_model_stage.py"

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    source = root / "sources"
    target = root / "models"
    source.mkdir()
    for index in range(5):
        model = source / f"model-{index}"
        model.mkdir()
        (model / "model.bin").write_bytes(bytes([index]) * 1024)
        (model / "LICENSE").write_text("test license")

    catalog = root / "catalog.json"
    catalog.write_text(
        json.dumps(
            [
                {
                    "id": f"model-{index}",
                    "displayName": f"Model {index}",
                    "tier": 1,
                    "runtime": "test",
                    "license": "test-only",
                    "licensePath": "LICENSE",
                    "upstream": "test://model",
                    "acquisition": {
                        "kind": "local-copy",
                        "source": str(source / f"model-{index}"),
                    },
                    "requiredPaths": ["model.bin", "LICENSE"],
                    "defaultSpeakerID": 50 if index == 0 else 0,
                }
                for index in range(5)
            ]
        )
    )

    result = subprocess.run(
        [
            sys.executable,
            str(tool),
            "--catalog",
            str(catalog),
            "--root",
            str(target),
            "--all",
            "--max-concurrency",
            "3",
            "--budget-gb",
            "1",
            "--reserve-free-gb",
            "0",
            "--json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    assert payload["peakActive"] <= 3
    assert all(item["state"] == "promoted" for item in payload["models"])
    assert all((target / f"model-{index}" / "typewhale-model.json").is_file() for index in range(5))
    first_manifest = json.loads(
        (target / "model-0" / "typewhale-model.json").read_text()
    )
    assert first_manifest["defaultSpeakerID"] == 50

    shutil.rmtree(source / "model-0")
    reuse_result = subprocess.run(
        [
            sys.executable,
            str(tool),
            "--catalog",
            str(catalog),
            "--root",
            str(target),
            "--only",
            "model-0",
            "--budget-gb",
            "1",
            "--reserve-free-gb",
            "0",
            "--json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert json.loads(reuse_result.stdout)["models"][0]["state"] == "already-promoted"

    budget_result = subprocess.run(
        [
            sys.executable,
            str(tool),
            "--catalog",
            str(catalog),
            "--root",
            str(root / "budget"),
            "--all",
            "--max-concurrency",
            "3",
            "--budget-bytes",
            "1500",
            "--reserve-free-gb",
            "0",
            "--json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    budget_payload = json.loads(budget_result.stdout)
    assert any(item["state"] == "blocked" for item in budget_payload["models"])

    free_result = subprocess.run(
        [
            sys.executable,
            str(tool),
            "--catalog",
            str(catalog),
            "--root",
            str(root / "free"),
            "--all",
            "--reserve-free-bytes",
            str(10**30),
            "--json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    free_payload = json.loads(free_result.stdout)
    assert all(item["state"] == "blocked" for item in free_payload["models"])

print("TTSModelStageCheck passed")
