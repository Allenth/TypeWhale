#!/usr/bin/env python3
import importlib.util
from pathlib import Path

worker_path = Path(__file__).parents[1] / "Resources" / "funasr_asr_worker.py"
spec = importlib.util.spec_from_file_location("funasr_asr_worker_matrix", worker_path)
worker = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(worker)

assert worker.SUPPORTED_PROVIDERS == {"fun-asr-nano-2512"}
assert worker.PROVIDER_SPECS["fun-asr-nano-2512"]["hotword_strategy"] == "native_list"

class FakeModel:
    def __init__(self):
        self.calls = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        return [{"text": "Fun-ASR Nano 识别结果"}]

model = FakeModel()
state = worker.WorkerState(model_loader=lambda provider, _: model)
assert state.handle({
    "id": "warm", "command": "warmup", "provider": "fun-asr-nano-2512", "model_dir": "/tmp/model"
})["ok"]
result = state.handle({
    "id": "run", "command": "transcribe", "provider": "fun-asr-nano-2512",
    "audio_path": "/tmp/audio.wav", "hotwords": ["魔搭", "Qwen3-ASR"],
    "hotword_strategy": "native_list",
})
assert result["ok"] and result["hotword_count"] == 2
assert model.calls[-1]["hotwords"] == ["魔搭", "Qwen3-ASR"]
print("FunASRFourProviderMatrixCheck passed")
