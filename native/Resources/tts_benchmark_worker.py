#!/usr/bin/env python3
"""JSONL worker for isolated local TTS benchmarks and product playback."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
import time
import unicodedata
import wave
from pathlib import Path
from typing import NamedTuple


SAFE_VOICE_ID = re.compile(r"^[A-Za-z0-9._-]+$")


def normalize_zipvoice_text(text: str) -> str:
    """Turn display-oriented Markdown into stable, speakable ZipVoice text."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    normalized = re.sub(
        r"(?m)^\s{0,3}([-*_])(?:\s*\1){2,}\s*$",
        "",
        normalized,
    )
    normalized = re.sub(r"\[([^\]]+)\]\((?:https?://[^)]+)\)", r"\1", normalized)
    normalized = re.sub(r"(?m)^\s{0,3}#{1,6}\s*", "", normalized)
    normalized = re.sub(r"\*\*([^*]+)\*\*", r"\1", normalized)
    normalized = re.sub(r"`([^`]+)`", r"\1", normalized)
    normalized = re.sub(r"[—–]+", "，", normalized)
    normalized = normalized.translate(str.maketrans("", "", "\"“”'‘’`"))
    normalized = "".join(
        character
        for character in normalized
        if unicodedata.category(character) != "So"
        and ord(character) not in range(0xFE00, 0xFE10)
    )
    lines = (
        line.strip()
        for line in normalized.splitlines()
    )
    return "".join(line for line in lines if line)


class ZipVoiceReference(NamedTuple):
    voice_id: str
    text: str
    samples: list[float]
    sample_rate: int


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_zipvoice_reference(
    pack: Path,
    voice_id: str,
    reference_directory_name: str | None = None,
) -> ZipVoiceReference:
    if not isinstance(voice_id, str) or not SAFE_VOICE_ID.fullmatch(voice_id):
        raise ValueError("unknown voiceID for ZipVoice")
    reference_root = (pack / "references").resolve()
    directory_name = reference_directory_name or voice_id
    if (
        not isinstance(directory_name, str)
        or "/" in directory_name
        or "\\" in directory_name
        or not directory_name.startswith(
            (voice_id, f".{voice_id}-staging-")
        )
    ):
        raise ValueError("invalid ZipVoice reference directory")
    directory = (reference_root / directory_name).resolve()
    try:
        directory.relative_to(reference_root)
    except ValueError as error:
        raise ValueError("ZipVoice reference escaped model directory") from error
    manifest_path = directory / "reference.json"
    audio_path = directory / "reference.wav"
    text_path = directory / "reference.txt"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("missing ZipVoice reference manifest") from error
    if (
        manifest.get("schemaVersion") != 1
        or manifest.get("voiceID") != voice_id
        or manifest.get("sampleRate") != 24000
        or manifest.get("channels") != 1
    ):
        raise ValueError("invalid ZipVoice reference manifest")
    try:
        if _sha256(audio_path) != manifest.get("audioSHA256"):
            raise ValueError("ZipVoice reference audio hash mismatch")
        if _sha256(text_path) != manifest.get("textSHA256"):
            raise ValueError("ZipVoice reference text hash mismatch")
        text = text_path.read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ValueError("missing ZipVoice reference files") from error
    if not text:
        raise ValueError("ZipVoice reference text is empty")
    samples, sample_rate = load_wave(audio_path)
    if sample_rate != 24000:
        raise ValueError("ZipVoice reference must use 24 kHz audio")
    duration = len(samples) / sample_rate
    legacy_long_reference_ids = {
        "zipvoice-default",
        "zipvoice-video-reference",
    }
    if voice_id not in legacy_long_reference_ids and not 1 <= duration <= 3:
        raise ValueError(
            f"ZipVoice cloned reference must be 1-3 seconds, got {duration:.2f}"
        )
    return ZipVoiceReference(voice_id, text, samples, sample_rate)


class FakeEngine:
    def __init__(self, delay: float):
        self.delay = delay
        self.sample_rate = 24000
        self.channels = 1

    def prepare(self) -> None:
        if self.delay:
            time.sleep(self.delay)

    def generate(self, text: str, first_audio, speaker_id: int = 0) -> list[float]:
        del speaker_id
        first_audio()
        duration = max(0.1, min(1.0, len(text) * 0.03))
        return [
            math.sin(2 * math.pi * 440 * index / self.sample_rate) * 0.2
            for index in range(int(duration * self.sample_rate))
        ]


def load_wave(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        width = source.getsampwidth()
        rate = source.getframerate()
        frames = source.readframes(source.getnframes())
    if width != 2:
        raise ValueError("ZipVoice prompt must be 16-bit PCM")
    values = struct.unpack(f"<{len(frames) // 2}h", frames)
    if channels > 1:
        values = values[::channels]
    return [value / 32768.0 for value in values], rate


class SherpaEngine:
    def __init__(self, engine: str, pack: Path):
        self.engine = engine
        self.pack = pack
        self.model = None
        self.sample_rate = 0
        self.channels = 1

    def prepare(self) -> None:
        import sherpa_onnx

        if self.engine == "sherpa-zipvoice":
            zipvoice = sherpa_onnx.OfflineTtsZipvoiceModelConfig(
                tokens=str(self.pack / "tokens.txt"),
                encoder=str(self.pack / "encoder.int8.onnx"),
                decoder=str(self.pack / "decoder.int8.onnx"),
                vocoder=str(self.pack / "vocos_24khz.onnx"),
                data_dir=str(self.pack / "espeak-ng-data"),
                lexicon=str(self.pack / "lexicon.txt"),
            )
            model = sherpa_onnx.OfflineTtsModelConfig(zipvoice=zipvoice, num_threads=4)
            config = sherpa_onnx.OfflineTtsConfig(model=model)
        else:
            raise ValueError(f"unsupported sherpa engine: {self.engine}")
        if not config.validate():
            raise ValueError(f"invalid {self.engine} configuration")
        self.model = sherpa_onnx.OfflineTts(config)
        self.sample_rate = self.model.sample_rate

    def generate(
        self,
        text: str,
        first_audio,
        speaker_id: int = 0,
        voice_id: str | None = None,
        reference_directory_name: str | None = None,
    ) -> list[float]:
        if self.model is None:
            raise RuntimeError("engine is not prepared")

        def callback(samples, progress):
            del samples, progress
            first_audio()
            return 1

        reference = load_zipvoice_reference(
            self.pack,
            voice_id or "zipvoice-default",
            reference_directory_name,
        )
        text = normalize_zipvoice_text(text)
        if not text:
            raise ValueError("text is empty after ZipVoice normalization")
        audio = self.model.generate(
            text,
            reference.text,
            reference.samples,
            reference.sample_rate,
            callback=callback,
        )
        first_audio()
        self.sample_rate = audio.sample_rate
        return list(audio.samples)


def write_wave(
    path: Path,
    samples: list[float],
    sample_rate: int,
    channels: int = 1,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = [
        max(-32768, min(32767, int(sample * 32767)))
        for sample in samples
    ]
    with wave.open(str(path), "wb") as destination:
        destination.setparams(
            (channels, 2, sample_rate, len(pcm), "NONE", "not compressed")
        )
        destination.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))


def _biquad(
    samples: list[float],
    sample_rate: int,
    cutoff: float,
    kind: str,
) -> list[float]:
    omega = 2 * math.pi * cutoff / sample_rate
    cosine = math.cos(omega)
    sine = math.sin(omega)
    alpha = sine / (2 * math.sqrt(0.5))
    if kind == "highpass":
        b0 = (1 + cosine) / 2
        b1 = -(1 + cosine)
        b2 = b0
    else:
        b0 = (1 - cosine) / 2
        b1 = 1 - cosine
        b2 = b0
    a0 = 1 + alpha
    a1 = -2 * cosine
    a2 = 1 - alpha
    b0, b1, b2, a1, a2 = (
        value / a0 for value in (b0, b1, b2, a1, a2)
    )
    x1 = x2 = y1 = y2 = 0.0
    output = []
    for sample in samples:
        value = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        output.append(value)
        x2, x1 = x1, sample
        y2, y1 = y1, value
    return output


def post_process_zipvoice_samples(
    samples: list[float],
    sample_rate: int,
) -> list[float]:
    """Reduce out-of-band noise and prevent hard PCM clipping without trimming."""
    if not samples or sample_rate <= 0:
        return samples
    processed = _biquad(samples, sample_rate, 45, "highpass")
    processed = _biquad(
        processed,
        sample_rate,
        min(11_500, sample_rate * 0.475),
        "lowpass",
    )
    peak = max(abs(value) for value in processed)
    if peak > 0.95:
        scale = 0.95 / peak
        processed = [value * scale for value in processed]
    return processed


def respond(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True)
    parser.add_argument("--pack", type=Path)
    parser.add_argument("--fake-delay", type=float, default=0)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    if arguments.engine == "fake":
        engine = FakeEngine(arguments.fake_delay)
    else:
        if not arguments.pack:
            raise SystemExit("--pack is required for a real engine")
        if arguments.engine != "sherpa-zipvoice":
            raise SystemExit(f"unsupported engine: {arguments.engine}")
        engine = SherpaEngine(arguments.engine, arguments.pack)
    cold = True
    respond({"ok": True, "phase": "ready"})
    for line in sys.stdin:
        request_id = ""
        try:
            request = json.loads(line)
            request_id = str(request.get("id", ""))
            request_type = request.get("type")
            if request_type == "health":
                respond(
                    {
                        "id": request_id,
                        "ok": True,
                        "phase": "healthy",
                    }
                )
            elif request_type == "prepare":
                started = time.monotonic()
                engine.prepare()
                respond(
                    {
                        "id": request_id,
                        "ok": True,
                        "phase": "prepared",
                        "metrics": {
                            "cold": cold,
                            "prepareSeconds": time.monotonic() - started,
                        },
                    }
                )
                cold = False
            elif request_type == "synthesize":
                text = request.get("text")
                output_text = request.get("output")
                if not isinstance(text, str) or not text.strip():
                    raise ValueError("text is required")
                if not isinstance(output_text, str) or not output_text:
                    raise ValueError("output is required")
                voice_id = request.get("voiceID")
                reference_directory_name = request.get("referenceDirectoryName")
                if arguments.engine == "fake":
                    if not isinstance(voice_id, str) or not voice_id:
                        raise ValueError("voiceID is required")
                    speaker_id = 0
                elif arguments.engine == "sherpa-zipvoice":
                    if voice_id is None:
                        voice_id = "zipvoice-default"
                    if not isinstance(voice_id, str) or not voice_id:
                        raise ValueError("voiceID is required for ZipVoice")
                    speaker_id = 0
                started = time.monotonic()
                first_at = None

                def mark_first_audio():
                    nonlocal first_at
                    if first_at is None:
                        first_at = time.monotonic()

                if arguments.engine == "sherpa-zipvoice":
                    samples = engine.generate(
                        text,
                        mark_first_audio,
                        speaker_id,
                        voice_id,
                        reference_directory_name,
                    )
                else:
                    samples = engine.generate(text, mark_first_audio, speaker_id)
                if arguments.engine == "sherpa-zipvoice":
                    samples = post_process_zipvoice_samples(
                        samples,
                        engine.sample_rate,
                    )
                output = Path(output_text)
                channels = max(1, getattr(engine, "channels", 1))
                write_wave(output, samples, engine.sample_rate, channels)
                elapsed = time.monotonic() - started
                audio_seconds = len(samples) / (engine.sample_rate * channels)
                respond(
                    {
                        "id": request_id,
                        "ok": True,
                        "phase": "completed",
                        "voiceID": voice_id,
                        "speakerID": speaker_id,
                        "metrics": {
                            "firstAudioSeconds": (first_at or time.monotonic()) - started,
                            "synthesisSeconds": elapsed,
                            "audioSeconds": audio_seconds,
                            "rtf": elapsed / max(audio_seconds, 0.000001),
                            "runtimeFamily": getattr(
                                engine,
                                "runtime_family",
                                arguments.engine,
                            ),
                        },
                    }
                )
            elif request_type == "shutdown":
                respond({"id": request_id, "ok": True, "phase": "shutdown"})
                return 0
            else:
                raise ValueError(f"unsupported request type: {request_type}")
        except Exception as error:
            respond(
                {
                    "id": request_id,
                    "ok": False,
                    "phase": "failed",
                    "error": str(error),
                }
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
