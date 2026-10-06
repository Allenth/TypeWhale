#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE="$ROOT/native/SystemMediaRemoteBridge.m"
HEADER="$ROOT/native/SystemMediaRemoteBridge.h"
BUILD="$ROOT/native/build_native_app.sh"
UMBRELLA="$ROOT/native/TypeSpeakerNativeASR.h"

require_file() {
  local file="$1"
  local message="$2"
  if [[ ! -f "$file" ]]; then
    echo "$message" >&2
    exit 1
  fi
}

require_text() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! rg -Fq "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -Fq "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_minimum_count() {
  local file="$1"
  local pattern="$2"
  local minimum="$3"
  local message="$4"
  local count
  count="$(rg -Fo "$pattern" "$file" | wc -l | tr -d ' ')"
  if (( count < minimum )); then
    echo "$message" >&2
    exit 1
  fi
}

require_file "$HEADER" "System media bridge header is missing"
require_file "$BRIDGE" "System media bridge implementation is missing"
require_text "$BRIDGE" 'dlopen(' "MediaRemote must be loaded dynamically"
require_text "$BRIDGE" 'dlsym(' "MediaRemote symbols must be resolved dynamically"
require_text "$BRIDGE" 'MRMediaRemoteGetNowPlayingApplicationIsPlaying' \
  "Bridge must query the system now-playing state"
require_text "$BRIDGE" 'MRMediaRemoteGetNowPlayingApplicationPID' \
  "Bridge must query the system now-playing process identity"
require_minimum_count "$BRIDGE" 'getPID(' 2 \
  "Bridge must read PID before and after playback state"
require_text "$BRIDGE" 'dispatch_after(' \
  "Bridge must fail closed after a bounded timeout"
reject_text "$BRIDGE" 'MRMediaRemoteGetNowPlayingInfo' \
  "Bridge must not read now-playing metadata"
require_text "$BUILD" 'SystemMediaRemoteBridge.m' \
  "Native build must compile the media bridge"
require_text "$BUILD" 'MEDIA_REMOTE_BRIDGE_OBJECT' \
  "Native build must link a named media bridge object"
require_text "$UMBRELLA" '#include "SystemMediaRemoteBridge.h"' \
  "Swift bridging header must expose the media bridge"
require_text "$UMBRELLA" '#ifdef __OBJC__' \
  "Objective-C media bridge include must be hidden from pure C compilation"

if ! xcrun clang -x c -fsyntax-only -I "$ROOT/native" - 2>/dev/null <<'C_HEADER_CHECK'
#include "TypeSpeakerNativeASR.h"
C_HEADER_CHECK
then
  echo "TypeSpeakerNativeASR.h must remain valid when included from pure C" >&2
  exit 1
fi

echo "SystemMediaRemoteBridgeBoundaryCheck passed"
