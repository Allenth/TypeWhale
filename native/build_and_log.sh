#!/bin/zsh
# TypeWhale 固定构建动作：构建 → 覆盖安装本地 → 打开 → 写构建日志，按节奏打大包。
#
# 用法：
#   ./native/build_and_log.sh            # 源码有变更才构建；每第 N 次自动打大包(DMG)
#   ./native/build_and_log.sh --package  # 强制构建并立即打大包，忽略变更检测与计数节奏
#   ./native/build_and_log.sh --auto     # Stop hook 兜底用：无 native 源码变更则静默跳过
#
# 设计：
# - 变更检测：对 native/ 下的 .swift/.c/.h 内容做哈希，与上次成功构建的哈希比对；
#   --auto 模式下无变更则直接跳过，避免每轮对话结束都空跑一次构建。
# - 主路径（我在对话里手动跑）会更新哈希；之后 Stop hook 再触发时哈希一致 → 秒跳过，不重复构建。
# - 打大包节奏：每累计 N 次（默认 4）本地构建，或显式 --package，生成 dist/ 下 DMG。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT/native/build_native_app.sh"
RELEASE_SCRIPT="$ROOT/native/release_local_build.sh"
PACKAGE_SCRIPT="$ROOT/native/package_dmg.sh"
BUILD_LOG="$ROOT/docs/构建日志.md"
STATE_DIR="$ROOT/.runtime"
STATE_FILE="$STATE_DIR/build_state"
PACKAGE_EVERY="${TYPEWHALE_PACKAGE_EVERY:-4}"

mode_auto=0
force_package=0
for arg in "$@"; do
  case "$arg" in
    --auto) mode_auto=1 ;;
    --package) force_package=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
[[ "${TYPEWHALE_FORCE_PACKAGE:-0}" == "1" ]] && force_package=1

mkdir -p "$STATE_DIR"

source_hash() {
  find "$ROOT/native" -type f \( -name '*.swift' -o -name '*.c' -o -name '*.h' \) \
    -not -path '*/.*' -print0 \
    | sort -z \
    | xargs -0 shasum 2>/dev/null \
    | shasum | awk '{print $1}'
}

current_hash="$(source_hash)"
last_hash=""
build_count=0
if [[ -f "$STATE_FILE" ]]; then
  last_hash="$(awk -F= '/^hash=/{print $2}' "$STATE_FILE" 2>/dev/null || true)"
  build_count="$(awk -F= '/^count=/{print $2}' "$STATE_FILE" 2>/dev/null || true)"
  [[ "$build_count" =~ ^[0-9]+$ ]] || build_count=0
fi

# Stop hook 兜底：无源码变更且未强制打包 → 静默跳过，不构建。
if [[ "$mode_auto" == "1" && "$force_package" == "0" && "$current_hash" == "$last_hash" ]]; then
  exit 0
fi

# 互斥锁：防止 Stop hook 触发的构建与手动构建并发，导致 .LaunchProbe.o / App 包写入竞态。
LOCK_DIR="$STATE_DIR/build.lock"
# 清理超过 30 分钟的陈旧锁（上次构建异常退出残留）。
if [[ -d "$LOCK_DIR" ]] && [[ -z "$(find "$LOCK_DIR" -prune -mmin -30 2>/dev/null)" ]]; then
  rmdir "$LOCK_DIR" 2>/dev/null || true
fi
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "==> 已有构建在进行中，跳过本次（由正在运行的构建产出最新安装版）。" >&2
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

echo "==> TypeWhale build_and_log: 构建并覆盖安装本地…"
"$RELEASE_SCRIPT"

# 读取本次构建后的版本号 / build 号
ver="$(perl -ne 'print "$1" if m{<key>CFBundleShortVersionString</key><string>([^<]+)}' "$BUILD_SCRIPT" | head -1)"
bld="$(perl -ne 'print "$1" if m{<key>CFBundleVersion</key><string>([^<]+)}' "$BUILD_SCRIPT" | head -1)"

build_count=$((build_count + 1))
ts="$(date '+%Y-%m-%d %H:%M:%S')"
branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo '-')"
dirty=""
git -C "$ROOT" diff --quiet 2>/dev/null || dirty="+dirty"

# 决定本次是否打大包
do_package=0
if [[ "$force_package" == "1" ]]; then
  do_package=1
elif (( build_count % PACKAGE_EVERY == 0 )); then
  do_package=1
fi

action="覆盖安装+打开"
dmg_note=""
if [[ "$do_package" == "1" ]]; then
  echo "==> 触发打大包（第 $build_count 次 / 每 $PACKAGE_EVERY 次）…"
  dmg_path="$("$PACKAGE_SCRIPT")"
  action="覆盖安装+打开+打大包"
  dmg_note=" · 包：\`$(basename "$dmg_path")\`"
fi

# 写构建日志（追加表格行）
if [[ ! -f "$BUILD_LOG" ]]; then
  {
    echo "# TypeWhale 构建日志"
    echo ""
    echo "本文件由 \`native/build_and_log.sh\` 自动追加，记录每次本地构建/覆盖安装/打大包动作。"
    echo "叙事性的需求与实现说明仍写入 \`docs/开发日志.md\`。"
    echo ""
    echo "| 时间 | 版本(build) | 分支@提交 | 动作 | 累计 |"
    echo "| --- | --- | --- | --- | --- |"
  } > "$BUILD_LOG"
fi
echo "| $ts | $ver ($bld) | $branch@$sha$dirty | $action$dmg_note | #$build_count |" >> "$BUILD_LOG"

# 保存状态
{
  echo "hash=$current_hash"
  echo "count=$build_count"
} > "$STATE_FILE"

echo "==> 完成：$ver ($bld) · $action · 累计 #$build_count"
if [[ "$do_package" == "1" ]]; then
  echo "==> 已打大包（第 $build_count 次节奏）：请同步更新 docs/开发日志.md 与应用内版本历史。"
fi
