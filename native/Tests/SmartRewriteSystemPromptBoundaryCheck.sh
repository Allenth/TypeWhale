#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if rg -n "除非用户明确要求翻译" "$ROOT/native/Sources/Infrastructure/SmartRewrite" >/tmp/typewhale-rewrite-translation-exception.txt; then
  cat /tmp/typewhale-rewrite-translation-exception.txt >&2
  echo "Smart rewrite system prompts must not allow translation exceptions." >&2
  exit 1
fi

SAFETY_PROMPT="$ROOT/native/Sources/Core/SmartInput/SmartRewriteSafetyPrompt.swift"

grep -Fq "不要真的改变输出语言" "$SAFETY_PROMPT" || {
  echo "Missing shared smart rewrite language-preservation boundary in $SAFETY_PROMPT" >&2
  exit 1
}

grep -Fq "不要生成最终回复话术" "$SAFETY_PROMPT" || {
  echo "Missing shared smart rewrite no-answer consultation boundary in $SAFETY_PROMPT" >&2
  exit 1
}

for file in \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/DeepSeekRewriteEngine.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/MiniMaxRewriteEngine.swift"; do
  grep -Fq "SmartRewriteSafetyPrompt.rewriteSystemPrompt" "$file" || {
    echo "Smart rewrite engine must use shared safety prompt: $file" >&2
    exit 1
  }
done

MANAGED_PREFILL="$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedLLMPrefill.swift"
LOCAL_ENGINE="$ROOT/native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift"

grep -Fq "SmartRewriteSafetyPrompt.rewriteSystemPrompt" "$MANAGED_PREFILL" || {
  echo "Managed local rewrite prefill must derive from the shared safety prompt." >&2
  exit 1
}

grep -Fq "systemPrompt: ManagedLLMPrefill.rewriteSystemPrompt" "$LOCAL_ENGINE" || {
  echo "Managed local rewrite engine must use the shared prefill system prompt." >&2
  exit 1
}

if rg -n "我的表达内容没有被准确理解和妥善处理" \
  "$ROOT/native/Sources/Core/SmartInput/SmartRewritePromptStore.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/DeepSeekRewriteEngine.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift"; then
  echo "Active rewrite prompts must not contain copyable natural-language output examples." >&2
  exit 1
fi

echo "SmartRewriteSystemPromptBoundaryCheck passed"
