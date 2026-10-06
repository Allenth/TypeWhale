#!/usr/bin/env python3
import importlib.util
import contextlib
import os
import sys
import tempfile
import types
from pathlib import Path

worker_path = Path(__file__).parents[1] / "Resources" / "mlx_asr_worker.py"
spec = importlib.util.spec_from_file_location("mlx_asr_worker_check", worker_path)
worker = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(worker)

assert worker.SUPPORTED_PROVIDERS == {
    "qwen3-asr-0.6b-mlx", "qwen3-asr-1.7b-mlx"
}
assert os.environ["HF_HUB_OFFLINE"] == "1"
assert os.environ["TRANSFORMERS_OFFLINE"] == "1"

with tempfile.TemporaryDirectory() as model_dir:
    state = worker.WorkerState()
    class FakeQwenModel: pass
    worker._qwen_load_model = lambda path: FakeQwenModel()
    qwen_calls = []
    worker._qwen_generate = lambda **kwargs: qwen_calls.append(kwargs) or "Qwen 结果"
    warm = state.handle({"id": "q", "command": "warmup", "provider": "qwen3-asr-0.6b-mlx", "model_dir": model_dir})
    assert warm["ok"]
    rejected = state.handle({
        "id": "bad", "command": "transcribe", "provider": "qwen3-asr-0.6b-mlx",
        "audio_path": "/tmp/a.wav", "context_prompt": "unsupported"
    })
    assert not rejected["ok"] and "context" in rejected["error"].lower()
    result = state.handle({
        "id": "good", "command": "transcribe", "provider": "qwen3-asr-0.6b-mlx",
        "audio_path": "/tmp/a.wav"
    })
    assert result["text"] == "Qwen 结果"
    assert qwen_calls[-1]["audio"] == "/tmp/a.wav"
    assert qwen_calls[-1]["language"] == "Chinese"
    assert qwen_calls[-1]["output_path"].endswith("/transcript-0000")

    @contextlib.contextmanager
    def fake_chunks(_audio_path):
        yield ["/tmp/chunk-1.wav", "/tmp/chunk-2.wav", "/tmp/chunk-3.wav"]

    worker._qwen_audio_chunks = fake_chunks
    chunk_text = {
        "/tmp/chunk-1.wav": "第一段结尾重叠",
        "/tmp/chunk-2.wav": "结尾重叠第二段",
        "/tmp/chunk-3.wav": "第二段第三段",
    }
    worker._qwen_generate = lambda **kwargs: chunk_text[kwargs["audio"]]
    result = state.handle({
        "id": "long", "command": "transcribe", "provider": "qwen3-asr-0.6b-mlx",
        "audio_path": "/tmp/long.wav"
    })
    assert result["ok"]
    assert result["text"] == "第一段结尾重叠第二段第三段"
    assert result["chunk_count"] == 3

bad = worker.WorkerState().handle({
    "id": "remote", "command": "warmup", "provider": "qwen3-asr-0.6b-mlx",
    "model_dir": "mlx-community/qwen"
})
assert not bad["ok"] and "local" in bad["error"].lower()
legacy = worker.WorkerState().handle({
    "id": "legacy", "command": "warmup", "provider": "whisper-tiny-mlx",
    "model_dir": "/tmp"
})
assert not legacy["ok"] and "unsupported provider" in legacy["error"].lower()
health = worker.WorkerState().handle({"id": "h", "command": "health"})
assert health == {"id": "h", "ok": True, "ready": True}
shutdown = worker.WorkerState().handle({"id": "s", "command": "shutdown"})
assert shutdown["ok"] and shutdown["shutdown"]
print("MLXASRWorkerProtocolCheck passed")
