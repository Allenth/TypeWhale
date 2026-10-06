#!/usr/bin/env python3
import importlib.util
from pathlib import Path


root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "tts_benchmark_worker",
    root / "native/Resources/tts_benchmark_worker.py",
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)

source = """好。

---

深海里有一只小海胆。

小海胆奇怪："你不怕疼吗？"

第一次发现——原来被扎到和被记得，可以同时发生。

---

🦞 讲完了。"""

normalized = worker.normalize_zipvoice_text(source)
assert normalized.startswith("好。深海里有一只小海胆。")
assert "你不怕疼吗？" in normalized
assert "第一次发现，原来被扎到和被记得，可以同时发生。" in normalized
assert normalized.endswith("讲完了。")
assert "---" not in normalized
assert "🦞" not in normalized
assert "\n" not in normalized
assert '"' not in normalized

plain = "今天开始测试，请完整读出每一个字。"
assert worker.normalize_zipvoice_text(plain) == plain
mixed = "TypeWhale reads this sentence clearly.\n\n第二段。"
assert worker.normalize_zipvoice_text(mixed) == "TypeWhale reads this sentence clearly.第二段。"

print("TTSZipVoiceTextNormalizationCheck passed")
