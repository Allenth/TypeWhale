import importlib.util
from pathlib import Path
import sys
import unittest

try:
    import mlx.core as mx
    from mlx_lm.models.cache import KVCache
except ModuleNotFoundError:
    mx = None
    KVCache = None


WORKER_PATH = (
    Path(__file__).resolve().parents[1]
    / "Resources"
    / "managed_mlx_llm_worker.py"
)
SPEC = importlib.util.spec_from_file_location("managed_mlx_llm_worker", WORKER_PATH)
worker = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = worker
SPEC.loader.exec_module(worker)


@unittest.skipIf(mx is None or KVCache is None, "requires managed MLX runtime")
class ManagedMLXCacheCompactionCheck(unittest.TestCase):
    def test_compaction_materializes_trimmed_kv_backing_shape(self):
        cache = KVCache()
        keys = mx.zeros((1, 8, 2_048, 128), dtype=mx.float16)
        values = mx.zeros((1, 8, 2_048, 128), dtype=mx.float16)
        cache.update_and_fetch(keys, values)
        mx.eval(cache.keys, cache.values)
        backing_bytes = cache.keys.nbytes + cache.values.nbytes
        cache.trim(1_920)

        self.assertEqual(cache.offset, 128)
        self.assertEqual(cache.keys.shape[2], 2_048)

        retained_bytes = worker.compact_prompt_cache([cache])

        self.assertEqual(cache.offset, 128)
        self.assertEqual(cache.keys.shape[2], 128)
        self.assertEqual(cache.values.shape[2], 128)
        self.assertEqual(retained_bytes, cache.keys.nbytes + cache.values.nbytes)
        self.assertEqual(retained_bytes, backing_bytes // 16)


if __name__ == "__main__":
    unittest.main()
