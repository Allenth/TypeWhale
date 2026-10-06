#!/usr/bin/env python3
import ast
from pathlib import Path


root = Path(__file__).resolve().parents[1]
source = (root / "Scripts/tts_runtime_bootstrap.py").read_text()
tree = ast.parse(source)
assert "--system-site-packages" not in source
assert "voxcpm==2.0.3" in source
assert "074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc" in source
assert "offlineAfterInstall" in source
assert any(isinstance(node, ast.FunctionDef) and node.name == "main" for node in tree.body)
print("test_tts_runtime_bootstrap passed")
