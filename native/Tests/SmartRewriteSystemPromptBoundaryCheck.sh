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

for file in \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/DeepSeekRewriteEngine.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/MiniMaxRewriteEngine.swift"; do
  grep -Fq "SmartRewriteSafetyPrompt.rewriteSystemPrompt" "$file" || {
    echo "Smart rewrite engine must use shared safety prompt: $file" >&2
    exit 1
  }
done

echo "SmartRewriteSystemPromptBoundaryCheck passed"
