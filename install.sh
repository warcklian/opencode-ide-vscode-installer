#!/usr/bin/env bash
# OpenCode Portable Installer - macOS / Linux
#
# Adaptive, self-updating installer for the OpenCode CLI.
#
# It inspects the machine first (existing OpenCode, PATH, available tools),
# resolves the latest OpenCode version live (no version URLs are hardcoded),
# downloads the package for YOUR platform from the npm registry, verifies its
# sha512 integrity, installs it and, with your consent, adds it to the PATH.
#
# Usage: ./install.sh [options]
#   --version <v>       Install a specific version (default: latest).
#   --install-dir <p>   Installation folder (default: $HOME/.opencode/bin).
#   --cache-dir <p>     Package cache folder.
#   --check             Only check (exit 10 if an install/update is needed).
#   --update            Update only if a newer version exists.
#   --dry-run           Show the plan without installing.
#   --offline           Use only the local cache.
#   --no-path           Do not modify the PATH.
#   --yes               Assume yes to prompts (non-interactive).
#   --no-ollama         Skip auto Ollama provider setup.
#   --force             Reinstall.
#   --json              JSON output (non-interactive).
#   --quiet             Minimal output.
#   -h, --help          Help.

set -euo pipefail

APP="opencode"
TOOLKIT_NAME="opencode-ide-vscode-installer"
TOOLKIT_VERSION="1.1.0"
UPDATE_API="https://opencode.ai/update/api/latest/cli/npm"
NPM_REGISTRY="https://registry.npmjs.org"
SCOPE="@opencode"
LEGACY_SCOPE="@opencode-ai"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; DIM='\033[2m'; CYAN='\033[0;36m'; NC='\033[0m'

if [ -t 1 ]; then
  C_RED="$RED"; C_GREEN="$GREEN"; C_YELLOW="$YELLOW"; C_DIM="$DIM"; C_CYAN="$CYAN"; C_NC="$NC"
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_DIM=""; C_CYAN=""; C_NC=""
fi

info() { printf '%b\n' "${C_NC}$*${C_NC}"; }
ok()   { printf '%b\n' "${C_GREEN}$*${C_NC}"; }
warn() { printf '%b\n' "${C_YELLOW}$*${C_NC}"; }
dim()  { printf '%b\n' "${C_DIM}$*${C_NC}"; }
title(){ printf '%b\n' "${C_CYAN}$*${C_NC}"; }
err()  { printf '%b\n' "${C_RED}$*${C_NC}" >&2; }
die()  { err "ERROR: $*"; exit 1; }

# --- Arguments ---------------------------------------------------------------
VERSION_REQUESTED=""
INSTALL_DIR="${HOME}/.opencode/bin"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/${TOOLKIT_NAME}"
CHECK=false; UPDATE=false; DRY_RUN=false; OFFLINE=false
NOPATH=false; YES=false; NO_OLLAMA=false; FORCE=false; JSON=false; QUIET=false
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }
log() { [ "$JSON" = true ] && return 0; [ "$QUIET" = true ] && return 0; "$@"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)     VERSION_REQUESTED="${2:?missing value}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:?missing value}"; shift 2 ;;
    --cache-dir)   CACHE_DIR="${2:?missing value}"; shift 2 ;;
    --check)       CHECK=true; shift ;;
    --update)      UPDATE=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --offline)     OFFLINE=true; shift ;;
    --no-path)     NOPATH=true; shift ;;
    --yes|-y)      YES=true; shift ;;
    --no-ollama)   NO_OLLAMA=true; shift ;;
    --force)       FORCE=true; shift ;;
    --json)        JSON=true; shift ;;
    --quiet)       QUIET=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [ "$JSON" = true ]; then QUIET=true; fi
INTERACTIVE=false
{ [ -t 0 ] && [ -t 1 ]; } && INTERACTIVE=true

# --- System inspection (adaptive) --------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
tool_path() { command -v "$1" 2>/dev/null || true; }

detect_target() {
  local raw_os os arch baseline=false musl=false
  raw_os="$(uname -s)"
  case "$raw_os" in
    Darwin*) os="darwin" ;;
    Linux*)  os="linux" ;;
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    *) die "Unsupported OS: $raw_os" ;;
  esac
  arch="$(uname -m)"
  case "$arch" in
    aarch64|arm64) arch="arm64" ;;
    x86_64|amd64)  arch="x64" ;;
  esac
  if [ "$os" = "darwin" ] && [ "$arch" = "x64" ]; then
    if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then arch="arm64"; fi
  fi
  if [ "$arch" = "x64" ]; then
    if [ "$os" = "linux" ]; then
      grep -qwi avx2 /proc/cpuinfo 2>/dev/null || baseline=true
    elif [ "$os" = "darwin" ]; then
      [ "$(sysctl -n hw.optional.avx2_0 2>/dev/null || echo 0)" = "1" ] || baseline=true
    elif [ "$os" = "windows" ]; then
      baseline=true
    fi
  fi
  if [ "$os" = "linux" ]; then
    [ -f /etc/alpine-release ] && musl=true
    if have ldd && ldd --version 2>&1 | grep -qi musl; then musl=true; fi
  fi
  TARGET="$os-$arch"
  [ "$baseline" = true ] && TARGET="$TARGET-baseline"
  [ "$musl" = true ] && TARGET="$TARGET-musl"
  OS="$os"
}

print_system_report() {
  log title "System check"
  log dim "  Platform            : $OS / $(uname -m)  -> target $TARGET"
  local t
  for t in tar curl git node npm bun pnpm yarn ollama; do
    if have "$t"; then log dim "  $(printf '%-19s' "$t") : $(tool_path "$t")"
    else log dim "  $(printf '%-19s' "$t") : (not found)"; fi
  done
  if have tar; then log dim "  Extraction method   : tar"; else log dim "  Extraction method   : (tar required)"; fi
  if [ -n "${MANAGED_VERSION:-}" ]; then log dim "  OpenCode (managed)  : $INSTALL_DIR/$APP (v$MANAGED_VERSION)"
  else log dim "  OpenCode (managed)  : not installed"; fi
  if [ -n "${PATH_OPENCODE:-}" ]; then log dim "  OpenCode (on PATH)  : $PATH_OPENCODE (v${PATH_OPENCODE_VERSION:-unknown})"
  else log dim "  OpenCode (on PATH)  : not found"; fi
  case ":$PATH:" in *":$INSTALL_DIR:"*) log dim "  Install dir on PATH : yes" ;;
    *) log dim "  Install dir on PATH : no" ;; esac
}

# --- Version resolution ------------------------------------------------------
urlencode_pkg() { printf '%s' "$1" | sed 's/@/%40/g; s#/#%2F#g'; }

resolve_version() {
  local json ver pkg
  json="$(curl -fsSL "$UPDATE_API" 2>/dev/null || true)"
  if [ -n "$json" ]; then
    ver="$(printf '%s' "$json" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n1)"
    pkg="$(printf '%s' "$json" | sed -n 's/.*"package":"\([^"]*\)".*/\1/p' | head -n1)"
    [ -n "$pkg" ] && SCOPE="${pkg%/cli}"
  fi
  if [ -z "${ver:-}" ]; then
    json="$(curl -fsSL "$NPM_REGISTRY/$(urlencode_pkg "$SCOPE/cli")/latest" 2>/dev/null || true)"
    ver="$(printf '%s' "$json" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n1)"
  fi
  [ -n "${ver:-}" ] || die "Could not resolve the latest version."
  VERSION="$ver"
}

resolve_package() {
  local name enc status doc
  for name in "$SCOPE/cli-$TARGET" "$LEGACY_SCOPE/cli-$TARGET"; do
    enc="$(urlencode_pkg "$name")"
    status="$(curl -s -o /dev/null -w '%{http_code}' "$NPM_REGISTRY/$enc/$VERSION" || true)"
    if [ "$status" = "200" ]; then
      doc="$(curl -fsSL "$NPM_REGISTRY/$enc/$VERSION")"
      TARBALL="$(printf '%s' "$doc" | grep -o '"tarball":"[^"]*"' | head -n1 | sed 's/^"tarball":"//; s/"$//')"
      INTEGRITY="$(printf '%s' "$doc" | grep -o '"integrity":"[^"]*"' | head -n1 | sed 's/^"integrity":"//; s/"$//')"
      PKG_NAME="$name"
      [ -n "$TARBALL" ] && return 0
    fi
  done
  die "No package available for target '$TARGET' version '$VERSION'."
}

# --- Integrity ---------------------------------------------------------------
file_sha512_hex() {
  if have sha512sum; then sha512sum "$1" | awk '{print tolower($1)}'
  elif have shasum; then shasum -a 512 "$1" | awk '{print tolower($1)}'
  elif have openssl; then openssl dgst -sha512 "$1" | awk '{print $NF}' | tr 'A-Z' 'a-z'
  else printf ''; fi
}
b64_to_hex() { openssl base64 -d -A 2>/dev/null | od -An -tx1 | tr -d ' \n'; }

verify_sha512() {
  local file="$1" integrity="${2:-}" expected actual hex
  [ -n "$integrity" ] || return 0
  case "$integrity" in sha512-*) expected="${integrity#sha512-}" ;; *) return 0 ;; esac
  actual="$(file_sha512_hex "$file")"
  if [ -z "$actual" ]; then warn "No sha512sum/shasum/openssl; skipping integrity verification."; return 0; fi
  hex="$(printf '%s' "$expected" | b64_to_hex)"
  [ "$actual" = "$hex" ] && return 0
  return 1
}

# --- Version comparison ------------------------------------------------------
version_gt() {
  local IFS=. i x y; local a=($1) b=($2)
  for i in 0 1 2; do
    x="${a[$i]:-0}"; y="${b[$i]:-0}"
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
    x="${x:-0}"; y="${y:-0}"
    if [ "$x" -gt "$y" ]; then return 0; fi
    if [ "$x" -lt "$y" ]; then return 1; fi
  done
  return 1
}
version_eq() {
  local IFS=. i x y; local a=($1) b=($2)
  for i in 0 1 2; do
    x="${a[$i]:-0}"; y="${b[$i]:-0}"
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
    x="${x:-0}"; y="${y:-0}"
    [ "$x" = "$y" ] || return 1
  done
  return 0
}

version_from_exe() {
  local exe="$1"
  [ -x "$exe" ] || return 1
  "$exe" --version < /dev/null 2>/dev/null | awk '{print $NF}' | sed 's/^[vV]//'
}

# --- Install -----------------------------------------------------------------
install_binary() {
  local cache_file tmp bin_name src
  mkdir -p "$INSTALL_DIR" "$CACHE_DIR"
  cache_file="$CACHE_DIR/$(basename "$TARBALL")"
  bin_name="$APP"
  [ "$OS" = "windows" ] && bin_name="$APP.exe"

  if [ "$FORCE" = true ] || [ ! -f "$cache_file" ] || ! verify_sha512 "$cache_file" "$INTEGRITY"; then
    if [ "$OFFLINE" = true ]; then die "Offline and no cached package: $cache_file"; fi
    log info "  Downloading $TARBALL"
    rm -f "$cache_file"
    local curlflags="-fL --retry 3 --retry-delay 2"
    if [ "$QUIET" = true ]; then curlflags="$curlflags -sS"; fi
    curl $curlflags -o "$cache_file" "$TARBALL" || die "Download failed."
    verify_sha512 "$cache_file" "$INTEGRITY" || { rm -f "$cache_file"; die "Integrity verification failed."; }
  else
    log dim "  Using verified cached package."
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  tar -xzf "$cache_file" -C "$tmp" || die "tar failed to extract."
  src="$tmp/package/bin/$bin_name"
  if [ ! -f "$src" ]; then src="$(find "$tmp" -type f -name "$bin_name" | head -n1)"; fi
  [ -n "${src:-}" ] && [ -f "$src" ] || die "Could not find '$bin_name' inside the package."
  cp -f "$src" "$INSTALL_DIR/$bin_name"
  chmod 755 "$INSTALL_DIR/$bin_name"

  cat > "$INSTALL_DIR/opencode2" <<'SHIM'
#!/bin/sh
exec "$(dirname "$0")/opencode" "$@"
SHIM
  chmod 755 "$INSTALL_DIR/opencode2"
  log ok "  Installed binary at $INSTALL_DIR/$bin_name"
}

resolve_consent() {
  # Prints "yes" or "no" for adding INSTALL_DIR to PATH.
  if [ "$NOPATH" = true ]; then printf 'no'; return 0; fi
  if [ "$YES" = true ]; then printf 'yes'; return 0; fi
  if [ "$INTERACTIVE" != true ]; then printf 'no'; return 0; fi
  local ans
  printf 'Add OpenCode to your PATH (%s)? [Y/n] ' "$INSTALL_DIR" >&2
  read -r ans || ans=""
  case "$ans" in
    ""|y|Y|yes|YES|Yes) printf 'yes' ;;
    *) printf 'no' ;;
  esac
}

add_to_path() {
  case ":$PATH:" in *":$INSTALL_DIR:"*) return 0 ;; esac
  local consent rc
  consent="$(resolve_consent)"
  if [ "$consent" != "yes" ]; then
    log warn "  PATH not modified. Add it later with --yes  (folder: $INSTALL_DIR)"
    return 0
  fi
  case "${SHELL:-}" in
    */zsh)  rc="$HOME/.zshrc" ;;
    */bash) rc="$HOME/.bashrc" ;;
    *)      rc="$HOME/.profile" ;;
  esac
  [ -f "$rc" ] || rc="$HOME/.profile"
  if grep -qF "$INSTALL_DIR" "$rc" 2>/dev/null; then return 0; fi
  printf '\n# opencode\n%s\n' "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$rc"
  log dim "  PATH updated in $rc (restart your terminal)."
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
emit_json() {
  printf '{"ok":true,"action":"%s","installed":%s,"previous":%s,"available":"%s","target":"%s","package":"%s","tarball":"%s","source":"%s","installDir":"%s","extraction":"%s"}\n' \
    "$ACTION" \
    "$( [ -n "${NEW_VERSION:-}" ] && printf '"%s"' "$NEW_VERSION" || printf 'null')" \
    "$( [ -n "${installed:-}" ] && printf '"%s"' "$installed" || printf 'null')" \
    "$(json_escape "$VERSION")" "$(json_escape "$TARGET")" "$(json_escape "$PKG_NAME")" \
    "$(json_escape "$TARBALL")" "$SOURCE" "$(json_escape "$INSTALL_DIR")" "$EXTRACTION"
}

# --- Main flow ---------------------------------------------------------------
have curl || die "'curl' is required."
have tar  || die "'tar' is required."
EXTRACTION="tar"

detect_target
if [ "$JSON" = false ]; then
  printf '\n'; title "OpenCode Portable Installer"
  dim "  Toolkit v$TOOLKIT_VERSION"
fi

# System inspection.
MANAGED_VERSION="$(version_from_exe "$INSTALL_DIR/$APP" || true)"
PATH_OPENCODE="$(command -v "$APP" 2>/dev/null || true)"
PATH_OPENCODE_VERSION=""
if [ -n "$PATH_OPENCODE" ]; then PATH_OPENCODE_VERSION="$(version_from_exe "$PATH_OPENCODE" || true)"; fi
if [ "$JSON" = false ]; then printf '\n'; print_system_report; printf '\n'; fi

# Version + package resolution.
if [ -n "$VERSION_REQUESTED" ]; then VERSION="$VERSION_REQUESTED"; SOURCE="pinned"; else resolve_version; SOURCE="update-api"; fi
resolve_package

installed="$MANAGED_VERSION"
UPDATE_AVAILABLE=false
if [ -n "${installed:-}" ]; then
  if version_gt "$VERSION" "$installed"; then UPDATE_AVAILABLE=true; fi
else
  UPDATE_AVAILABLE=true
fi

if [ "$JSON" = false ]; then
  info "  Available version: $VERSION ($SOURCE)"
  info "  Installed version: ${installed:-(none)}"
  dim "  Package          : $PKG_NAME"
  dim "  Tarball          : $TARBALL"
  printf '\n'
fi

# Check mode.
if [ "$CHECK" = true ]; then
  ACTION="check"
  if [ "$JSON" = true ]; then emit_json
  elif [ -z "${installed:-}" ]; then warn "  OpenCode is not installed. Would install $VERSION."
  elif [ "$UPDATE_AVAILABLE" = true ]; then warn "  Update available: $installed -> $VERSION."
  else ok "  Already up to date ($VERSION)."; fi
  [ "$UPDATE_AVAILABLE" = true ] && exit 10 || exit 0
fi

# Dry run.
if [ "$DRY_RUN" = true ]; then
  ACTION="dry-run"
  if [ "$JSON" = true ]; then emit_json; elif [ "$QUIET" = false ]; then dim "  [DryRun] Nothing was changed."; fi
  exit 0
fi

# Decide whether to install.
SHOULD_INSTALL=true
if [ "$FORCE" = false ] && [ -n "${installed:-}" ]; then
  if version_eq "$VERSION" "$installed" || version_gt "$installed" "$VERSION"; then SHOULD_INSTALL=false; fi
fi
# An existing OpenCode elsewhere on PATH that is already current: do not duplicate.
EXTERNAL_CURRENT=false
if [ -n "$PATH_OPENCODE" ] && [ "$PATH_OPENCODE" != "$INSTALL_DIR/$APP" ]; then
  if [ -n "$PATH_OPENCODE_VERSION" ] && [ "$FORCE" = false ]; then
    if ! version_gt "$VERSION" "$PATH_OPENCODE_VERSION"; then EXTERNAL_CURRENT=true; fi
  fi
fi
if [ "$EXTERNAL_CURRENT" = true ] && [ -z "${installed:-}" ]; then SHOULD_INSTALL=false; fi

auto_ollama_setup() {
  [ "$NO_OLLAMA" = true ] && return 0
  [ "$DRY_RUN" = true ] && return 0
  [ "$CHECK" = true ] && return 0
  local setup="$SCRIPT_DIR/setup-ollama.sh"
  [ -f "$setup" ] || return 0
  local found=false
  if have ollama; then found=true; fi
  for c in /usr/local/bin/ollama /usr/bin/ollama /opt/homebrew/bin/ollama \
           "$HOME/.local/bin/ollama" "$HOME/bin/ollama"; do
    [ -x "$c" ] && found=true
  done
  # Also try a quick API probe (Ollama running without being on PATH).
  if [ "$found" = false ]; then
    if curl -fsS --max-time 2 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
      found=true
    fi
  fi
  [ "$found" = true ] || return 0
  log info "  Ollama detected: registering local models for Ctrl+X M ..."
  if [ "$JSON" = true ] || [ "$QUIET" = true ]; then
    bash "$setup" --quiet --write-even-if-unreachable >/dev/null 2>&1 || \
      log warn "  Ollama auto-setup failed (OpenCode install is OK). Retry: ./setup-ollama.sh"
  else
    bash "$setup" --write-even-if-unreachable || \
      warn "  Ollama auto-setup failed (OpenCode install is OK). Retry: ./setup-ollama.sh"
  fi
}

if [ "$SHOULD_INSTALL" = false ]; then
  ACTION="up-to-date"
  NEW_VERSION="$installed"
  if [ "$JSON" = true ]; then :
  elif [ "$QUIET" = false ]; then
    if [ "$EXTERNAL_CURRENT" = true ]; then ok "  OpenCode is already installed at $PATH_OPENCODE (v$PATH_OPENCODE_VERSION). Nothing to do."
    else ok "  Already up to date ($installed). Not reinstalling."; fi
  fi
  # Offer PATH help only if our managed binary exists.
  if [ -x "$INSTALL_DIR/$APP" ]; then
    case ":$PATH:" in *":$INSTALL_DIR:"*) : ;; *) add_to_path ;; esac
  fi
  auto_ollama_setup
  [ "$JSON" = true ] && emit_json
  exit 0
fi

# Install / update.
ACTION="installed"
[ -n "${installed:-}" ] && ACTION="updated"
if [ "$QUIET" = false ]; then
  if [ -n "${installed:-}" ]; then info "  Updating to OpenCode $VERSION into $INSTALL_DIR"
  else info "  Installing OpenCode $VERSION into $INSTALL_DIR"; fi
fi
install_binary
add_to_path
NEW_VERSION="$(version_from_exe "$INSTALL_DIR/$APP" || true)"
if [ "$QUIET" = false ]; then
  [ -n "${NEW_VERSION:-}" ] && ok "  Verified: opencode $NEW_VERSION"
  info '  Done. Open the Cursor integrated terminal and run: opencode'
fi
auto_ollama_setup
[ "$JSON" = true ] && emit_json
exit 0
