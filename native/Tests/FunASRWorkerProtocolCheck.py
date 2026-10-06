#!/usr/bin/env python3
import importlib.util
from pathlib import Path

worker_path = Path(__file__).parents[1] / "Resources" / "funasr_asr_worker.py"
spec = importlib.util.spec_from_file_location("funasr_asr_worker", worker_path)
worker = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(worker)

class FakeModel:
    def generate(self, **kwargs):
        return [{"text": "把 Qwen3-ASR 接到 SpeechInputCoordinator"}]

loads = []
state = worker.WorkerState(model_loader=lambda provider, model_dir: loads.append((provider, model_dir)) or FakeModel())
assert state.handle({"id": "h", "command": "health"})["ready"] is False
warm = state.handle({
    "id": "w", "command": "warmup", "provider": "fun-asr-nano-2512", "model_dir": "/tmp/model"
})
assert warm["ok"] and loads == [("fun-asr-nano-2512", "/tmp/model")]
result = state.handle({
    "id": "t", "command": "transcribe", "provider": "fun-asr-nano-2512",
    "audio_path": "/tmp/audio.wav", "hotwords": ["Qwen3-ASR"],
    "hotword_strategy": "native_list",
})
assert result["ok"] and result["text"] == "把 Qwen3-ASR 接到 SpeechInputCoordinator"
unsupported = state.handle({
    "id": "x", "command": "warmup", "provider": "retired-provider", "model_dir": "/tmp/model"
})
assert not unsupported["ok"] and "unsupported provider" in unsupported["error"]
assert state.handle({"id": "s", "command": "shutdown"})["shutdown"]
print("FunASRWorkerProtocolCheck passed")
