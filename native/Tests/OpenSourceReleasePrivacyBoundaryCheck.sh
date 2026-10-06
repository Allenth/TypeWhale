#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETTINGS="$ROOT/native/Sources/Infrastructure/Settings/AppSettings.swift"
VSCODE_SETTINGS="$ROOT/.vscode/settings.json"
AGENT_RULES="$ROOT/AGENTS.md"

if grep -Fq 'URL(fileURLWithPath: "/Users/' "$SETTINGS"; then
  echo "Production defaults must not contain a developer-specific macOS home path." >&2
  exit 1
fi

grep -Fq 'FileManager.default.homeDirectoryForCurrentUser' "$SETTINGS" || {
  echo "The backlog default must derive from the current user's home directory." >&2
  exit 1
}

grep -Fq 'appendingPathComponent("Documents/TypeWhale/需求池", isDirectory: true)' "$SETTINGS" || {
  echo "The backlog default must use the user-neutral Documents/TypeWhale/需求池 location." >&2
  exit 1
}

grep -Fq '${workspaceFolder}/windows/native' "$VSCODE_SETTINGS" || {
  echo "VS Code CMake configuration must be workspace-relative." >&2
  exit 1
}

if grep -Fq '/Users/' "$VSCODE_SETTINGS" "$AGENT_RULES"; then
  echo "Repository configuration and collaboration rules must not expose a local user home path." >&2
  exit 1
fi

if git -C "$ROOT" grep -n '/Users/' -- \
  ':!native/Tests/**' \
  ':!windows/**/Tests/**' \
  ':!tools/**/test_*'; then
  echo "Public source and documentation must not contain a developer-specific macOS home path." >&2
  exit 1
fi

echo "OpenSourceReleasePrivacyBoundaryCheck passed"
