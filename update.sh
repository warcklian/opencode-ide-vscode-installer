#!/usr/bin/env bash
# OpenCode Portable - update to the latest version (macOS/Linux).
# Thin wrapper over install.sh --update. Does not reinstall when already current.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/install.sh" --update "$@"
