#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

RESOURCE="$ROOT/native/Resources/Launch/TypeWhaleInkWhaleAlpha.mov"
PRESENTER="$ROOT/native/Sources/Presentation/Launch/LaunchAnimationPresenter.swift"
STORE="$ROOT/native/Sources/Infrastructure/Settings/LaunchAnimationPlaybackStore.swift"
MAIN="$ROOT/native/TypeSpeakerApp.swift"
MAIN_VIEW="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
PANEL="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
BUILD="$ROOT/native/build_native_app.sh"

if [[ ! -f "$RESOURCE" ]]; then
  echo "Missing launch animation resource: $RESOURCE" >&2
  exit 1
fi

if [[ ! -f "$PRESENTER" ]]; then
  echo "Missing launch animation presenter: $PRESENTER" >&2
  exit 1
fi

if [[ ! -f "$STORE" ]]; then
  echo "Missing launch animation playback store: $STORE" >&2
  exit 1
fi

if ! grep -q "typewhale.launchAnimation.hasPlayed.v1" "$STORE"; then
  echo "Launch animation must persist a first-play UserDefaults key." >&2
  exit 1
fi

if ! grep -q "LaunchAnimationPresenter.shared.playIfNeeded()" "$MAIN"; then
  echo "App launch must trigger the first-run launch animation." >&2
  exit 1
fi

if ! grep -q "let replayLaunchAnimationButton" "$MAIN_VIEW"; then
  echo "Main settings view must own a replay button." >&2
  exit 1
fi

if ! grep -q "重播启动动画" "$MAIN_VIEW"; then
  echo "Replay launch animation button must use the visible title." >&2
  exit 1
fi

if ! grep -q "replayLaunchAnimationButton" "$PANEL"; then
  echo "Settings panel must expose the replay launch animation button." >&2
  exit 1
fi

if ! grep -q "LaunchAnimationPresenter.shared.replayFromSettings()" "$ACTIONS"; then
  echo "Replay button must call the launch animation presenter." >&2
  exit 1
fi

if ! grep -q "native/Resources" "$BUILD" || ! grep -q "Contents/Resources" "$BUILD"; then
  echo "Build script must copy native resources into the app bundle." >&2
  exit 1
fi

if ! grep -q -- "-framework AVFoundation" "$BUILD"; then
  echo "Build script must link AVFoundation for video playback." >&2
  exit 1
fi
