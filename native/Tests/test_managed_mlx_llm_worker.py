import importlib.util
from pathlib import Path
import sys
import unittest


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


class FakeTokenizer:
    def __init__(self, decoded):
        self.decoded = decoded
        self.calls = []

    def decode(self, token_ids, *, skip_special_tokens):
        self.calls.append((token_ids, skip_special_tokens))
        return self.decoded


class FakeCache:
    def __init__(self, values):
        self.values = list(values)


class UncopyableCache:
    def __deepcopy__(self, _memo):
        raise RuntimeError("copy_failed")


def fake_can_trim(caches):
    return all(isinstance(cache, FakeCache) for cache in caches)


def fake_trim(caches, count):
    for cache in caches:
        del cache.values[-count:]


class ManagedMLXLLMWorkerCheck(unittest.TestCase):
    def test_decode_generated_text_strips_and_skips_special_tokens(self):
        tokenizer = FakeTokenizer("  整理后的正文  ")

        result = worker.decode_generated_text(tokenizer, [10, 11, 12])

        self.assertEqual(result, "整理后的正文")
        self.assertEqual(tokenizer.calls, [([10, 11, 12], True)])

    def test_decode_generated_text_rejects_empty_output(self):
        tokenizer = FakeTokenizer("  \n ")

        with self.assertRaisesRegex(worker.WorkerRequestError, "empty_final_text"):
            worker.decode_generated_text(tokenizer, [10])

    def test_worker_has_no_gpt_oss_harmony_or_reasoning_template_arguments(self):
        source = WORKER_PATH.read_text(encoding="utf-8")

        self.assertNotIn("HarmonyTokenIDs", source)
        self.assertNotIn("extract_harmony_final", source)
        self.assertNotIn("reasoning_effort=", source)
        self.assertIn("add_generation_prompt=True", source)

    def test_shorter_cached_prefix_is_cloned_and_reused(self):
        cache = worker.PromptPrefixCache(max_size=2)
        original = [FakeCache([1, 2, 3])]
        cache.insert("model-a", [10, 11, 12], original)

        match = cache.fetch(
            "model-a",
            [10, 11, 12, 13, 14],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertEqual(match.reused_tokens, 3)
        self.assertEqual(match.remaining_tokens, [13, 14])
        self.assertIsNot(match.cache, original)
        match.cache[0].values.append(99)
        self.assertEqual(original[0].values, [1, 2, 3])

    def test_longer_cached_sequence_trims_to_safe_common_prefix(self):
        cache = worker.PromptPrefixCache(max_size=2)
        cache.insert(
            "model-a",
            [10, 11, 12, 20],
            [FakeCache([10, 11, 12, 20])],
        )

        match = cache.fetch(
            "model-a",
            [10, 11, 12, 30],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertEqual(match.reused_tokens, 3)
        self.assertEqual(match.remaining_tokens, [30])
        self.assertEqual(match.cache[0].values, [10, 11, 12])

    def test_model_mismatch_and_clear_are_misses(self):
        cache = worker.PromptPrefixCache(max_size=2)
        cache.insert("model-a", [1, 2], [FakeCache([1, 2])])

        mismatch = cache.fetch(
            "model-b",
            [1, 2, 3],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )
        self.assertEqual(mismatch.reused_tokens, 0)

        cache.clear()
        cleared = cache.fetch(
            "model-a",
            [1, 2, 3],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )
        self.assertEqual(cleared.reused_tokens, 0)

    def test_untrimmable_longer_cache_falls_back_to_miss(self):
        cache = worker.PromptPrefixCache(max_size=2)
        cache.insert("model-a", [1, 2, 3], [FakeCache([1, 2, 3])])

        match = cache.fetch(
            "model-a",
            [1, 9],
            can_trim=lambda _: False,
            trim=fake_trim,
        )

        self.assertEqual(match.reused_tokens, 0)
        self.assertEqual(match.remaining_tokens, [1, 9])
        self.assertIsNone(match.cache)

    def test_exact_cached_prompt_retains_one_token_for_generation(self):
        cache = worker.PromptPrefixCache(max_size=2)
        cache.insert("model-a", [1, 2, 3], [FakeCache([1, 2, 3])])

        match = cache.fetch(
            "model-a",
            [1, 2, 3],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertEqual(match.reused_tokens, 2)
        self.assertEqual(match.remaining_tokens, [3])
        self.assertEqual(match.cache[0].values, [1, 2])

    def test_clone_failure_falls_back_to_miss(self):
        cache = worker.PromptPrefixCache(max_size=2)
        cache.insert("model-a", [1, 2], [UncopyableCache()])

        match = cache.fetch(
            "model-a",
            [1, 2, 3],
            can_trim=lambda _: True,
            trim=lambda _cache, _count: None,
        )

        self.assertEqual(match.reused_tokens, 0)
        self.assertEqual(match.remaining_tokens, [1, 2, 3])
        self.assertIsNone(match.cache)

    def test_token_budget_evicts_least_recent_entry(self):
        cache = worker.PromptPrefixCache(max_size=3, max_total_tokens=5)
        cache.insert("model-a", [1, 2, 3], [FakeCache([1, 2, 3])])
        cache.insert("model-a", [4, 5], [FakeCache([4, 5])])
        cache.fetch(
            "model-a",
            [1, 2, 3, 9],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )
        cache.insert("model-a", [6, 7], [FakeCache([6, 7])])

        evicted = cache.fetch(
            "model-a",
            [4, 5, 9],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )
        retained = cache.fetch(
            "model-a",
            [1, 2, 3, 9],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertEqual(evicted.reused_tokens, 0)
        self.assertEqual(retained.reused_tokens, 3)

    def test_byte_budget_evicts_least_recent_entry(self):
        cache = worker.PromptPrefixCache(
            max_size=3,
            max_total_tokens=10,
            max_total_bytes=5,
        )
        cache.insert(
            "model-a",
            [1, 2],
            [FakeCache([1, 2])],
            cache_bytes=3,
        )
        cache.insert(
            "model-a",
            [3, 4],
            [FakeCache([3, 4])],
            cache_bytes=2,
        )
        cache.fetch(
            "model-a",
            [1, 2, 9],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )
        cache.insert(
            "model-a",
            [5, 6],
            [FakeCache([5, 6])],
            cache_bytes=2,
        )

        evicted = cache.fetch(
            "model-a",
            [3, 4, 9],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )
        retained = cache.fetch(
            "model-a",
            [1, 2, 9],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertEqual(evicted.reused_tokens, 0)
        self.assertEqual(retained.reused_tokens, 2)

    def test_prepare_generation_cache_uses_remainder_on_hit(self):
        state = worker.WorkerState()
        state.model = object()
        state.model_directory = "/model"
        state.prompt_prefix_cache.insert(
            "/model",
            [1, 2, 3],
            [FakeCache([1, 2, 3])],
        )

        prepared = state._prepare_generation_cache(
            prompt_tokens=[1, 2, 3, 4],
            make_cache=lambda _: [FakeCache([])],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertTrue(prepared.hit)
        self.assertEqual(prepared.input_tokens, [4])
        self.assertEqual(prepared.reused_tokens, 3)
        self.assertEqual(prepared.cache[0].values, [1, 2, 3])

    def test_prepare_generation_cache_creates_empty_cache_on_miss(self):
        state = worker.WorkerState()
        state.model = object()

        prepared = state._prepare_generation_cache(
            prompt_tokens=[7, 8],
            make_cache=lambda _: [FakeCache([])],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertFalse(prepared.hit)
        self.assertEqual(prepared.input_tokens, [7, 8])
        self.assertEqual(prepared.reused_tokens, 0)
        self.assertEqual(prepared.cache[0].values, [])

    def test_metrics_report_cache_hit_and_evaluated_tokens(self):
        state = worker.WorkerState()

        miss = state._metrics(
            prompt_tokens=20,
            prompt_cache_hit=False,
            prompt_cache_reused_tokens=0,
            prompt_tokens_evaluated=20,
        )
        hit = state._metrics(
            prompt_tokens=20,
            prompt_cache_hit=True,
            prompt_cache_reused_tokens=15,
            prompt_tokens_evaluated=5,
        )

        self.assertFalse(miss["prompt_cache_hit"])
        self.assertEqual(miss["prompt_cache_reused_tokens"], 0)
        self.assertEqual(miss["prompt_tokens_evaluated"], 20)
        self.assertTrue(hit["prompt_cache_hit"])
        self.assertEqual(hit["prompt_cache_reused_tokens"], 15)
        self.assertEqual(hit["prompt_tokens_evaluated"], 5)

    def test_cached_generation_failure_retries_full_prompt_once(self):
        state = worker.WorkerState()
        state.model = object()
        state.model_directory = "/model"
        state.prompt_prefix_cache.insert(
            "/model",
            [1, 2, 3],
            [FakeCache([1, 2, 3])],
        )
        attempts = []

        def run(prepared):
            attempts.append(prepared.hit)
            if prepared.hit:
                raise RuntimeError("cached_generation_failed")
            return "fallback-result"

        prepared, result = state._run_with_cache_fallback(
            prompt_tokens=[1, 2, 3, 4],
            make_cache=lambda _: [FakeCache([])],
            can_trim=fake_can_trim,
            trim=fake_trim,
            run=run,
        )

        self.assertEqual(attempts, [True, False])
        self.assertFalse(prepared.hit)
        self.assertEqual(prepared.input_tokens, [1, 2, 3, 4])
        self.assertEqual(result, "fallback-result")

    def test_stored_cache_trims_generated_tokens_and_keeps_prompt_only(self):
        state = worker.WorkerState()
        state.model_directory = "/model"
        generated_cache = [FakeCache([1, 2, 3, 20, 21])]

        stored = state._store_prompt_cache(
            prompt_tokens=[1, 2, 3],
            generated_token_count=2,
            prompt_cache=generated_cache,
            can_trim=fake_can_trim,
            trim=fake_trim,
        )
        match = state.prompt_prefix_cache.fetch(
            "/model",
            [1, 2, 3, 4],
            can_trim=fake_can_trim,
            trim=fake_trim,
        )

        self.assertTrue(stored)
        self.assertEqual(generated_cache[0].values, [1, 2, 3])
        self.assertEqual(match.reused_tokens, 3)


if __name__ == "__main__":
    unittest.main()
