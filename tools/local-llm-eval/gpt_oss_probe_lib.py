#!/usr/bin/env python3
"""Dependency-free contracts for the TypeWhale gpt-oss admission probe."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


REQUIRED_MODEL_FILES = (
    "config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "chat_template.jinja",
    "model.safetensors.index.json",
)


@dataclass(frozen=True)
class ModelValidation:
    model_type: str
    architecture: str
    shard_count: int
    total_bytes: int
    missing: tuple[str, ...]
    errors: tuple[str, ...]

    @property
    def valid(self) -> bool:
        return not self.missing and not self.errors


@dataclass(frozen=True)
class HarmonyTokenIDs:
    channel: int
    message: int
    end: int
    return_token: int
    analysis: tuple[int, ...]
    final: tuple[int, ...]


class HarmonyStructureError(ValueError):
    """Raised for unsafe or incomplete Harmony output structure."""


def _load_json_object(path: Path, errors: list[str]) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        errors.append(f"invalid_json:{path.name}")
        return None
    if not isinstance(value, dict):
        errors.append(f"invalid_object:{path.name}")
        return None
    return value


def validate_model_directory(path: Path) -> ModelValidation:
    root = path.expanduser()
    if not root.is_absolute():
        root = root.resolve()
    if not root.is_dir():
        return ModelValidation("", "", 0, 0, (), ("model_root_not_directory",))

    missing = [name for name in REQUIRED_MODEL_FILES if not (root / name).is_file()]
    errors: list[str] = []
    model_type = ""
    architecture = ""
    shards: set[str] = set()

    config_path = root / "config.json"
    if config_path.is_file():
        config = _load_json_object(config_path, errors)
        if config is not None:
            model_type = str(config.get("model_type", ""))
            architectures = config.get("architectures")
            if isinstance(architectures, list) and architectures:
                architecture = str(architectures[0])
            if model_type != "gpt_oss":
                errors.append(f"unsupported_model_type:{model_type or 'missing'}")
            if architecture != "GptOssForCausalLM":
                errors.append(
                    f"unsupported_architecture:{architecture or 'missing'}"
                )

    index_path = root / "model.safetensors.index.json"
    if index_path.is_file():
        index = _load_json_object(index_path, errors)
        if index is not None:
            weight_map = index.get("weight_map")
            if not isinstance(weight_map, dict) or not weight_map:
                errors.append("invalid_weight_map")
            else:
                for value in weight_map.values():
                    if not isinstance(value, str) or not value.endswith(".safetensors"):
                        errors.append("invalid_shard_reference")
                        continue
                    shards.add(value)

    for shard in sorted(shards):
        shard_path = root / shard
        if not shard_path.is_file():
            missing.append(shard)
        elif shard_path.stat().st_size <= 0:
            errors.append(f"zero_byte:{shard}")

    total_bytes = 0
    for file_path in root.iterdir():
        if file_path.is_file():
            try:
                total_bytes += file_path.stat().st_size
            except OSError:
                errors.append(f"unreadable:{file_path.name}")

    return ModelValidation(
        model_type=model_type,
        architecture=architecture,
        shard_count=len(shards),
        total_bytes=total_bytes,
        missing=tuple(sorted(set(missing))),
        errors=tuple(sorted(set(errors))),
    )


def _matches(values: list[int], offset: int, expected: tuple[int, ...]) -> bool:
    return values[offset : offset + len(expected)] == list(expected)


def extract_harmony_final(
    token_ids: list[int],
    ids: HarmonyTokenIDs,
    decode: Callable[[list[int]], str],
) -> str:
    final_segments: list[list[int]] = []
    control_tokens = {ids.channel, ids.message, ids.end, ids.return_token}
    offset = 0

    while offset < len(token_ids):
        if token_ids[offset] != ids.channel:
            offset += 1
            continue

        channel_offset = offset + 1
        if _matches(token_ids, channel_offset, ids.final):
            message_offset = channel_offset + len(ids.final)
            if message_offset >= len(token_ids) or token_ids[message_offset] != ids.message:
                raise HarmonyStructureError("final_missing_message_marker")
            content_offset = message_offset + 1
            content: list[int] = []
            while content_offset < len(token_ids):
                token = token_ids[content_offset]
                if token in {ids.end, ids.return_token}:
                    break
                if token in control_tokens:
                    raise HarmonyStructureError("control_token_in_final")
                content.append(token)
                content_offset += 1
            else:
                raise HarmonyStructureError("unterminated_final")
            final_segments.append(content)
            offset = content_offset + 1
            continue

        if _matches(token_ids, channel_offset, ids.analysis):
            message_offset = channel_offset + len(ids.analysis)
            if message_offset >= len(token_ids) or token_ids[message_offset] != ids.message:
                raise HarmonyStructureError("analysis_missing_message_marker")
            offset = message_offset + 1
            while offset < len(token_ids) and token_ids[offset] not in {
                ids.end,
                ids.return_token,
            }:
                offset += 1
            offset += 1
            continue

        offset += 1

    if not final_segments:
        raise HarmonyStructureError("missing_final_channel")
    if len(final_segments) > 1:
        raise HarmonyStructureError("multiple_final_channels")
    if not final_segments[0]:
        raise HarmonyStructureError("empty_final_channel")

    final_text = decode(final_segments[0]).strip()
    if not final_text:
        raise HarmonyStructureError("empty_final_text")
    return final_text


def evaluate_case(case: dict[str, Any], output: str) -> list[str]:
    failures: list[str] = []
    stripped = output.strip()
    for required in case.get("must_contain", []):
        if required not in stripped:
            failures.append(f"missing:{required}")
    for alternatives in case.get("must_contain_any", []):
        if not any(alternative in stripped for alternative in alternatives):
            failures.append(f"missing_any:{'|'.join(alternatives)}")
    for forbidden in case.get("must_not_contain", []):
        if forbidden in stripped:
            failures.append(f"forbidden:{forbidden}")
    max_chars = int(case.get("max_output_chars", 0))
    if max_chars and len(stripped) > max_chars:
        failures.append(f"too_long:{len(stripped)}>{max_chars}")
    if not stripped:
        failures.append("empty")
    return failures
