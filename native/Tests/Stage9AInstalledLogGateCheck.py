#!/usr/bin/env python3
"""Stage 9A installed-app log gate.

This is intentionally read-only. It parses TypeWhale Pro installation logs and
reports whether the remaining Stage 9A manual gates have real runtime evidence:

1. shadow/candidate disabled single-capsule recording path still reaches
   recording_finish_saved/final_asr_result/paste_finish without shadow logs.
2. cancellation emits recording_cancel_requested + shadow_preview_teardown and
   a later successful recording proves recovery.

Default mode is report-only and exits 0 so agents can inspect current evidence
without pretending a missing manual gate is a test failure. Use
--require-complete after running the manual cases to enforce Stage 9A closure.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


LOG_ROOT = Path.home() / "Library" / "Logs" / "TypeWhale Pro"


TASK_RE = re.compile(r"task_id=([0-9A-Fa-f-]{36})")
SHORT_TASK_RE = re.compile(r"task_id=([0-9A-Fa-f]{8})")
SESSION_RE = re.compile(r"session=([0-9A-Fa-f]{8})")
BUILD_RE = re.compile(r"/(\d+\.\d+\.\d+)-(\d+)\.log$")


@dataclass
class SessionEvidence:
    short_id: str
    log_path: str
    line_start: int
    recording_start: bool = False
    finish_saved: bool = False
    final_asr: bool = False
    paste_finish: bool = False
    shadow_mode: bool = False
    shadow_render: bool = False
    candidate_render: bool = False
    lines: list[str] = field(default_factory=list)

    @property
    def successful(self) -> bool:
        return self.recording_start and self.finish_saved and self.final_asr and self.paste_finish

    @property
    def single_capsule_successful(self) -> bool:
        return self.successful and not (self.shadow_mode or self.shadow_render or self.candidate_render)


@dataclass
class CancelEvidence:
    log_path: str
    line_number: int
    reason: str
    task_short_id: str
    teardown_after: bool = False
    recovery_session: str | None = None

    @property
    def recovered(self) -> bool:
        return self.teardown_after and self.recovery_session is not None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check Stage 9A installed-app log evidence.")
    parser.add_argument(
        "--log-root",
        default=str(LOG_ROOT),
        help="TypeWhale Pro log root. Defaults to ~/Library/Logs/TypeWhale Pro",
    )
    parser.add_argument(
        "--min-build",
        type=int,
        default=748,
        help="Only consider logs with build >= this value. Defaults to 748.",
    )
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="Exit 1 unless both remaining Stage 9A gates have evidence.",
    )
    return parser.parse_args()


def candidate_logs(root: Path, min_build: int) -> list[Path]:
    if not root.exists():
        return []
    logs: list[Path] = []
    for path in root.rglob("*.log"):
        match = BUILD_RE.search(str(path))
        if not match:
            continue
        build = int(match.group(2))
        if build >= min_build:
            logs.append(path)
    return sorted(logs)


def short_task_id(line: str) -> str | None:
    match = TASK_RE.search(line)
    if match:
        return match.group(1)[:8].upper()
    match = SHORT_TASK_RE.search(line)
    if match:
        return match.group(1).upper()
    return None


def session_id(line: str) -> str | None:
    match = SESSION_RE.search(line)
    if match:
        return match.group(1).upper()
    return None


def reason_from_cancel(line: str) -> str:
    match = re.search(r"reason=([^ ]+)", line)
    return match.group(1) if match else "-"


def parse_logs(logs: list[Path]) -> tuple[list[SessionEvidence], list[CancelEvidence]]:
    sessions: dict[str, SessionEvidence] = {}
    ordered_sessions: list[SessionEvidence] = []
    cancels: list[CancelEvidence] = []
    latest_unpasted_final_session: SessionEvidence | None = None

    flattened: list[tuple[Path, int, str]] = []
    for path in logs:
        try:
            lines = path.read_text(errors="replace").splitlines()
        except OSError:
            continue
        for number, line in enumerate(lines, start=1):
            flattened.append((path, number, line))

            task = short_task_id(line)
            sid = session_id(line) or task
            if sid and "recording_start" in line:
                evidence = sessions.get(sid)
                if evidence is None:
                    evidence = SessionEvidence(sid, str(path), number)
                    sessions[sid] = evidence
                    ordered_sessions.append(evidence)
                evidence.recording_start = True
                evidence.lines.append(line)
            elif sid and sid in sessions:
                evidence = sessions[sid]
                evidence.lines.append(line)
                if "recording_finish_saved" in line:
                    evidence.finish_saved = True
                if "final_asr_result" in line:
                    evidence.final_asr = True
                    latest_unpasted_final_session = evidence
                if "paste_finish" in line:
                    evidence.paste_finish = True
                    latest_unpasted_final_session = None
                if "shadow_preview_mode" in line:
                    evidence.shadow_mode = True
                if "shadow_preview_render" in line:
                    evidence.shadow_render = True
                if "candidate_preview_render" in line:
                    evidence.candidate_render = True

            sid = session_id(line)
            if sid and sid in sessions:
                evidence = sessions[sid]
                evidence.lines.append(line)
                if "shadow_preview_render" in line:
                    evidence.shadow_render = True
                if "candidate_preview_render" in line:
                    evidence.candidate_render = True

            if "shadow_preview_mode" in line:
                task_short = short_task_id(line)
                if task_short:
                    evidence = sessions.get(task_short)
                    if evidence is None:
                        evidence = SessionEvidence(task_short, str(path), number)
                        sessions[task_short] = evidence
                        ordered_sessions.append(evidence)
                    evidence.shadow_mode = True
                    evidence.lines.append(line)

            if "paste_finish" in line and sid is None and latest_unpasted_final_session is not None:
                latest_unpasted_final_session.paste_finish = True
                latest_unpasted_final_session.lines.append(line)
                latest_unpasted_final_session = None

            if "recording_cancel_requested" in line:
                cancels.append(
                    CancelEvidence(
                        log_path=str(path),
                        line_number=number,
                        reason=reason_from_cancel(line),
                        task_short_id=short_task_id(line) or "-",
                    )
                )

    successful_after_line: list[tuple[str, str, int]] = [
        (session.short_id, session.log_path, session.line_start)
        for session in ordered_sessions
        if session.successful
    ]

    for cancel in cancels:
        for path, number, line in flattened:
            if str(path) != cancel.log_path or number <= cancel.line_number:
                continue
            if "shadow_preview_teardown" in line and "cancelled=true" in line:
                cancel.teardown_after = True
                break
        for session_id_value, session_path, start_line in successful_after_line:
            if session_path > cancel.log_path or (session_path == cancel.log_path and start_line > cancel.line_number):
                cancel.recovery_session = session_id_value
                break

    return ordered_sessions, cancels


def main() -> int:
    args = parse_args()
    logs = candidate_logs(Path(args.log_root).expanduser(), args.min_build)
    sessions, cancels = parse_logs(logs)

    single_capsule = next((session for session in sessions if session.single_capsule_successful), None)
    recovered_cancel = next((cancel for cancel in cancels if cancel.recovered), None)

    print(f"Stage9AInstalledLogGate logs={len(logs)} min_build={args.min_build}")
    if single_capsule:
        print(
            "PASS single_capsule "
            f"session={single_capsule.short_id} log={single_capsule.log_path}:{single_capsule.line_start}"
        )
    else:
        print(
            "MISSING single_capsule "
            "need recording_start + recording_finish_saved + final_asr_result + paste_finish "
            "with no shadow_preview/candidate_preview lines for that session"
        )

    if recovered_cancel:
        print(
            "PASS cancel_recovery "
            f"reason={recovered_cancel.reason} task={recovered_cancel.task_short_id} "
            f"log={recovered_cancel.log_path}:{recovered_cancel.line_number} "
            f"recovery_session={recovered_cancel.recovery_session}"
        )
    else:
        print(
            "MISSING cancel_recovery "
            "need recording_cancel_requested + shadow_preview_teardown cancelled=true + later successful recording"
        )

    if args.require_complete and (single_capsule is None or recovered_cancel is None):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
