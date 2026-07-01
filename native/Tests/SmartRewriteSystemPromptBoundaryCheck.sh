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

# Ollama 的整理提示词是小模型定制正文，不走共享 rewriteSystemPrompt，但必须复用
# 共享 languageLock，否则翻译防注入行会像历史上那样只在本地引擎悄悄漂移。
OLLAMA_ENGINE="$ROOT/native/Sources/Infrastructure/SmartRewrite/OllamaRewriteEngine.swift"
grep -Fq "SmartRewriteSafetyPrompt.languageLock" "$OLLAMA_ENGINE" || {
  echo "Ollama engine must reuse shared languageLock: $OLLAMA_ENGINE" >&2
  exit 1
}

echo "SmartRewriteSystemPromptBoundaryCheck passed"
