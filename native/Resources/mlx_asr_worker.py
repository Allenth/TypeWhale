#!/usr/bin/env python3
"""Persistent, local-only MLX ASR JSONL worker."""
import contextlib
import json
import os
import sys
import tempfile
import time
import traceback
import wave
from contextlib import contextmanager
from pathlib import Path
from typing import Any

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_DATASETS_OFFLINE"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"

SUPPORTED_PROVIDERS = {
    "qwen3-asr-0.6b-mlx", "qwen3-asr-1.7b-mlx"
}

def _qwen_load_model(model_dir: str) -> Any:
    from mlx_audio.stt.utils import load_model
    return load_model(model_dir)


def _qwen_generate(**kwargs: Any) -> Any:
    from mlx_audio.stt.generate import generate_transcription
    return generate_transcription(**kwargs)


def _local_directory(value: str) -> str:
    path = Path(value).expanduser()
    if not path.is_absolute() or not path.is_dir():
        raise ValueError("model_dir must be an existing local directory")
    return str(path.resolve())


def _text(value: Any) -> str:
    if isinstance(value, dict):
        value = value.get("text", "")
    elif hasattr(value, "text"):
        value = value.text
    return str(value or "").strip()


def _merge_text(previous: str, current: str) -> str:
    previous, current = previous.strip(), current.strip()
    if not previous:
        return current
    if not current:
        return previous
    maximum = min(120, len(previous), len(current))
    for length in range(maximum, 1, -1):
        if previous[-length:] == current[:length]:
            return previous + current[length:]
    separator = " " if previous[-1].isascii() and previous[-1].isalnum() and current[0].isascii() and current[0].isalnum() else ""
    return previous + separator + current


@contextmanager
def _qwen_audio_chunks(audio_path: str):
    """Yield overlapping PCM WAV chunks so Qwen cannot silently truncate long recordings."""
    try:
        with wave.open(audio_path, "rb") as source:
            frame_rate = source.getframerate()
            frame_count = source.getnframes()
            if frame_rate <= 0 or source.getcomptype() != "NONE" or frame_count <= frame_rate * 25:
                yield [audio_path]
                return
            parameters = source.getparams()
            chunk_frames = frame_rate * 25
            overlap_frames = frame_rate
            step_frames = chunk_frames - overlap_frames
            with tempfile.TemporaryDirectory(prefix="typewhale-qwen-chunks-") as directory:
                chunks = []
                start = 0
                while start < frame_count:
                    source.setpos(start)
                    frames = source.readframes(min(chunk_frames, frame_count - start))
                    chunk_path = str(Path(directory) / f"chunk-{len(chunks):04d}.wav")
                    with wave.open(chunk_path, "wb") as target:
                        target.setparams(parameters)
                        target.writeframes(frames)
                    chunks.append(chunk_path)
                    if start + chunk_frames >= frame_count:
                        break
                    start += step_frames
                yield chunks
    except (OSError, EOFError, wave.Error):
        yield [audio_path]


class WorkerState:
    def __init__(self) -> None:
        self.provider: str | None = None
        self.model_dir: str | None = None
        self.model: Any = None

    def handle(self, request: dict[str, Any]) -> dict[str, Any]:
        request_id = str(request.get("id", ""))
        try:
            command = request.get("command")
            if command == "health":
                return {"id": request_id, "ok": True, "ready": True}
            if command == "shutdown":
                return {"id": request_id, "ok": True, "shutdown": True}
            if command == "warmup":
                return self._warmup(request_id, request)
            if command == "transcribe":
                return self._transcribe(request_id, request)
            raise ValueError(f"unsupported command: {command}")
        except Exception as error:
            return {"id": request_id, "ok": False, "error": f"{type(error).__name__}: {error}"}

    def _warmup(self, request_id: str, request: dict[str, Any]) -> dict[str, Any]:
        provider = str(request.get("provider", ""))
        if provider not in SUPPORTED_PROVIDERS:
            raise ValueError(f"unsupported provider: {provider}")
        model_dir = _local_directory(str(request.get("model_dir", "")))
        started = time.monotonic()
        if provider != self.provider or model_dir != self.model_dir:
            with contextlib.redirect_stdout(sys.stderr):
                model = _qwen_load_model(model_dir)
            self.provider, self.model_dir, self.model = provider, model_dir, model
        return {
            "id": request_id, "ok": True, "engine": f"{provider}/mlx",
            "load_sec": time.monotonic() - started,
        }

    def _transcribe(self, request_id: str, request: dict[str, Any]) -> dict[str, Any]:
        provider = str(request.get("provider", ""))
        if provider != self.provider or self.model_dir is None:
            raise ValueError(f"provider is not warmed up: {provider}")
        audio_path = str(request.get("audio_path", ""))
        if not audio_path:
            raise ValueError("audio_path is required")
        context_prompt = str(request.get("context_prompt", "")).strip()
        if context_prompt:
            raise ValueError("context prompt/hotwords are unsupported by this Qwen MLX API")
        started = time.monotonic()
        with contextlib.redirect_stdout(sys.stderr):
            combined = ""
            with _qwen_audio_chunks(audio_path) as chunks:
                for index, chunk_path in enumerate(chunks):
                    with tempfile.TemporaryDirectory(prefix="typewhale-mlx-asr-") as output_dir:
                        value = _qwen_generate(
                            model=self.model, audio=chunk_path,
                            output_path=str(Path(output_dir) / f"transcript-{index:04d}"),
                            format="txt", verbose=False, language="Chinese",
                        )
                    combined = _merge_text(combined, _text(value))
                value = combined
            strategy = "unsupported"
        text = _text(value)
        if not text:
            raise ValueError("provider returned empty text")
        return {
            "id": request_id, "ok": True, "text": text,
            "engine": f"{provider}/mlx", "duration_sec": time.monotonic() - started,
            "hotword_strategy": strategy,
            "chunk_count": len(chunks),
        }


def main() -> int:
    state = WorkerState()
    for line in sys.stdin:
        try:
            request = json.loads(line)
            response = state.handle(request)
        except Exception as error:
            response = {"id": "", "ok": False, "error": f"{type(error).__name__}: {error}"}
            traceback.print_exc(file=sys.stderr)
        print(json.dumps(response, ensure_ascii=False), flush=True)
        if response.get("shutdown"):
            return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
