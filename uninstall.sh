#!/usr/bin/env bash
# OpenCode Portable - uninstall (macOS/Linux).
#   --install-dir <p>   Installation folder.
#   --cache-dir <p>     Package cache folder.
#   --remove-path       Remove it from the PATH (edits the shell rc).
#   --purge             Remove the install folder (if empty) and the cache.
set -euo pipefail

APP="opencode"
TOOLKIT_NAME="opencode-ide-vscode-installer"
INSTALL_DIR="${HOME}/.opencode/bin"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/${TOOLKIT_NAME}"
REMOVE_PATH=false
PURGE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --install-dir) INSTALL_DIR="${2:?missing value}"; shift 2 ;;
    --cache-dir)   CACHE_DIR="${2:?missing value}"; shift 2 ;;
    --remove-path) REMOVE_PATH=true; shift ;;
    --purge)       PURGE=true; shift ;;
    -h|--help)     sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

removed=0
for f in "$APP" "${APP}.exe" "opencode2"; do
  if [ -e "$INSTALL_DIR/$f" ]; then
    rm -f "$INSTALL_DIR/$f"
    echo "  - $INSTALL_DIR/$f"
    removed=$((removed + 1))
  fi
done

if [ "$REMOVE_PATH" = true ]; then
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
    [ -f "$rc" ] || continue
    if grep -qF "$INSTALL_DIR" "$rc" 2>/dev/null; then
      tmp="$(mktemp)"
      grep -vF "$INSTALL_DIR" "$rc" > "$tmp" && mv "$tmp" "$rc"
      echo "  PATH cleaned in $rc"
    fi
  done
fi

if [ "$PURGE" = true ]; then
  rmdir "$INSTALL_DIR" 2>/dev/null || true
  rm -rf "$CACHE_DIR" 2>/dev/null || true
fi

if [ "$removed" -gt 0 ]; then
  echo "OpenCode uninstalled ($removed file(s))."
else
  echo "Nothing to uninstall in $INSTALL_DIR"
fi
exit 0
