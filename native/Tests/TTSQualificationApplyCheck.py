import importlib.util
import json
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "tts_qualification_apply", root / "tools/tts_qualification_apply.py"
)
module = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    models = base / "models"
    run = base / "20260728-010351"
    run.mkdir()
    reports = []
    for index in range(8):
        model_id = (
            "kokoro-int8-multi-lang-v1_1" if index == 0 else f"model-{index}"
        )
        directory = models / model_id
        directory.mkdir(parents=True)
        (directory / "typewhale-model.json").write_text(
            json.dumps({
                "id": model_id,
                "qualification": {"status": "unverified"},
            }),
            encoding="utf-8",
        )
        results = [{"phase": "ready", "response": {"ok": True}}]
        results += [
            {"sampleID": sample, "response": {"ok": True, "phase": "completed"}}
            for sample in module.REQUIRED_SAMPLES
        ]
        reports.append({"modelID": model_id, "results": results})
    (run / "metrics.json").write_text(json.dumps(reports), encoding="utf-8")

    updated = module.apply_qualification(run, models)
    assert updated == 8
    kokoro = json.loads(
        (models / "kokoro-int8-multi-lang-v1_1/typewhale-model.json").read_text()
    )
    assert kokoro["qualification"]["status"] == "passed"
    assert kokoro["qualification"]["evidence"] == run.name
    assert kokoro["defaultSpeakerID"] == 50

    reports[0]["results"][-1]["response"]["ok"] = False
    (run / "metrics.json").write_text(json.dumps(reports), encoding="utf-8")
    try:
        module.apply_qualification(run, models)
        raise AssertionError("failed sample must reject promotion")
    except module.QualificationRejected:
        pass

print("TTSQualificationApplyCheck passed")
