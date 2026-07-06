#!/bin/zsh
set -euo pipefail

next_full_version() {
  local version="$1"
  if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Unexpected version format: $version" >&2
    return 1
  fi

  local major="${match[1]}"
  local minor="${match[2]}"
  local patch="${match[3]}"
  local patch_number=$((10#$patch))

  patch_number=$((patch_number + 1))

  echo "$major.$minor.$patch_number"
}

assert_next() {
  local from="$1"
  local expected="$2"
  local actual
  actual="$(next_full_version "$from")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $from -> $expected, got $actual" >&2
    exit 1
  fi
}

assert_next "1.6.8" "1.6.9"
assert_next "1.6.9" "1.6.10"
assert_next "1.7.0" "1.7.1"
assert_next "1.7.8" "1.7.9"
assert_next "1.7.9" "1.7.10"
assert_next "1.7.10" "1.7.11"
assert_next "1.9.9" "1.9.10"

echo "ReleaseVersionRuleCheck passed"
