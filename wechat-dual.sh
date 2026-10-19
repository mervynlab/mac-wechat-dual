#!/usr/bin/env bash
# mac-wechat-dual: 在 macOS 上为微信创建独立副本，实现双开/多开。
# 原理：复制 WeChat.app → 修改 Bundle ID（系统视为另一个 App，分配独立沙盒数据目录）→ 本地临时签名。
# 不修改原版 WeChat.app，不修改微信任何代码。
set -euo pipefail

VERSION="1.0.0"
SRC="${WECHAT_APP:-/Applications/WeChat.app}"
APP_DIR="${WECHAT_DUAL_DIR:-/Applications}"
BASE_ID="com.tencent.xinWeChat"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '==> %s\n' "$*"; }

usage() {
  cat <<EOF
mac-wechat-dual $VERSION — macOS 微信双开/多开工具

用法:
  $(basename "$0") install [N]           创建并启动第 N 个微信（默认 N=2，生成 WeChat2.app）
  $(basename "$0") open [N]              启动已创建的第 N 个微信
  $(basename "$0") list                  列出已创建的副本及版本
  $(basename "$0") remove N [--purge]    删除第 N 个副本；加 --purge 同时删除该账号的本地数据（不可恢复）
  $(basename "$0") help                  显示帮助

环境变量:
  WECHAT_APP        原版微信路径（默认 /Applications/WeChat.app）
  WECHAT_DUAL_DIR   副本存放目录（默认 /Applications）

微信更新后：退出副本，重新执行 install N 即可，聊天数据不会丢失。
EOF
}

check_n() {
  [[ "$1" =~ ^[2-9]$|^[1-9][0-9]+$ ]] || { red "N 必须是 >=2 的整数，收到: $1"; exit 1; }
}

dst_of() { echo "$APP_DIR/WeChat$1.app"; }
bid_of() { echo "$BASE_ID$1"; }

is_running() { pgrep -f "$1/Contents/MacOS/WeChat" >/dev/null 2>&1; }

cmd_install() {
  local n="${1:-2}"; check_n "$n"
  local dst bid; dst="$(dst_of "$n")"; bid="$(bid_of "$n")"

  [[ "$(uname)" == "Darwin" ]] || { red "仅支持 macOS"; exit 1; }
  [[ -d "$SRC" ]] || { red "找不到原版微信: $SRC"; exit 1; }
  [[ -w "$APP_DIR" ]] || { red "$APP_DIR 不可写。请用管理员账户运行，或设置 WECHAT_DUAL_DIR=~/Applications"; exit 1; }
  if is_running "$dst"; then red "WeChat$n 正在运行，请先退出（菜单栏 微信 → 退出）"; exit 1; fi

  local ver; ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist" 2>/dev/null || echo '?')"
  info "原版微信 $ver → $dst ($bid)"

  rm -rf "$dst"
  info "复制（APFS 克隆，几乎不占额外空间）"
  cp -Rc "$SRC" "$dst" 2>/dev/null || cp -R "$SRC" "$dst"

  info "修改 Bundle ID 与显示名"
  local plist="$dst/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bid" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName WeChat$n" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 微信$n" "$plist" 2>/dev/null || true

  info "移除与原版同 ID 的扩展（分享扩展 / 文件提供扩展），避免干扰原版"
  rm -rf "$dst/Contents/PlugIns"

  info "本地临时签名"
  codesign --force --deep --sign - "$dst" >/dev/null 2>&1
  xattr -dr com.apple.quarantine "$dst" 2>/dev/null || true
  codesign --verify --deep "$dst"

  green "完成：$dst"
  open "$dst"
}

cmd_open() {
  local n="${1:-2}"; check_n "$n"
  local dst; dst="$(dst_of "$n")"
  [[ -d "$dst" ]] || { red "未找到 $dst，请先执行 install $n"; exit 1; }
  open "$dst"
}

cmd_list() {
  local src_ver; src_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist" 2>/dev/null || echo '未安装')"
  echo "原版: $SRC  版本 $src_ver"
  local found=0 app
  for app in "$APP_DIR"/WeChat[0-9]*.app; do
    [[ -d "$app" ]] || continue
    found=1
    local v b s
    v="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo '?')"
    b="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || echo '?')"
    s=""; [[ "$v" != "$src_ver" ]] && s="  ← 版本落后，建议重新 install"
    echo "副本: $app  $b  版本 $v$s"
  done
  [[ $found -eq 1 ]] || echo "暂无副本"
}

cmd_remove() {
  local n="${1:-}"; [[ -n "$n" ]] || { red "用法: remove N [--purge]"; exit 1; }
  check_n "$n"
  local purge="${2:-}" dst bid; dst="$(dst_of "$n")"; bid="$(bid_of "$n")"
  if is_running "$dst"; then red "WeChat$n 正在运行，请先退出"; exit 1; fi
  if [[ -d "$dst" ]]; then rm -rf "$dst"; green "已删除 $dst"; else echo "$dst 不存在"; fi

  if [[ "$purge" == "--purge" ]]; then
    local data="$HOME/Library/Containers/$bid"
    if [[ -d "$data" ]]; then
      printf '将永久删除第 %s 个账号的本地聊天数据：%s\n输入 yes 确认: ' "$n" "$data"
      local ans; read -r ans
      if [[ "$ans" == "yes" ]]; then rm -rf "$data"; green "已删除数据目录"; else echo "已取消，数据保留"; fi
    else
      echo "未找到数据目录 $data"
    fi
  else
    echo "聊天数据保留在 ~/Library/Containers/$bid（如需删除：remove $n --purge）"
  fi
}

case "${1:-help}" in
  install) shift; cmd_install "$@" ;;
  open)    shift; cmd_open "$@" ;;
  list)    cmd_list ;;
  remove)  shift; cmd_remove "$@" ;;
  -v|--version|version) echo "$VERSION" ;;
  help|-h|--help) usage ;;
  *) red "未知命令: $1"; usage; exit 1 ;;
esac
