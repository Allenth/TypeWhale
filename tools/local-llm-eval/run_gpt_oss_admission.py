#!/usr/bin/env python3
"""Run TypeWhale's isolated local gpt-oss MLX admission checks."""

from __future__ import annotations

import argparse
import json
import os
import selectors
import shutil
import signal
import subprocess
import tempfile
import time
from dataclasses import asdict
from pathlib import Path
from typing import Any, Mapping

from gpt_oss_probe_lib import evaluate_case, validate_model_directory


FORBIDDEN_EVIDENCE_KEYS = {"analysis", "thinking", "raw_tokens", "raw_output"}


class WorkerTimeoutError(TimeoutError):
    """Raised when an owned probe worker misses a protocol deadline."""


class WorkerProtocolError(RuntimeError):
    """Raised for malformed or incomplete worker JSONL."""


def offline_environment(base: Mapping[str, str]) -> dict[str, str]:
    environment = dict(base)
    environment.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "TOKENIZERS_PARALLELISM": "false",
            "PYTHONNOUSERSITE": "1",
        }
    )
    return environment


def require_absolute_model_directory(path: Path) -> Path:
    if not path.is_absolute():
        raise ValueError("model_path_must_be_absolute")
    resolved = path.resolve()
    if not resolved.is_dir():
        raise ValueError("model_path_not_directory")
    return resolved


def assert_safe_evidence(value: Any) -> None:
    if isinstance(value, dict):
        for key, nested in value.items():
            if str(key).lower() in FORBIDDEN_EVIDENCE_KEYS:
                raise ValueError(f"forbidden_evidence_key:{key}")
            assert_safe_evidence(nested)
    elif isinstance(value, list):
        for nested in value:
            assert_safe_evidence(nested)


def admission_decision(evidence: dict[str, Any]) -> str:
    required_sections = (
        "model_validation",
        "cold_start",
        "case_results",
        "warm_continuity",
        "cancellation",
        "recovery",
        "apfs_clone",
    )
    if any(section not in evidence for section in required_sections):
        return "INCONCLUSIVE"
    if not evidence["model_validation"].get("valid", False):
        return "REJECT"
    if evidence["cold_start"].get("status") != "ok":
        return "REJECT"
    cases = evidence["case_results"]
    if any(
        case.get("status") != "ok" or bool(case.get("failures"))
        for case in cases
    ):
        return "REJECT"
    if len(cases) < 3:
        return "INCONCLUSIVE"
    if evidence["warm_continuity"].get("status") != "ok":
        return "REJECT"
    if int(evidence["warm_continuity"].get("count", 0)) < 3:
        return "REJECT"
    for section in ("cancellation", "recovery", "apfs_clone"):
        if evidence[section].get("status") != "ok":
            return "REJECT"
    return "ADMIT"


class WorkerClient:
    def __init__(
        self,
        *,
        python_path: Path,
        worker_path: Path,
        model_dir: Path,
        environment: Mapping[str, str],
    ) -> None:
        self.python_path = python_path
        self.worker_path = worker_path
        self.model_dir = model_dir
        self.environment = dict(environment)
        self.process: subprocess.Popen[str] | None = None
        self._stderr_file = None

    def start(self, *, timeout_seconds: float) -> dict[str, Any]:
        if self.process is not None:
            raise WorkerProtocolError("worker_already_started")
        self._stderr_file = tempfile.TemporaryFile(mode="w+", encoding="utf-8")
        self.process = subprocess.Popen(
            [
                str(self.python_path),
                str(self.worker_path),
                "--model-dir",
                str(self.model_dir),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self._stderr_file,
            text=True,
            bufsize=1,
            env=self.environment,
            start_new_session=True,
        )
        ready = self._read_event(timeout_seconds=timeout_seconds)
        if ready.get("type") != "ready" or ready.get("status") != "ok":
            raise WorkerProtocolError("worker_not_ready")
        return ready

    def request(
        self, command: dict[str, Any], *, timeout_seconds: float
    ) -> dict[str, Any]:
        process = self._require_process()
        if process.stdin is None:
            raise WorkerProtocolError("worker_stdin_unavailable")
        process.stdin.write(json.dumps(command, ensure_ascii=False) + "\n")
        process.stdin.flush()
        return self._read_event(timeout_seconds=timeout_seconds)

    def shutdown(self, *, timeout_seconds: float) -> None:
        process = self._require_process()
        event = self.request({"type": "shutdown"}, timeout_seconds=timeout_seconds)
        if event.get("type") != "shutdown" or event.get("status") != "ok":
            raise WorkerProtocolError("worker_shutdown_rejected")
        process.wait(timeout=timeout_seconds)
        self._close_streams()

    def terminate(self) -> None:
        process = self.process
        if process is None:
            return
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
        self._close_streams()

    def _require_process(self) -> subprocess.Popen[str]:
        if self.process is None:
            raise WorkerProtocolError("worker_not_started")
        return self.process

    def _read_event(self, *, timeout_seconds: float) -> dict[str, Any]:
        process = self._require_process()
        if process.stdout is None:
            raise WorkerProtocolError("worker_stdout_unavailable")
        selector = selectors.DefaultSelector()
        try:
            selector.register(process.stdout, selectors.EVENT_READ)
            if not selector.select(timeout_seconds):
                raise WorkerTimeoutError("worker_event_timeout")
            line = process.stdout.readline()
        finally:
            selector.close()
        if not line:
            raise WorkerProtocolError("worker_closed_without_event")
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise WorkerProtocolError("worker_invalid_json") from error
        if not isinstance(value, dict):
            raise WorkerProtocolError("worker_event_not_object")
        return value

    def _close_streams(self) -> None:
        if self.process is not None:
            if self.process.stdin is not None and not self.process.stdin.closed:
                self.process.stdin.close()
            if self.process.stdout is not None and not self.process.stdout.closed:
                self.process.stdout.close()
        if self._stderr_file is not None:
            self._stderr_file.close()
            self._stderr_file = None


def file_snapshot(root: Path) -> list[dict[str, Any]]:
    snapshot: list[dict[str, Any]] = []
    for path in sorted(root.iterdir(), key=lambda item: item.name):
        if not path.is_file():
            continue
        stat = path.stat()
        snapshot.append(
            {
                "name": path.name,
                "size": stat.st_size,
                "mtime_ns": stat.st_mtime_ns,
            }
        )
    return snapshot


def run_apfs_clone_check(
    model_dir: Path, source_validation: dict[str, Any]
) -> dict[str, Any]:
    temp_root = Path(tempfile.mkdtemp(prefix="typewhale-gpt-oss-clone-")).resolve()
    clone_root = temp_root / "model"
    expected_parent = Path(tempfile.gettempdir()).resolve()
    try:
        if (
            not temp_root.name.startswith("typewhale-gpt-oss-clone-")
            or temp_root.parent != expected_parent
            or not clone_root.is_relative_to(temp_root)
        ):
            raise RuntimeError("unsafe_clone_temp_path")
        started = time.perf_counter()
        subprocess.run(
            ["cp", "-cR", str(model_dir), str(clone_root)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        clone_ms = (time.perf_counter() - started) * 1000
        validation = validate_model_directory(clone_root)
        if (
            not validation.valid
            or validation.total_bytes != int(source_validation["total_bytes"])
        ):
            return {"status": "error", "error_code": "clone_validation_failed"}
        return {
            "status": "ok",
            "clone_ms": round(clone_ms, 3),
            "total_bytes": validation.total_bytes,
            "shard_count": validation.shard_count,
        }
    except BaseException as error:
        return {
            "status": "error",
            "error_type": type(error).__name__,
            "error_code": "apfs_clone_failed",
        }
    finally:
        if (
            temp_root.name.startswith("typewhale-gpt-oss-clone-")
            and temp_root.parent == expected_parent
        ):
            shutil.rmtree(temp_root)


def load_cases(path: Path) -> list[dict[str, Any]]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, list) or not value:
        raise ValueError("cases_must_be_nonempty_array")
    if not all(isinstance(case, dict) for case in value):
        raise ValueError("case_must_be_object")
    return value


def command_for_case(case: dict[str, Any], request_id: str) -> dict[str, Any]:
    command = {
        "type": "generate",
        "request_id": request_id,
        "task": case["task"],
        "text": case["text"],
        "max_tokens": int(case["max_tokens"]),
    }
    if case.get("target_language"):
        command["target_language"] = case["target_language"]
    return command


def render_report(evidence: dict[str, Any]) -> str:
    lines = [
        "# GPT-OSS 本地 MLX 隔离准入报告",
        "",
        f"- 决策：**{evidence['decision']}**",
        "- 模型：`mlx-community/gpt-oss-20b-MXFP4-Q8`",
        "- 来源：`~/.lmstudio/models/mlx-community/gpt-oss-20b-MXFP4-Q8`（只读）",
        "- 运行方式：TypeWhale 受管 Python 中的独立 MLX worker，完全离线",
        "",
        "## 性能",
        "",
        "| 阶段 | 加载 ms | 首 token ms | 完成 ms | tok/s | 峰值 RSS |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    cold = evidence.get("cold_start", {})
    first_case = (evidence.get("case_results") or [{}])[0]
    lines.append(
        "| 冷启动与首个样本 | "
        f"{cold.get('load_ms', '—')} | "
        f"{first_case.get('prefill_and_ttft_ms', '—')} | "
        f"{first_case.get('completion_ms', '—')} | "
        f"{first_case.get('decode_tokens_per_second', '—')} | "
        f"{first_case.get('peak_rss_bytes', '—')} |"
    )
    lines.extend(
        [
            "",
            "## 合成样本",
            "",
            "| ID | 状态 | 断言 | 输出 |",
            "|---|---|---|---|",
        ]
    )
    for case in evidence.get("case_results", []):
        output = str(case.get("final", "")).replace("|", "\\|").replace("\n", " ")
        failures = ", ".join(case.get("failures", [])) or "通过"
        lines.append(
            f"| {case.get('case_id', '')} | {case.get('status', '')} | "
            f"{failures} | {output} |"
        )
    lines.extend(
        [
            "",
            "## 稳定性与导入",
            "",
            f"- 同进程连续调用：{evidence.get('warm_continuity', {}).get('status', 'missing')}",
            f"- 取消并终止自有 worker：{evidence.get('cancellation', {}).get('status', 'missing')}",
            f"- 新 worker 恢复：{evidence.get('recovery', {}).get('status', 'missing')}",
            f"- APFS clone-on-write：{evidence.get('apfs_clone', {}).get('status', 'missing')}",
            f"- 外部模型源文件保持不变：{evidence.get('source_immutable', False)}",
            "",
            "## 决策边界",
            "",
            "本报告只决定该模型是否有资格进入后续生产接入计划；不会改变当前默认模型、Ollama 路由或 TypeWhale 安装版。",
            "",
        ]
    )
    return "\n".join(lines)


def write_evidence(
    evidence: dict[str, Any], output_json: Path, output_report: Path
) -> None:
    assert_safe_evidence(evidence)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_report.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    output_report.write_text(render_report(evidence), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--cases", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-report", required=True)
    parser.add_argument("--request-timeout-seconds", type=float, default=30)
    parser.add_argument("--cancel-after-seconds", type=float, default=1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    python_path = Path(args.python).expanduser()
    if not python_path.is_absolute() or not python_path.is_file():
        raise ValueError("python_path_must_be_absolute_file")
    model_dir = require_absolute_model_directory(
        Path(args.model_dir).expanduser()
    )
    cases = load_cases(Path(args.cases))
    worker_path = Path(__file__).with_name("gpt_oss_worker.py").resolve()
    environment = offline_environment(os.environ)
    source_before = file_snapshot(model_dir)
    validation = validate_model_directory(model_dir)
    evidence: dict[str, Any] = {
        "model_validation": {**asdict(validation), "valid": validation.valid},
        "case_results": [],
    }
    active_client: WorkerClient | None = None

    try:
        if not validation.valid:
            evidence["decision"] = "REJECT"
            evidence["source_immutable"] = source_before == file_snapshot(model_dir)
            write_evidence(
                evidence, Path(args.output_json), Path(args.output_report)
            )
            return 1

        active_client = WorkerClient(
            python_path=python_path,
            worker_path=worker_path,
            model_dir=model_dir,
            environment=environment,
        )
        cold_ready = active_client.start(
            timeout_seconds=max(120, args.request_timeout_seconds)
        )
        evidence["cold_start"] = cold_ready

        for case in cases:
            result = active_client.request(
                command_for_case(case, f"cold-{case['id']}"),
                timeout_seconds=args.request_timeout_seconds,
            )
            result["case_id"] = case["id"]
            result["failures"] = (
                evaluate_case(case, str(result.get("final", "")))
                if result.get("status") == "ok"
                else ["worker_error"]
            )
            evidence["case_results"].append(result)

        warm_results = []
        worker_pid = active_client.process.pid if active_client.process else None
        for case in cases[:3]:
            warm_results.append(
                active_client.request(
                    command_for_case(case, f"warm-{case['id']}"),
                    timeout_seconds=args.request_timeout_seconds,
                )
            )
        evidence["warm_continuity"] = {
            "status": (
                "ok"
                if len(warm_results) == 3
                and all(result.get("status") == "ok" for result in warm_results)
                else "error"
            ),
            "count": len(warm_results),
            "worker_pid": worker_pid,
        }
        active_client.shutdown(timeout_seconds=5)
        active_client = None

        cancel_client = WorkerClient(
            python_path=python_path,
            worker_path=worker_path,
            model_dir=model_dir,
            environment=environment,
        )
        active_client = cancel_client
        cancel_ready = cancel_client.start(
            timeout_seconds=max(120, args.request_timeout_seconds)
        )
        long_text = "请忠实保留这段用于取消测试的合成文字。" * 600
        cancelled = False
        try:
            cancel_client.request(
                {
                    "type": "generate",
                    "request_id": "cancel-stress",
                    "task": "rewrite",
                    "text": long_text,
                    "max_tokens": 2048,
                },
                timeout_seconds=args.cancel_after_seconds,
            )
        except WorkerTimeoutError:
            cancelled = True
        cancel_client.terminate()
        evidence["cancellation"] = {
            "status": "ok" if cancelled else "error",
            "worker_pid": cancel_ready.get("worker_pid", cancel_client.process.pid if cancel_client.process else None),
            "terminated": bool(
                cancel_client.process is not None
                and cancel_client.process.poll() is not None
            ),
        }
        active_client = None

        recovery_client = WorkerClient(
            python_path=python_path,
            worker_path=worker_path,
            model_dir=model_dir,
            environment=environment,
        )
        active_client = recovery_client
        recovery_ready = recovery_client.start(
            timeout_seconds=max(120, args.request_timeout_seconds)
        )
        recovery_result = recovery_client.request(
            {
                "type": "generate",
                "request_id": "recovery-health",
                "task": "rewrite",
                "text": "恢复后继续保持本地运行。",
                "max_tokens": 96,
            },
            timeout_seconds=args.request_timeout_seconds,
        )
        evidence["recovery"] = {
            "status": recovery_result.get("status"),
            "worker_pid": recovery_ready.get(
                "worker_pid",
                recovery_client.process.pid if recovery_client.process else None,
            ),
            "final": recovery_result.get("final", ""),
        }
        recovery_client.shutdown(timeout_seconds=5)
        active_client = None

        evidence["apfs_clone"] = run_apfs_clone_check(
            model_dir, evidence["model_validation"]
        )
    except BaseException as error:
        evidence["run_error"] = {
            "error_type": type(error).__name__,
            "error_code": "admission_run_interrupted",
        }
    finally:
        if active_client is not None:
            active_client.terminate()

    evidence["source_immutable"] = source_before == file_snapshot(model_dir)
    evidence["decision"] = admission_decision(evidence)
    write_evidence(evidence, Path(args.output_json), Path(args.output_report))
    return 0 if evidence["decision"] == "ADMIT" else 1


if __name__ == "__main__":
    raise SystemExit(main())
