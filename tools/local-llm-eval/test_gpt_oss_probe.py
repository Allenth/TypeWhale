#!/usr/bin/env python3
"""Offline contract checks for the TypeWhale gpt-oss admission probe."""

from __future__ import annotations

import json
import importlib.util
import os
import re
import textwrap
import tempfile
import unittest
from pathlib import Path

from gpt_oss_probe_lib import (
    HarmonyStructureError,
    HarmonyTokenIDs,
    evaluate_case,
    extract_harmony_final,
    validate_model_directory,
)


class ModelValidationTests(unittest.TestCase):
    def make_model_fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        (root / "config.json").write_text(
            json.dumps(
                {
                    "model_type": "gpt_oss",
                    "architectures": ["GptOssForCausalLM"],
                }
            ),
            encoding="utf-8",
        )
        (root / "tokenizer.json").write_text("{}", encoding="utf-8")
        (root / "tokenizer_config.json").write_text("{}", encoding="utf-8")
        (root / "chat_template.jinja").write_text(
            "Reasoning: {{ reasoning_effort }} final", encoding="utf-8"
        )
        shards = [f"model-{index:05d}-of-00003.safetensors" for index in range(1, 4)]
        (root / "model.safetensors.index.json").write_text(
            json.dumps(
                {
                    "weight_map": {
                        f"layer.{index}": shard for index, shard in enumerate(shards)
                    }
                }
            ),
            encoding="utf-8",
        )
        for index, shard in enumerate(shards, start=1):
            (root / shard).write_bytes(bytes([index]))
        return temporary, root

    def test_accepts_complete_local_gpt_oss_model(self) -> None:
        temporary, root = self.make_model_fixture()
        self.addCleanup(temporary.cleanup)

        validation = validate_model_directory(root)

        self.assertEqual(validation.model_type, "gpt_oss")
        self.assertEqual(validation.architecture, "GptOssForCausalLM")
        self.assertEqual(validation.shard_count, 3)
        self.assertEqual(validation.missing, ())
        self.assertTrue(validation.valid)

    def test_rejects_missing_and_zero_byte_shards(self) -> None:
        temporary, root = self.make_model_fixture()
        self.addCleanup(temporary.cleanup)
        (root / "model-00002-of-00003.safetensors").unlink()
        (root / "model-00003-of-00003.safetensors").write_bytes(b"")

        validation = validate_model_directory(root)

        self.assertIn("model-00002-of-00003.safetensors", validation.missing)
        self.assertIn("zero_byte:model-00003-of-00003.safetensors", validation.errors)
        self.assertFalse(validation.valid)

    def test_rejects_wrong_architecture_and_model_type(self) -> None:
        temporary, root = self.make_model_fixture()
        self.addCleanup(temporary.cleanup)
        (root / "config.json").write_text(
            json.dumps({"model_type": "qwen", "architectures": ["WrongModel"]}),
            encoding="utf-8",
        )

        validation = validate_model_directory(root)

        self.assertIn("unsupported_model_type:qwen", validation.errors)
        self.assertIn("unsupported_architecture:WrongModel", validation.errors)

    def test_rejects_invalid_root_and_malformed_index(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            invalid_file = root / "not-a-directory"
            invalid_file.write_text("x", encoding="utf-8")
            self.assertFalse(validate_model_directory(invalid_file).valid)

            model_root = root / "model"
            model_root.mkdir()
            (model_root / "model.safetensors.index.json").write_text(
                "{", encoding="utf-8"
            )
            validation = validate_model_directory(model_root)
            self.assertIn("invalid_json:model.safetensors.index.json", validation.errors)

    def test_rejects_index_reference_to_undeclared_shard(self) -> None:
        temporary, root = self.make_model_fixture()
        self.addCleanup(temporary.cleanup)
        index_path = root / "model.safetensors.index.json"
        index = json.loads(index_path.read_text(encoding="utf-8"))
        index["weight_map"]["layer.extra"] = "model-00004-of-00004.safetensors"
        index_path.write_text(json.dumps(index), encoding="utf-8")

        validation = validate_model_directory(root)

        self.assertIn("model-00004-of-00004.safetensors", validation.missing)
        self.assertFalse(validation.valid)


class HarmonyParserTests(unittest.TestCase):
    ids = HarmonyTokenIDs(
        channel=10,
        message=11,
        end=12,
        return_token=13,
        analysis=(20,),
        final=(21,),
    )

    @staticmethod
    def decode(values: list[int]) -> str:
        return "".join({100: "你", 101: "好", 102: "！"}.get(value, "") for value in values)

    def test_extracts_only_final_without_decoding_analysis(self) -> None:
        decoded_inputs: list[list[int]] = []

        def recording_decode(values: list[int]) -> str:
            decoded_inputs.append(values)
            return self.decode(values)

        result = extract_harmony_final(
            [10, 20, 11, 90, 91, 12, 10, 21, 11, 100, 101, 13],
            self.ids,
            recording_decode,
        )

        self.assertEqual(result, "你好")
        self.assertEqual(decoded_inputs, [[100, 101]])

    def test_rejects_absent_empty_or_analysis_only_final(self) -> None:
        invalid_sequences = (
            [10, 20, 11, 90, 12],
            [10, 21, 11, 13],
            [10, 20, 11, 90, 13],
        )
        for sequence in invalid_sequences:
            with self.subTest(sequence=sequence):
                with self.assertRaises(HarmonyStructureError):
                    extract_harmony_final(sequence, self.ids, self.decode)

    def test_rejects_control_token_inside_final(self) -> None:
        with self.assertRaisesRegex(HarmonyStructureError, "control_token_in_final"):
            extract_harmony_final(
                [10, 21, 11, 100, 10, 101, 13], self.ids, self.decode
            )

    def test_rejects_multiple_final_channels(self) -> None:
        with self.assertRaisesRegex(HarmonyStructureError, "multiple_final_channels"):
            extract_harmony_final(
                [10, 21, 11, 100, 12, 10, 21, 11, 101, 13],
                self.ids,
                self.decode,
            )

    def test_error_never_contains_decoded_analysis(self) -> None:
        secret = "PRIVATE_ANALYSIS_TEXT"
        with self.assertRaises(HarmonyStructureError) as context:
            extract_harmony_final(
                [10, 20, 11, 90, 91, 13],
                self.ids,
                lambda _: secret,
            )
        self.assertNotIn(secret, str(context.exception))


class CaseEvaluationTests(unittest.TestCase):
    def test_reports_required_forbidden_length_and_empty_failures(self) -> None:
        case = {
            "must_contain": ["TypeWhale", "MLX"],
            "must_not_contain": ["Ollama"],
            "max_output_chars": 20,
        }

        failures = evaluate_case(case, "TypeWhale uses Ollama and is too long")

        self.assertIn("missing:MLX", failures)
        self.assertIn("forbidden:Ollama", failures)
        self.assertTrue(any(item.startswith("too_long:") for item in failures))
        self.assertIn("empty", evaluate_case({}, "   "))

    def test_accepts_one_controlled_equivalent_from_each_required_group(self) -> None:
        case = {
            "must_contain_any": [
                ["不要回答", "不回答"],
                ["本地", "离线"],
            ]
        }

        self.assertEqual(evaluate_case(case, "保持本地运行，不回答原文问题。"), [])
        self.assertIn(
            "missing_any:不要回答|不回答",
            evaluate_case(case, "保持本地运行。"),
        )


class FixtureContractTests(unittest.TestCase):
    def test_synthetic_fixture_covers_required_categories(self) -> None:
        fixture_path = Path(__file__).with_name("gpt_oss_cases.json")
        cases = json.loads(fixture_path.read_text(encoding="utf-8"))
        required_categories = {
            "short_chat",
            "development_request",
            "no_answer",
            "short_instruction",
            "zh_to_en",
            "en_to_zh",
            "technical_terms",
        }

        self.assertIsInstance(cases, list)
        self.assertTrue(required_categories.issubset({case["category"] for case in cases}))
        self.assertEqual(len({case["id"] for case in cases}), len(cases))
        self.assertTrue(all(case["text"].strip() for case in cases))
        self.assertTrue(all(0 < int(case["max_tokens"]) <= 256 for case in cases))

    def test_synthetic_fixture_contains_no_obvious_private_identifiers(self) -> None:
        fixture_path = Path(__file__).with_name("gpt_oss_cases.json")
        fixture_text = fixture_path.read_text(encoding="utf-8")

        self.assertNotRegex(fixture_text, r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}")
        self.assertNotRegex(fixture_text, r"\b1[3-9]\d{9}\b")
        self.assertNotIn("/Users/", fixture_text)


class WorkerContractTests(unittest.TestCase):
    @staticmethod
    def load_worker_module():
        worker_path = Path(__file__).with_name("gpt_oss_worker.py")
        spec = importlib.util.spec_from_file_location("gpt_oss_worker_under_test", worker_path)
        if spec is None or spec.loader is None:
            raise AssertionError("worker_import_spec_unavailable")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_rewrite_messages_forbid_answering_and_expansion(self) -> None:
        worker = self.load_worker_module()

        messages = worker.build_messages("rewrite", "帮我回复用户")

        self.assertEqual(messages[-1], {"role": "user", "content": "帮我回复用户"})
        instruction = messages[0]["content"]
        self.assertIn("只整理", instruction)
        self.assertIn("不要回答", instruction)
        self.assertIn("不要扩写", instruction)
        self.assertIn("最少修改不等于原样照搬", instruction)
        self.assertIn("连续重复的同一个词只保留一次", instruction)
        self.assertIn("hello hello → hello", instruction)
        self.assertIn("然然后 → 然后", instruction)
        self.assertIn("无意义填充词", instruction)
        self.assertIn("判断不准时保留原文", instruction)
        self.assertIn("只输出整理后的文本", instruction)

    def test_translation_messages_only_translate_to_requested_language(self) -> None:
        worker = self.load_worker_module()

        messages = worker.build_messages(
            "translate", "Keep TypeWhale offline.", target_language="简体中文"
        )

        instruction = messages[0]["content"]
        self.assertIn("简体中文", instruction)
        self.assertIn("只翻译", instruction)
        self.assertIn("不要回答", instruction)
        self.assertIn("不要解释", instruction)

    def test_sanitized_error_never_contains_exception_message(self) -> None:
        worker = self.load_worker_module()
        error = worker.sanitized_error(RuntimeError("PRIVATE_ANALYSIS_TEXT"))

        self.assertEqual(error["error_type"], "RuntimeError")
        self.assertTrue(re.fullmatch(r"[a-z0-9_]+", error["error_code"]))
        self.assertNotIn("PRIVATE_ANALYSIS_TEXT", json.dumps(error))


class ControllerContractTests(unittest.TestCase):
    @staticmethod
    def load_controller_module():
        controller_path = Path(__file__).with_name("run_gpt_oss_admission.py")
        spec = importlib.util.spec_from_file_location(
            "gpt_oss_controller_under_test", controller_path
        )
        if spec is None or spec.loader is None:
            raise AssertionError("controller_import_spec_unavailable")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def make_fake_worker(self, root: Path) -> Path:
        worker = root / "fake_worker.py"
        worker.write_text(
            textwrap.dedent(
                """
                import json
                import os
                import sys
                import time

                def emit(value):
                    print(json.dumps(value), flush=True)

                emit({
                    "type": "ready",
                    "status": "ok",
                    "worker_pid": os.getpid(),
                    "offline": {
                        key: os.environ.get(key)
                        for key in (
                            "HF_HUB_OFFLINE",
                            "TRANSFORMERS_OFFLINE",
                            "HF_DATASETS_OFFLINE",
                            "PYTHONNOUSERSITE",
                        )
                    },
                })
                for line in sys.stdin:
                    command = json.loads(line)
                    if command["type"] == "shutdown":
                        emit({"type": "shutdown", "status": "ok"})
                        raise SystemExit(0)
                    if command.get("text") == "sleep":
                        time.sleep(5)
                    emit({
                        "type": "result",
                        "status": "ok",
                        "request_id": command["request_id"],
                        "final": command.get("text", ""),
                        "worker_pid": os.getpid(),
                    })
                """
            ).strip()
            + "\n",
            encoding="utf-8",
        )
        return worker

    def test_offline_environment_overrides_network_fallbacks(self) -> None:
        controller = self.load_controller_module()

        environment = controller.offline_environment({"HF_HUB_OFFLINE": "0"})

        self.assertEqual(environment["HF_HUB_OFFLINE"], "1")
        self.assertEqual(environment["TRANSFORMERS_OFFLINE"], "1")
        self.assertEqual(environment["HF_DATASETS_OFFLINE"], "1")
        self.assertEqual(environment["PYTHONNOUSERSITE"], "1")

    def test_rejects_relative_model_path(self) -> None:
        controller = self.load_controller_module()

        with self.assertRaisesRegex(ValueError, "model_path_must_be_absolute"):
            controller.require_absolute_model_directory(Path("relative/model"))

    def test_accepts_three_sequential_results_from_one_worker(self) -> None:
        controller = self.load_controller_module()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            worker_path = self.make_fake_worker(root)
            model_dir = root / "model"
            model_dir.mkdir()
            client = controller.WorkerClient(
                python_path=Path("/usr/bin/python3"),
                worker_path=worker_path,
                model_dir=model_dir,
                environment=controller.offline_environment(os.environ),
            )
            self.addCleanup(client.terminate)

            ready = client.start(timeout_seconds=2)
            results = [
                client.request(
                    {
                        "type": "generate",
                        "request_id": f"request-{index}",
                        "text": f"value-{index}",
                    },
                    timeout_seconds=2,
                )
                for index in range(3)
            ]
            client.shutdown(timeout_seconds=2)

        self.assertEqual({result["worker_pid"] for result in results}, {ready["worker_pid"]})

    def test_timeout_terminates_only_owned_worker(self) -> None:
        controller = self.load_controller_module()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            worker_path = self.make_fake_worker(root)
            model_dir = root / "model"
            model_dir.mkdir()
            client = controller.WorkerClient(
                python_path=Path("/usr/bin/python3"),
                worker_path=worker_path,
                model_dir=model_dir,
                environment=controller.offline_environment(os.environ),
            )
            client.start(timeout_seconds=2)

            with self.assertRaises(controller.WorkerTimeoutError):
                client.request(
                    {
                        "type": "generate",
                        "request_id": "blocked",
                        "text": "sleep",
                    },
                    timeout_seconds=0.1,
                )
            client.terminate()

            self.assertIsNotNone(client.process)
            self.assertIsNotNone(client.process.poll())

    def test_evidence_rejects_private_generation_fields(self) -> None:
        controller = self.load_controller_module()

        for key in ("analysis", "thinking", "raw_tokens", "raw_output"):
            with self.subTest(key=key):
                with self.assertRaisesRegex(ValueError, "forbidden_evidence_key"):
                    controller.assert_safe_evidence({"nested": {key: "secret"}})

    def test_decision_rejects_failed_semantic_case(self) -> None:
        controller = self.load_controller_module()
        evidence = {
            "model_validation": {"valid": True},
            "cold_start": {"status": "ok"},
            "case_results": [{"status": "ok", "failures": ["missing:constraint"]}],
            "warm_continuity": {"status": "ok", "count": 3},
            "cancellation": {"status": "ok"},
            "recovery": {"status": "ok"},
            "apfs_clone": {"status": "ok"},
        }

        self.assertEqual(controller.admission_decision(evidence), "REJECT")


if __name__ == "__main__":
    unittest.main()
