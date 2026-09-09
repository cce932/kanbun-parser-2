# AGENTS.md

Use this file as the primary bootstrap contract for automation.

```yaml
repo:
  name: kanbun-parser
  root_required: true
  primary_goal: compile markdown to PDF with kanbun annotations

entrypoints:
  setup_unix: ./scripts/setup-local.sh
  cli_unix: ./scripts/local-exec.sh ruby bin/jpmd
  cli_windows: .\\bin\\jpmd.cmd
  visual_suite: ./scripts/local-exec.sh ruby scripts/run_visual_suite.rb

examples:
  full_document: examples/academic-paper.md
  kanbun_only: examples/minimal-kanbun.md
  citation_document: examples/two-file-manuscript.md
  config_default: test/fixtures/config-default.md
  config_inline: test/fixtures/config-inline.md
  config_outsourced: test/fixtures/config-outsourced.md
  linux_script: examples/scripts/build-linux.sh
  windows_script: examples/scripts/build-windows.ps1

required_tools:
  common:
    - ruby
    - pandoc
    - lualatex
  texlive_packages:
    - jlreq
    - luatexja
    - titlesec
    - haranoaji
    - lualatex-math
    - selnolig

font_rules:
  linux:
    preferred_source: vendor/fonts
    required_files:
      - vendor/fonts/times.ttf
      - vendor/fonts/timesbd.ttf
      - vendor/fonts/timesi.ttf
      - vendor/fonts/timesbi.ttf
      - vendor/fonts/msmincho.ttc
  windows:
    required_installed_fonts:
      - Times New Roman
      - MS Mincho

environment_variables:
  optional:
    - PANDOC_PATH
    - LUALATEX_PATH
    - JPMD_WINDOWS_FONT_DIR
    - JPMD_TIMES_NEW_ROMAN_REGULAR
    - JPMD_TIMES_NEW_ROMAN_BOLD
    - JPMD_TIMES_NEW_ROMAN_ITALIC
    - JPMD_TIMES_NEW_ROMAN_BOLD_ITALIC
    - JPMD_MS_MINCHO

verification:
  tests:
    - ./scripts/local-exec.sh ruby -Itest test/jpmd_config_test.rb
    - ./scripts/local-exec.sh ruby -Itest test/jpmd_compiler_test.rb
    - ./scripts/local-exec.sh ruby -Itest test/jpmd_cli_test.rb
    - ./scripts/local-exec.sh ruby -Itest test/local_environment_test.rb
  sample_builds_unix:
    - ./scripts/build-local.sh examples/minimal-kanbun.md
    - ./scripts/build-local.sh examples/academic-paper.md
    - ./scripts/build-local.sh examples/two-file-manuscript.md
  config_fixture_builds:
    - ./scripts/build-local.sh test/fixtures/config-default.md
    - ./scripts/build-local.sh test/fixtures/config-inline.md
    - ./scripts/build-local.sh test/fixtures/config-outsourced.md
    - tracked_snapshots: test/fixtures/pdf
  sample_builds_windows:
    - .\\bin\\jpmd.cmd build .\\examples\\minimal-kanbun.md
    - .\\bin\\jpmd.cmd build .\\examples\\academic-paper.md
    - .\\bin\\jpmd.cmd build .\\examples\\two-file-manuscript.md
  visual_suite:
    - ./scripts/local-exec.sh ruby scripts/run_visual_suite.rb
    - report_path: out/variation-suite/report.html

operating_notes:
  - run commands from repo root
  - .local/ contains project tools, gems, downloads, and caches; it is gitignored
  - local setup supports macOS and Linux; native Windows retains manual setup
  - dependency policy is scripts/local/dependencies.sh
  - use local-exec.sh for commands so temporary files and TeX caches stay local
  - PDF output is not automatically copied to ../transfer/
  - out/ is generated and gitignored
  - tracked fixture PDFs belong in test/fixtures/pdf, not out/
  - project defaults are in jpmd.yml
  - document overrides are read from jpmd: YAML frontmatter
  - shared YAML can be referenced from document frontmatter with jpmd.config
  - bibliography and csl metadata are read from top-level Markdown frontmatter
  - default PDF output is out/<input-basename>.pdf unless jpmd.output.pdf overrides it
  - TeX is emitted only when jpmd.output.tex is set in frontmatter
  - kanbun syntax is [BASE]{f=\"...\" o=\"...\" k=\"...\"}
  - visual suite cases are defined in test/variation_suite.yml

failure_triage:
  missing_pandoc: run ./scripts/setup-local.sh and use ./scripts/build-local.sh
  missing_lualatex: run ./scripts/setup-local.sh and use ./scripts/build-local.sh
  missing_fonts_linux: verify vendor/fonts or font env vars
  missing_fonts_windows: install Times New Roman and MS Mincho
  latex_failure: set jpmd.output.tex in frontmatter, inspect the emitted tex, and rerun
```
