#!/usr/bin/env python3
import json, os, struct, subprocess, sys, tempfile, wave
from pathlib import Path

root = Path(__file__).resolve().parents[2]
worker = root / "native/Resources/openclaw_tts_worker.py"
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    fake = tmp / "fake"
    fake.mkdir(parents=True)
    (fake / "sherpa_onnx.py").write_text('''
import math
import json
import os
class OfflineTtsVitsModelConfig:
    def __init__(self, **kwargs): self.kwargs = kwargs
class OfflineTtsModelConfig:
    def __init__(self, **kwargs): self.kwargs = kwargs
class OfflineTtsConfig:
    def __init__(self, **kwargs): self.kwargs = kwargs
class Audio:
    sample_rate = 44100
    samples = [0.0, 0.35, -0.35, 0.7, -0.7, 0.0]
class OfflineTts:
    def __init__(self, config):
        self.config = config
        capture = os.environ.get("TYPEWHALE_SHERPA_CAPTURE")
        if capture:
            lexicon = config.kwargs["model"].kwargs["vits"].kwargs["lexicon"]
            with open(capture, "w") as file:
                json.dump({"lexicon": lexicon}, file)
    def generate(self, text, sid=0, speed=1.0): return Audio()
''')
    (fake / "soundfile.py").write_text('''
import struct, wave
def write(output, samples, sample_rate):
    with wave.open(output, "wb") as wav:
        wav.setparams((1, 2, sample_rate, 0, "NONE", "not compressed"))
        wav.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, int(s * 32767)))) for s in samples))
''')
    pack = tmp / "pack"
    (pack / "dict").mkdir(parents=True)
    for name in ["model.onnx", "lexicon.txt", "tokens.txt", "number.fst", "phone.fst", "date.fst"]:
        (pack / name).write_bytes(b"x")
    capture = tmp / "capture.json"
    env = os.environ.copy(); env["PYTHONPATH"] = str(fake); env["TYPEWHALE_SHERPA_CAPTURE"] = str(capture)
    process = subprocess.Popen(
        [sys.executable, str(worker), "--server", "--engine", "sherpa_melo_44k", "--pack-dir", str(pack)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    ready = json.loads(process.stdout.readline()); assert ready["ok"] and ready["type"] == "ready"
    output = tmp / "voice.wav"
    for payload in [
        {"id":"w", "type":"warmup"},
        {"id":"s", "type":"synthesize", "text":"第一句", "output":str(output)},
        {"id":"x", "type":"shutdown"},
    ]:
        process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n"); process.stdin.flush()
        response = json.loads(process.stdout.readline()); assert response["ok"] and response["id"] == payload["id"]
    assert process.wait(timeout=5) == 0
    captured = json.loads(capture.read_text())
    lexicon = Path(captured["lexicon"])
    assert lexicon.name == "lexicon.typewhale.txt"
    merged = lexicon.read_text()
    assert "github g ih t hh ah b" in merged
    assert "minimax m ih n iy m ae k s" in merged
    assert "openai ow p ah n ey ay" in merged
    required_stack_terms = [
        "microservices m ay k r ow s er v ih s ih z",
        "async ey s ih ng k",
        "backend b ae k eh n d",
        "ci s iy ay",
        "cicd s iy ay s iy d iy",
        "fastapi f ae s t ey p iy ay",
        "frontend f r ah n t eh n d",
        "terraform t eh r ah f ao r m",
        "aws ey d ah b ah l y uw eh s",
        "nginx eh n jh ih n eh k s",
        "prometheus p r ah m iy th iy ah s",
        "grafana g r ah f aa n ah",
        "jwt jh ey d ah b ah l y uw t iy",
        "oauth ow ao th",
        "aes ey iy eh s",
        "lifecycle l ay f s ay k ah l",
        "realtime r iy l t ay m",
        "s3 eh s th r iy",
        "websocket w eh b s aa k ih t",
        "autoscaling ao t ow s k ey l ih ng",
    ]
    for term in required_stack_terms:
        assert term in merged, f"missing TypeWhale Sherpa lexicon entry: {term}"
    with wave.open(str(output), "rb") as wav:
        assert wav.getframerate() == 44100
        frames = wav.readframes(wav.getnframes())
    assert max(abs(value) for value in struct.unpack("<6h", frames)) >= 22000
print("OpenClawSherpaTTSWorkerCheck passed")
