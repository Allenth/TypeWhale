from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("bootstrap_managed_gpt_oss.py")


def load_module():
    spec = importlib.util.spec_from_file_location("bootstrap_managed_gpt_oss", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class BootstrapManagedGPTOSSTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module()
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.source = self.root / "external-source"
        self.destination = self.root / "managed" / "fixture-model"
        self.source.mkdir()
        (self.source / "config.json").write_bytes(b"config")
        (self.source / "model.safetensors").write_bytes(b"weights")
        self.descriptor = self.module.ModelDescriptor(
            model_id="fixture-model",
            artifacts=(
                self.artifact("config.json"),
                self.artifact("model.safetensors"),
            ),
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def artifact(self, name: str):
        data = (self.source / name).read_bytes()
        return self.module.Artifact(
            name=name,
            expected_bytes=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
        )

    def metadata(self, root: Path):
        return {
            path.name: (
                path.stat().st_size,
                path.stat().st_mtime_ns,
                path.stat().st_mode,
            )
            for path in root.iterdir()
        }

    def test_rejects_missing_and_invalid_source(self) -> None:
        with self.assertRaises(self.module.BootstrapError):
            self.module.bootstrap(
                self.root / "missing",
                self.destination,
                self.descriptor,
            )
        (self.source / "config.json").write_bytes(b"wrong")
        with self.assertRaises(self.module.BootstrapError):
            self.module.bootstrap(
                self.source,
                self.destination,
                self.descriptor,
            )
        self.assertFalse(self.destination.exists())

    def test_clones_through_staging_without_exposing_source(self) -> None:
        before = self.metadata(self.source)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = self.module.bootstrap(
                self.source,
                self.destination,
                self.descriptor,
            )
        self.assertEqual(result.status, "ready")
        self.assertEqual(self.metadata(self.source), before)
        self.assertEqual(
            (self.destination / "model.safetensors").read_bytes(),
            b"weights",
        )
        payload = json.loads(output.getvalue())
        self.assertEqual(
            set(payload),
            {"status", "model_id", "bytes", "elapsed_ms"},
        )
        self.assertNotIn(str(self.source), output.getvalue())
        self.assertFalse(
            self.destination.parent.joinpath(".installing-fixture-model").exists()
        )

    def test_refuses_ready_destination_without_replace(self) -> None:
        self.module.bootstrap(self.source, self.destination, self.descriptor)
        with self.assertRaises(self.module.BootstrapError):
            self.module.bootstrap(
                self.source,
                self.destination,
                self.descriptor,
            )
        self.module.bootstrap(
            self.source,
            self.destination,
            self.descriptor,
            replace=True,
        )
        self.assertEqual(
            (self.destination / "config.json").read_bytes(),
            b"config",
        )


if __name__ == "__main__":
    unittest.main()
