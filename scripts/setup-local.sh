#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/local/environment.sh"
source "$JPMD_ROOT/scripts/local/dependencies.sh"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=osx-arm64 ;;
  Darwin-x86_64) platform=osx-64 ;;
  Linux-x86_64) platform=linux-64 ;;
  Linux-aarch64) platform=linux-aarch64 ;;
  *) echo 'Supported platforms: macOS and Linux (x86_64 / arm64).' >&2; exit 1 ;;
esac

for tool in curl tar perl; do
  command -v "$tool" >/dev/null || { echo "Missing bootstrap tool: $tool" >&2; exit 1; }
done

mkdir -p "$JPMD_LOCAL/bootstrap" "$JPMD_LOCAL/downloads"
if [[ ! -x "$JPMD_LOCAL/bootstrap/bin/micromamba" ]]; then
  curl --fail --location --retry 3 "https://micro.mamba.pm/api/micromamba/$platform/latest" \
    -o "$JPMD_LOCAL/downloads/micromamba.tar.bz2"
  tar -xjf "$JPMD_LOCAL/downloads/micromamba.tar.bz2" -C "$JPMD_LOCAL/bootstrap" bin/micromamba
fi

mamba="$JPMD_LOCAL/bootstrap/bin/micromamba"
if [[ ! -d "$JPMD_LOCAL/runtime/conda-meta" ]]; then
  "$mamba" --no-rc create --yes --prefix "$JPMD_LOCAL/runtime" --override-channels --channel conda-forge \
    "$JPMD_RUBY_SPEC" "$JPMD_PANDOC_SPEC"
else
  "$mamba" --no-rc install --yes --prefix "$JPMD_LOCAL/runtime" --override-channels --channel conda-forge \
    "$JPMD_RUBY_SPEC" "$JPMD_PANDOC_SPEC"
fi
"$mamba" --no-rc list --prefix "$JPMD_LOCAL/runtime" --explicit > "$JPMD_LOCAL/conda-explicit.txt"

"$JPMD_LOCAL/runtime/bin/gem" install minitest --version "$JPMD_MINITEST_VERSION" --no-document
"$JPMD_LOCAL/runtime/bin/gem" install rexml --version "$JPMD_REXML_VERSION" --no-document

if [[ -z "$JPMD_TEXBIN" ]]; then
  curl --fail --location --retry 3 "$JPMD_TEXLIVE_REPOSITORY/install-tl-unx.tar.gz" \
    -o "$JPMD_LOCAL/downloads/install-tl.tar.gz"
  installer_dir="$(mktemp -d "$TMPDIR/install-tl.XXXXXX")"
  trap 'rm -rf "$installer_dir"' EXIT
  tar -xzf "$JPMD_LOCAL/downloads/install-tl.tar.gz" -C "$installer_dir" --strip-components=1
  installed=false
  for repository in "${JPMD_TEXLIVE_REPOSITORIES[@]}"; do
    if perl "$installer_dir/install-tl" --no-gui --no-interaction --portable --scheme=scheme-small \
      --no-doc-install --no-src-install --texdir="$JPMD_LOCAL/texlive" \
      --repository="$repository"; then
      JPMD_TEXLIVE_REPOSITORY="$repository"
      installed=true
      break
    fi
  done
  if [[ "$installed" != true ]]; then
    echo "Could not install TeX Live from any configured repository." >&2
    exit 1
  fi
fi

source "$JPMD_ROOT/scripts/local/environment.sh"
texlive_version="$($JPMD_TEXBIN/tlmgr --version)"
printf '%s\n' "$texlive_version" > "$JPMD_LOCAL/texlive-version.txt"
if ! grep -Fq "version $JPMD_TEXLIVE_YEAR" <<<"$texlive_version"; then
  echo "Expected TeX Live $JPMD_TEXLIVE_YEAR. Update the dependency policy and repository together." >&2
  exit 1
fi

"$JPMD_TEXBIN/tlmgr" --repository "$JPMD_TEXLIVE_REPOSITORY" install "${JPMD_TEX_PACKAGES[@]}"

"$JPMD_LOCAL/runtime/bin/ruby" --version
"$PANDOC_PATH" --version
"$LUALATEX_PATH" --version
printf '\nLocal setup complete. Build with ./scripts/build-local.sh examples/minimal-kanbun.md\n'
