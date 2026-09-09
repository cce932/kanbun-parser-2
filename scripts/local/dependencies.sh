#!/usr/bin/env bash
# Versions are deliberately kept here, rather than inferred from globally
# installed commands. Patch releases are resolved during setup and recorded in
# .local/conda-explicit.txt for the current platform.
JPMD_RUBY_SPEC='ruby=3.3.*'
JPMD_PANDOC_SPEC='pandoc=3.6.*'
JPMD_MINITEST_VERSION='5.25.5'
JPMD_REXML_VERSION='3.4.4'
JPMD_TEXLIVE_YEAR='2026'
JPMD_TEXLIVE_REPOSITORIES=(
  'https://mirrors.rit.edu/CTAN/systems/texlive/tlnet'
  'https://mirror.ctan.org/systems/texlive/tlnet'
)
JPMD_TEXLIVE_REPOSITORY="${JPMD_TEXLIVE_REPOSITORIES[0]}"

# tlmgr follows dependencies, so this remains smaller than installing TeX Live
# collections wholesale while covering the packages used by this project.
JPMD_TEX_PACKAGES=(
  jlreq luatexja titlesec haranoaji lualatex-math selnolig kanbun lua-ul luacolor
  fancyhdr caption footnotehyper xurl
)
