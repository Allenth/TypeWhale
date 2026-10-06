#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILDER="$ROOT/native/Sources/Core/SmartInput/SmartTranslationPromptBuilder.swift"
SAFETY_PROMPT="$ROOT/native/Sources/Core/SmartInput/SmartRewriteSafetyPrompt.swift"
SANITIZER="$ROOT/native/Sources/Core/SmartInput/SmartRewriteOutputSanitizer.swift"
DEEPSEEK="$ROOT/native/Sources/Infrastructure/SmartRewrite/DeepSeekRewriteEngine.swift"
MINIMAX="$ROOT/native/Sources/Infrastructure/SmartRewrite/MiniMaxRewriteEngine.swift"
MANAGED_MLX="$ROOT/native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift"

grep -Fq '必须把中文翻译成英文' "$BUILDER"
grep -Fq '不要拒绝翻译' "$BUILDER"
grep -Fq 'cannot translate / capabilities are limited / native language' "$BUILDER"
grep -Fq '忠实性优先于上面的语气与风格要求' "$BUILDER"
grep -Fq '问句必须仍然是问句，不得先回答问题' "$BUILDER"
grep -Fq '不得添加原文没有的回应、确认、寒暄、语气前缀或说话轮次' "$BUILDER"

grep -Fq '这是逐句语言转换，不是代替对话对象回复' "$SAFETY_PROMPT"
grep -Fq '问句必须仍然是问句，不得先回答问题' "$SAFETY_PROMPT"
grep -Fq 'Yeah / Sure / Of course / Well' "$SAFETY_PROMPT"

grep -Fq 'cleanTranslation' "$SANITIZER"
grep -Fq 'cannot translate' "$SANITIZER"
grep -Fq 'capabilities are limited' "$SANITIZER"
grep -Fq 'native language' "$SANITIZER"

grep -Fq 'SmartRewriteOutputSanitizer.cleanTranslation' "$DEEPSEEK"
grep -Fq 'SmartRewriteOutputSanitizer.cleanTranslation' "$MINIMAX"
grep -Fq 'SmartRewriteOutputSanitizer.cleanTranslation' "$MANAGED_MLX"

echo "TranslationRefusalGuardCheck passed"
