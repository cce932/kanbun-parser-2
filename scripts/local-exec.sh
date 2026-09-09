#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/local/environment.sh"

if [[ ! -x "$JPMD_LOCAL/runtime/bin/ruby" || ! -x "$PANDOC_PATH" || ! -x "$LUALATEX_PATH" ]]; then
  echo 'Local dependencies are missing. Run ./scripts/setup-local.sh first.' >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo 'Usage: ./scripts/local-exec.sh COMMAND [ARGUMENTS...]' >&2
  exit 1
fi

cd "$JPMD_ROOT"
exec "$@"
