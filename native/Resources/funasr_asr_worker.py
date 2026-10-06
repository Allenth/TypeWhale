#!/usr/bin/env python3
"""Persistent local FunASR worker using newline-delimited JSON over stdio."""

from __future__ import annotations

import contextlib
import json
import sys
import time
from pathlib import Path
from typing import Any, Callable


PROVIDER_SPECS = {
    "fun-asr-nano-2512": {
        "hotword_strategy": "native_list",
        "trust_remote_code": True,
    },
}
SUPPORTED_PROVIDERS = set(PROVIDER_SPECS)


def load_model(provider: str, model_dir: str) -> Any:
    if provider not in SUPPORTED_PROVIDERS:
        raise ValueError(f"unsupported provider: {provider}")
    path = Path(model_dir)
    if not path.is_dir():
        raise FileNotFoundError(f"model directory missing: {path}")
    with contextlib.redirect_stdout(sys.stderr):
        from funasr import AutoModel

        arguments: dict[str, Any] = {
            "model": str(path),
            "device": "cpu",
            "disable_update": True,
        }
        if PROVIDER_SPECS[provider]["trust_remote_code"]:
            arguments["trust_remote_code"] = True
        return AutoModel(**arguments)


class WorkerState:
    def __init__(self, model_loader: Callable[[str, str], Any] = load_model):
        self.model_loader = model_loader
        self.model: Any | None = None
        self.provider: str | None = None
        self.model_dir: str | None = None

    def handle(self, request: dict[str, Any]) -> dict[str, Any]:
        request_id = str(request.get("id", ""))
        command = str(request.get("command", ""))
        try:
            if not request_id:
                raise ValueError("request id is required")
            if command == "health":
                return {"id": request_id, "ok": True, "ready": self.model is not None}
            if command == "warmup":
                return self._warmup(request_id, request)
            if command == "transcribe":
                return self._transcribe(request_id, request)
            if command == "shutdown":
                return {"id": request_id, "ok": True, "shutdown": True}
            raise ValueError(f"unknown command: {command}")
        except Exception as exc:
            return {"id": request_id, "ok": False, "error": f"{type(exc).__name__}: {exc}"}

    def _warmup(self, request_id: str, request: dict[str, Any]) -> dict[str, Any]:
        provider = str(request.get("provider", ""))
        model_dir = str(request.get("model_dir", ""))
        if provider not in SUPPORTED_PROVIDERS:
            raise ValueError(f"unsupported provider: {provider}")
        needs_reload = (
            self.model is None
            or provider != self.provider
            or model_dir != self.model_dir
        )
        started = time.monotonic()
        if needs_reload:
            model = self.model_loader(provider, model_dir)
            self.model = model
            self.provider = provider
            self.model_dir = model_dir
        return {
            "id": request_id,
            "ok": True,
            "engine": f"{provider}/funasr-python",
            "load_sec": time.monotonic() - started,
        }

    def _transcribe(self, request_id: str, request: dict[str, Any]) -> dict[str, Any]:
        provider = str(request.get("provider", ""))
        if self.model is None or provider != self.provider:
            raise RuntimeError(f"provider not warmed: {provider}")
        audio_path = str(request.get("audio_path", ""))
        if not audio_path:
            raise ValueError("audio_path is required")
        hotwords = [str(value) for value in request.get("hotwords", []) if str(value).strip()]
        spec = PROVIDER_SPECS[provider]
        hotword_strategy = str(request.get("hotword_strategy", ""))
        expected_strategy = str(spec["hotword_strategy"])
        if hotword_strategy != expected_strategy:
            raise ValueError(
                f"hotword strategy mismatch: provider={provider} "
                f"expected={expected_strategy} actual={hotword_strategy or 'missing'}"
            )
        arguments: dict[str, Any] = {"input": [audio_path], "cache": {}, "batch_size": 1}
        arguments.update({"hotwords": hotwords, "language": "中文", "itn": True})
        started = time.monotonic()
        with contextlib.redirect_stdout(sys.stderr):
            result = self.model.generate(**arguments)
        if not isinstance(result, list) or not result or not isinstance(result[0], dict):
            raise ValueError("provider returned an invalid result")
        text = str(result[0].get("text", "")).strip()
        if not text:
            raise ValueError("provider returned empty text")
        return {
            "id": request_id,
            "ok": True,
            "text": text,
            "engine": f"{provider}/funasr-python",
            "duration_sec": time.monotonic() - started,
            "hotword_strategy": hotword_strategy,
            "hotword_count": len(hotwords),
        }


def main() -> int:
    state = WorkerState()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError("request must be an object")
            response = state.handle(request)
        except Exception as exc:
            response = {"id": "", "ok": False, "error": f"{type(exc).__name__}: {exc}"}
        sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        if response.get("shutdown") is True:
            return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
