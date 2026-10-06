#!/usr/bin/env python3
"""Persistent, local-only MLX worker for TypeWhale-managed language models."""

from __future__ import annotations

import contextlib
import copy
import json
import os
import resource
import signal
import sys
import time
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"
os.environ["HF_DATASETS_OFFLINE"] = "1"
os.environ["TOKENIZERS_PARALLELISM"] = "false"

PROTOCOL_VERSION = 1
MAX_TOKENS = 2048


class WorkerRequestError(ValueError):
    pass


@dataclass(frozen=True)
class PromptCacheMatch:
    cache: list[Any] | None
    remaining_tokens: list[int]
    reused_tokens: int


@dataclass(frozen=True)
class PromptCacheEntry:
    cache: list[Any]
    byte_count: int


class PromptPrefixCache:
    def __init__(
        self,
        max_size: int,
        max_total_tokens: int = 2_048,
        max_total_bytes: int = 384 * 1_024 * 1_024,
    ) -> None:
        if max_size < 1:
            raise ValueError("max_size_must_be_positive")
        if max_total_tokens < 1:
            raise ValueError("max_total_tokens_must_be_positive")
        if max_total_bytes < 1:
            raise ValueError("max_total_bytes_must_be_positive")
        self.max_size = max_size
        self.max_total_tokens = max_total_tokens
        self.max_total_bytes = max_total_bytes
        self._entries: OrderedDict[
            tuple[str, tuple[int, ...]], PromptCacheEntry
        ] = OrderedDict()

    def clear(self) -> None:
        self._entries.clear()

    def insert(
        self,
        model_key: str,
        tokens: list[int],
        prompt_cache: list[Any],
        *,
        cache_bytes: int = 0,
    ) -> None:
        if cache_bytes < 0:
            raise ValueError("cache_bytes_must_not_be_negative")
        if (
            len(tokens) > self.max_total_tokens
            or cache_bytes > self.max_total_bytes
        ):
            return
        key = (model_key, tuple(tokens))
        self._entries.pop(key, None)
        self._entries[key] = PromptCacheEntry(
            cache=prompt_cache,
            byte_count=cache_bytes,
        )
        while (
            len(self._entries) > self.max_size
            or self._total_tokens() > self.max_total_tokens
            or self._total_bytes() > self.max_total_bytes
        ):
            self._entries.popitem(last=False)

    def _total_tokens(self) -> int:
        return sum(len(tokens) for _, tokens in self._entries)

    def _total_bytes(self) -> int:
        return sum(entry.byte_count for entry in self._entries.values())

    def fetch(
        self,
        model_key: str,
        tokens: list[int],
        *,
        can_trim: Callable[[list[Any]], bool],
        trim: Callable[[list[Any], int], Any],
    ) -> PromptCacheMatch:
        miss = PromptCacheMatch(None, list(tokens), 0)
        if not tokens:
            return miss

        best_key: tuple[str, tuple[int, ...]] | None = None
        best_prefix = 0
        for key in self._entries:
            cached_model, cached_tokens = key
            if cached_model != model_key:
                continue
            prefix = self._common_prefix_length(cached_tokens, tokens)
            if prefix > best_prefix:
                best_key = key
                best_prefix = prefix

        if best_key is None or best_prefix == 0:
            return miss

        cached_tokens = best_key[1]
        try:
            cloned_cache = copy.deepcopy(self._entries[best_key].cache)
            if best_prefix == len(cached_tokens) and best_prefix < len(tokens):
                reused_tokens = best_prefix
            else:
                reused_tokens = min(best_prefix, len(tokens) - 1)
                tokens_to_trim = len(cached_tokens) - reused_tokens
                if tokens_to_trim > 0:
                    if not can_trim(cloned_cache):
                        return miss
                    trim(cloned_cache, tokens_to_trim)
        except Exception:
            return miss

        self._entries.move_to_end(best_key)
        return PromptCacheMatch(
            cache=cloned_cache,
            remaining_tokens=list(tokens[reused_tokens:]),
            reused_tokens=reused_tokens,
        )

    @staticmethod
    def _common_prefix_length(
        left: tuple[int, ...],
        right: list[int],
    ) -> int:
        limit = min(len(left), len(right))
        index = 0
        while index < limit and left[index] == right[index]:
            index += 1
        return index


def _compact_cache_state(
    value: Any,
    *,
    mx: Any,
    arrays: list[Any],
) -> Any:
    if isinstance(value, mx.array):
        compacted = mx.contiguous(value)
        arrays.append(compacted)
        return compacted
    if isinstance(value, tuple):
        return tuple(
            _compact_cache_state(item, mx=mx, arrays=arrays)
            for item in value
        )
    if isinstance(value, list):
        return [
            _compact_cache_state(item, mx=mx, arrays=arrays)
            for item in value
        ]
    if isinstance(value, dict):
        return {
            key: _compact_cache_state(item, mx=mx, arrays=arrays)
            for key, item in value.items()
        }
    return value


def compact_prompt_cache(prompt_cache: list[Any]) -> int:
    """Materialize logically trimmed cache state and return retained bytes."""
    stateful_caches = [
        cache for cache in prompt_cache if hasattr(type(cache), "state")
    ]
    if not stateful_caches:
        return 0

    import mlx.core as mx

    arrays: list[Any] = []
    compacted_states: list[tuple[Any, Any]] = []
    for cache in stateful_caches:
        compacted_states.append(
            (
                cache,
                _compact_cache_state(cache.state, mx=mx, arrays=arrays),
            )
        )
    if arrays:
        mx.eval(*arrays)
    for cache, state in compacted_states:
        cache.state = state
    return sum(int(array.nbytes) for array in arrays)


@dataclass(frozen=True)
class PreparedGeneration:
    cache: list[Any] | None
    input_tokens: list[int]
    hit: bool
    reused_tokens: int


def decode_generated_text(tokenizer: Any, token_ids: list[int]) -> str:
    """Decode only newly generated Qwen tokens into the user-visible final text."""
    final_text = tokenizer.decode(
        token_ids,
        skip_special_tokens=True,
    ).strip()
    if not final_text:
        raise WorkerRequestError("empty_final_text")
    return final_text


def peak_rss_bytes() -> int:
    value = int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    return value if sys.platform == "darwin" else value * 1024


def emit(value: dict[str, Any]) -> None:
    sys.stdout.write(
        json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n"
    )
    sys.stdout.flush()


def _local_model_directory(value: Any) -> str:
    path = Path(str(value or "")).expanduser()
    if not path.is_absolute() or not path.is_dir():
        raise WorkerRequestError("model_directory_invalid")
    return str(path.resolve())


def _request_id(request: dict[str, Any]) -> str:
    request_id = str(request.get("id", ""))
    if not request_id or len(request_id) > 128:
        raise WorkerRequestError("request_id_invalid")
    return request_id


def _error_response(request_id: str, error: BaseException) -> dict[str, Any]:
    if isinstance(error, WorkerRequestError):
        error_code = str(error) or "invalid_request"
        error_message = "本地模型请求无效"
    else:
        error_code = "generation_failed"
        error_message = "本地模型生成失败"
    return {
        "protocol_version": PROTOCOL_VERSION,
        "id": request_id,
        "ok": False,
        "final_text": None,
        "error_code": error_code,
        "error_message": error_message,
        "metrics": None,
        "cancelled": False,
    }


class WorkerState:
    def __init__(self) -> None:
        self.model_directory: str | None = None
        self.model: Any = None
        self.tokenizer: Any = None
        self.sampler: Any = None
        self.last_load_ms: float | None = None
        self.prompt_prefix_cache = PromptPrefixCache(
            max_size=4,
            max_total_tokens=2_048,
            max_total_bytes=384 * 1_024 * 1_024,
        )

    def handle(self, request: dict[str, Any]) -> dict[str, Any]:
        request_id = _request_id(request)
        if request.get("protocol_version") != PROTOCOL_VERSION:
            raise WorkerRequestError("protocol_version_unsupported")

        command = str(request.get("command", ""))
        if command == "health":
            return self._success(request_id, None, None)
        if command == "warmup":
            self._load(_local_model_directory(request.get("model_directory")))
            return self._success(request_id, None, self._metrics())
        if command not in {"rewrite", "translate"}:
            raise WorkerRequestError("command_unsupported")

        model_directory = _local_model_directory(request.get("model_directory"))
        system_prompt = str(request.get("system_prompt", "")).strip()
        user_prompt = str(request.get("user_prompt", "")).strip()
        if not system_prompt or not user_prompt:
            raise WorkerRequestError("prompt_required")
        if request.get("reasoning") != "low":
            raise WorkerRequestError("reasoning_unsupported")
        max_tokens = int(request.get("max_tokens", 0))
        if not 1 <= max_tokens <= MAX_TOKENS:
            raise WorkerRequestError("max_tokens_out_of_range")

        self._load(model_directory)
        return self._generate(
            request_id=request_id,
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            max_tokens=max_tokens,
        )

    def _load(self, model_directory: str) -> None:
        if (
            self.model_directory == model_directory
            and self.model is not None
            and self.tokenizer is not None
        ):
            return

        with contextlib.redirect_stdout(sys.stderr):
            from mlx_lm import load
            from mlx_lm.sample_utils import make_sampler

            started = time.perf_counter()
            model, tokenizer = load(
                model_directory,
                tokenizer_config={
                    "local_files_only": True,
                    "trust_remote_code": False,
                },
                lazy=False,
            )
            load_ms = (time.perf_counter() - started) * 1_000
            sampler = make_sampler(temp=0.0)

        self.model_directory = model_directory
        self.model = model
        self.tokenizer = tokenizer
        self.sampler = sampler
        self.last_load_ms = load_ms
        self.prompt_prefix_cache.clear()

    def _prepare_generation_cache(
        self,
        *,
        prompt_tokens: list[int],
        make_cache: Callable[[Any], list[Any]],
        can_trim: Callable[[list[Any]], bool],
        trim: Callable[[list[Any], int], Any],
    ) -> PreparedGeneration:
        if self.model is None:
            raise RuntimeError("model_not_loaded")

        try:
            match = self.prompt_prefix_cache.fetch(
                self.model_directory or "",
                prompt_tokens,
                can_trim=can_trim,
                trim=trim,
            )
            if match.cache is not None and match.reused_tokens > 0:
                return PreparedGeneration(
                    cache=match.cache,
                    input_tokens=match.remaining_tokens,
                    hit=True,
                    reused_tokens=match.reused_tokens,
                )
            return PreparedGeneration(
                cache=make_cache(self.model),
                input_tokens=list(prompt_tokens),
                hit=False,
                reused_tokens=0,
            )
        except Exception:
            return PreparedGeneration(
                cache=None,
                input_tokens=list(prompt_tokens),
                hit=False,
                reused_tokens=0,
            )

    def _run_with_cache_fallback(
        self,
        *,
        prompt_tokens: list[int],
        make_cache: Callable[[Any], list[Any]],
        can_trim: Callable[[list[Any]], bool],
        trim: Callable[[list[Any], int], Any],
        run: Callable[[PreparedGeneration], Any],
    ) -> tuple[PreparedGeneration, Any]:
        prepared = self._prepare_generation_cache(
            prompt_tokens=prompt_tokens,
            make_cache=make_cache,
            can_trim=can_trim,
            trim=trim,
        )
        try:
            return prepared, run(prepared)
        except Exception:
            if not prepared.hit:
                raise

        self.prompt_prefix_cache.clear()
        try:
            fresh_cache = make_cache(self.model)
        except Exception:
            fresh_cache = None
        fallback = PreparedGeneration(
            cache=fresh_cache,
            input_tokens=list(prompt_tokens),
            hit=False,
            reused_tokens=0,
        )
        return fallback, run(fallback)

    def _store_prompt_cache(
        self,
        *,
        prompt_tokens: list[int],
        generated_token_count: int,
        prompt_cache: list[Any] | None,
        can_trim: Callable[[list[Any]], bool],
        trim: Callable[[list[Any], int], Any],
    ) -> bool:
        if prompt_cache is None:
            return False
        try:
            if generated_token_count > 0:
                if not can_trim(prompt_cache):
                    return False
                trim(prompt_cache, generated_token_count)
            retained_bytes = compact_prompt_cache(prompt_cache)
            self.prompt_prefix_cache.insert(
                self.model_directory or "",
                prompt_tokens,
                prompt_cache,
                cache_bytes=retained_bytes,
            )
            return True
        except Exception:
            return False

    def _generate(
        self,
        *,
        request_id: str,
        system_prompt: str,
        user_prompt: str,
        max_tokens: int,
    ) -> dict[str, Any]:
        if (
            self.model is None
            or self.tokenizer is None
            or self.sampler is None
        ):
            raise RuntimeError("model_not_loaded")

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]
        prompt = self.tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )
        prompt_token_ids = list(
            self.tokenizer.encode(prompt, add_special_tokens=False)
        )
        prompt_tokens = len(prompt_token_ids)
        with contextlib.redirect_stdout(sys.stderr):
            from mlx_lm import stream_generate
            from mlx_lm.models.cache import (
                can_trim_prompt_cache,
                make_prompt_cache,
                trim_prompt_cache,
            )

            def run_generation(
                prepared_generation: PreparedGeneration,
            ) -> tuple[float, float, list[int], Any]:
                generation_started = time.perf_counter()
                first_token_at: float | None = None
                response_token_ids: list[int] = []
                final_response: Any = None

                for response in stream_generate(
                    self.model,
                    self.tokenizer,
                    prepared_generation.input_tokens,
                    max_tokens=max_tokens,
                    sampler=self.sampler,
                    prompt_cache=prepared_generation.cache,
                ):
                    if first_token_at is None:
                        first_token_at = time.perf_counter()
                    response_token_ids.append(int(response.token))
                    final_response = response

                completed_at = time.perf_counter()
                if first_token_at is None or final_response is None:
                    raise RuntimeError("generation_empty")
                return (
                    (first_token_at - generation_started) * 1_000,
                    (completed_at - generation_started) * 1_000,
                    response_token_ids,
                    final_response,
                )

            prepared, generation = self._run_with_cache_fallback(
                prompt_tokens=prompt_token_ids,
                make_cache=make_prompt_cache,
                can_trim=can_trim_prompt_cache,
                trim=trim_prompt_cache,
                run=run_generation,
            )
            (
                ttft_ms,
                completion_ms,
                response_token_ids,
                final_response,
            ) = generation

        final_text = decode_generated_text(self.tokenizer, response_token_ids)
        self._store_prompt_cache(
            prompt_tokens=prompt_token_ids,
            generated_token_count=len(response_token_ids),
            prompt_cache=prepared.cache,
            can_trim=can_trim_prompt_cache,
            trim=trim_prompt_cache,
        )
        metrics = self._metrics(
            ttft_ms=ttft_ms,
            completion_ms=completion_ms,
            tokens_per_second=float(final_response.generation_tps),
            prompt_tokens=prompt_tokens,
            completion_tokens=int(final_response.generation_tokens),
            prompt_cache_hit=prepared.hit,
            prompt_cache_reused_tokens=prepared.reused_tokens,
            prompt_tokens_evaluated=len(prepared.input_tokens),
        )
        return self._success(request_id, final_text, metrics)

    def _metrics(
        self,
        *,
        ttft_ms: float | None = None,
        completion_ms: float | None = None,
        tokens_per_second: float | None = None,
        prompt_tokens: int | None = None,
        completion_tokens: int | None = None,
        prompt_cache_hit: bool = False,
        prompt_cache_reused_tokens: int = 0,
        prompt_tokens_evaluated: int | None = None,
    ) -> dict[str, Any]:
        return {
            "load_ms": (
                round(self.last_load_ms, 3)
                if self.last_load_ms is not None
                else None
            ),
            "ttft_ms": round(ttft_ms, 3) if ttft_ms is not None else None,
            "completion_ms": (
                round(completion_ms, 3) if completion_ms is not None else None
            ),
            "tokens_per_second": (
                round(tokens_per_second, 3)
                if tokens_per_second is not None
                else None
            ),
            "peak_rss_bytes": peak_rss_bytes(),
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "prompt_cache_hit": prompt_cache_hit,
            "prompt_cache_reused_tokens": prompt_cache_reused_tokens,
            "prompt_tokens_evaluated": prompt_tokens_evaluated,
        }

    @staticmethod
    def _success(
        request_id: str,
        final_text: str | None,
        metrics: dict[str, Any] | None,
    ) -> dict[str, Any]:
        return {
            "protocol_version": PROTOCOL_VERSION,
            "id": request_id,
            "ok": True,
            "final_text": final_text,
            "error_code": None,
            "error_message": None,
            "metrics": metrics,
            "cancelled": False,
        }


def _terminate_cleanly(_signum: int, _frame: Any) -> None:
    raise SystemExit(0)


def main() -> int:
    signal.signal(signal.SIGTERM, _terminate_cleanly)
    state = WorkerState()
    for line in sys.stdin:
        request_id = ""
        try:
            decoded = json.loads(line)
            if not isinstance(decoded, dict):
                raise WorkerRequestError("request_not_object")
            request_id = str(decoded.get("id", ""))
            response = state.handle(decoded)
        except (KeyboardInterrupt, SystemExit):
            raise
        except BaseException as error:
            response = _error_response(request_id, error)
        emit(response)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
