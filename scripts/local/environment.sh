#!/usr/bin/env bash
# This file is sourced by the project launchers, never by an interactive shell.
JPMD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JPMD_LOCAL="$JPMD_ROOT/.local"

export MAMBA_ROOT_PREFIX="$JPMD_LOCAL/mamba"
export GEM_HOME="$JPMD_LOCAL/gems"
export GEM_PATH="$GEM_HOME"
export GEM_SPEC_CACHE="$JPMD_LOCAL/cache/gem-specs"
export TMPDIR="$JPMD_LOCAL/tmp"
export XDG_CACHE_HOME="$JPMD_LOCAL/cache"
export XDG_CONFIG_HOME="$JPMD_LOCAL/config"
export XDG_DATA_HOME="$JPMD_LOCAL/data"
export TEXMFHOME="$JPMD_LOCAL/texmf-home"
export TEXMFVAR="$JPMD_LOCAL/texmf-var"
export TEXMFCONFIG="$JPMD_LOCAL/texmf-config"
export TEXMFCACHE="$JPMD_LOCAL/texmf-var"
mkdir -p "$TMPDIR" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$GEM_HOME" "$TEXMFHOME" "$TEXMFVAR" "$TEXMFCONFIG"

JPMD_TEXBIN=''
for candidate in "$JPMD_LOCAL"/texlive/bin/*; do
  if [[ -x "$candidate/lualatex" ]]; then
    JPMD_TEXBIN="$candidate"
    break
  fi
done

# Explicit paths ensure the compiler cannot silently use a global installation.
export PANDOC_PATH="$JPMD_LOCAL/runtime/bin/pandoc"
export LUALATEX_PATH="${JPMD_TEXBIN:-$JPMD_LOCAL/texlive/bin/missing}/lualatex"
export PATH="$JPMD_LOCAL/runtime/bin:$GEM_HOME/bin:${JPMD_TEXBIN:-$JPMD_LOCAL/texlive/bin/missing}:$PATH"
