#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

./scripts/local-exec.sh ruby -Itest test/jpmd_config_test.rb
./scripts/local-exec.sh ruby -Itest test/jpmd_compiler_test.rb
./scripts/build-local.sh examples/minimal-kanbun.md
./scripts/build-local.sh examples/two-file-manuscript.md
