#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_AND_LOG="$ROOT/native/build_and_log.sh"
RELEASE="$ROOT/native/release_local_build.sh"

if ! grep -Fq -- '--install-only) mode="install-only"' "$RELEASE"; then
  echo 'BuildOnlyInstallPolicyCheck failed: release_local_build.sh must expose --install-only mode' >&2
  exit 1
fi

if ! grep -Fq -- '--build-only) mode="build-only"' "$RELEASE"; then
  echo 'BuildOnlyInstallPolicyCheck failed: release_local_build.sh must expose --build-only mode' >&2
  exit 1
fi

if ! grep -Fq 'release_mode="--build-only"' "$BUILD_AND_LOG"; then
  echo 'BuildOnlyInstallPolicyCheck failed: build_and_log.sh must compile and increment build by default' >&2
  exit 1
fi

if ! grep -Fq 'FULL_VERSION_EVERY="${TYPEWHALE_FULL_VERSION_EVERY:-0}"' "$BUILD_AND_LOG"; then
  echo 'BuildOnlyInstallPolicyCheck failed: ordinary build/install must not auto-compile by cumulative count' >&2
  exit 1
fi

/usr/bin/python3 - "$RELEASE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
required = [
    'next_build=$((current_build + 1))',
    'if [[ "$mode" == "build-only" ]]; then',
    'next_version="$current_version"',
    'Bumped TypeWhale Pro build to',
    '"$BUILD_SCRIPT"',
]
for item in required:
    if item not in source:
        raise SystemExit(f"BuildOnlyInstallPolicyCheck failed: build-only path missing {item}")
PY

for required in \
  'Existing app bundle version mismatch for install-only path.' \
  'source_version' \
  'source_build'; do
  if ! grep -Fq "$required" "$RELEASE"; then
    echo "BuildOnlyInstallPolicyCheck failed: install-only must verify existing app bundle version ($required missing)" >&2
    exit 1
  fi
done

if ! grep -Fq 'action="build-only构建+覆盖安装+打开"' "$BUILD_AND_LOG"; then
  echo 'BuildOnlyInstallPolicyCheck failed: build log action must record default build-only compilation' >&2
  exit 1
fi

echo 'BuildOnlyInstallPolicyCheck passed'
