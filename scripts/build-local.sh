#!/usr/bin/env bash
set -euo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/local-exec.sh" ruby bin/jpmd build "$@"
