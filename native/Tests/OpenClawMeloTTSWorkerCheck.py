#!/usr/bin/env python3
import json, os, struct, subprocess, sys, tempfile, wave
from pathlib import Path

root = Path(__file__).resolve().parents[2]
worker = root / "native/Resources/openclaw_tts_worker.py"
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    fake = tmp / "fake"
    (fake / "melo").mkdir(parents=True)
    (fake / "melo/text").mkdir()
    (fake / "torch").mkdir()
    (fake / "melo/__init__.py").write_text("")
    (fake / "melo/text/__init__.py").write_text("")
    (fake / "melo/text/chinese_bert.py").write_text("models={}\ntokenizers={}\n")
    (fake / "transformers.py").write_text('''
class Loader:
    @classmethod
    def from_pretrained(cls, path, **kwargs): return cls()
    def to(self, device): return self
AutoModelForMaskedLM=Loader
AutoTokenizer=Loader
''')
    (fake / "torch/__init__.py").write_text("class MPS:\n    @staticmethod\n    def is_available(): return True\nclass Backends: mps=MPS()\nbackends=Backends()\n")
    (fake / "melo/api.py").write_text('''
import struct, wave
class H: pass
class D: spk2id={"ZH": 0}
class TTS:
    def __init__(self, **kwargs): self.hps=H(); self.hps.data=D()
    def tts_to_file(self, text, speaker, output, speed=1.0, quiet=True):
        with wave.open(output, "wb") as wav:
            wav.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
            wav.writeframes(struct.pack("<4h", 1000, -1000, 2000, -2000))
''')
    pack = tmp / "pack"
    for path in [pack / "models/melotts-chinese", pack / "models/bert-base-multilingual-uncased", pack / "nltk_data"]:
        path.mkdir(parents=True)
    (pack / "models/melotts-chinese/config.json").write_text("{}")
    (pack / "models/melotts-chinese/checkpoint.pth").write_bytes(b"x")
    (pack / "models/bert-base-multilingual-uncased/config.json").write_text("{}")
    (pack / "models/bert-base-multilingual-uncased/pytorch_model.bin").write_bytes(b"x")
    (pack / "models/bert-base-multilingual-uncased/tokenizer.json").write_bytes(b"x")
    env = os.environ.copy(); env["PYTHONPATH"] = str(fake)
    process = subprocess.Popen([sys.executable, str(worker), "--server", "--pack-dir", str(pack)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    ready = json.loads(process.stdout.readline()); assert ready["ok"] and ready["type"] == "ready"
    output = tmp / "voice.wav"
    for payload in [
        {"id":"w", "type":"warmup"},
        {"id":"s1", "type":"synthesize", "text":"第一句", "output":str(output)},
        {"id":"s2", "type":"synthesize", "text":"第二句", "output":str(output)},
        {"id":"x", "type":"shutdown"},
    ]:
        process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n"); process.stdin.flush()
        response = json.loads(process.stdout.readline()); assert response["ok"] and response["id"] == payload["id"]
    assert process.wait(timeout=5) == 0
    with wave.open(str(output), "rb") as wav:
        frames = wav.readframes(wav.getnframes())
    assert max(abs(value) for value in struct.unpack("<4h", frames)) >= 29000
print("OpenClawMeloTTSWorkerCheck passed")
