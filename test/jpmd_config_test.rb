# frozen_string_literal: true

require_relative "test_helper"

class JPMDConfigTest < Minitest::Test
  include JPMDTestHelper

  def test_fixture_without_jpmd_format_config_uses_defaults
    with_empty_project_config do |config_path|
      resolved = JPMD::Config.new(
        input_path: fixture_path("config-default.md"),
        config_path: config_path
      ).resolve

      derived = resolved.fetch("derived")
      assert_equal "academic", resolved.fetch("preset_name")
      assert_equal 35, derived.fetch("characters_per_line")
      assert_equal 30, derived.fetch("lines_per_page")
      assert_equal "12pt", derived.fetch("body_size")
    end
  end

  def test_fixture_with_inline_yaml_config_overrides_defaults
    with_empty_project_config do |config_path|
      resolved = JPMD::Config.new(
        input_path: fixture_path("config-inline.md"),
        config_path: config_path
      ).resolve

      derived = resolved.fetch("derived")
      assert_equal "academic", resolved.fetch("preset_name")
      assert_equal 30, derived.fetch("characters_per_line")
      assert_equal 30, derived.fetch("lines_per_page")
      assert_equal File.expand_path("../out/config-inline.tex", __dir__), resolved.fetch("output").fetch("tex_path")
    end
  end

  def test_fixture_with_outsourced_yaml_config_merges_reference_then_inline_overrides
    with_empty_project_config do |config_path|
      resolved = JPMD::Config.new(
        input_path: fixture_path("config-outsourced.md"),
        config_path: config_path
      ).resolve

      derived = resolved.fetch("derived")
      assert_equal "academic", resolved.fetch("preset_name")
      assert_equal 30, derived.fetch("characters_per_line")
      assert_equal 30, derived.fetch("lines_per_page")
      assert_equal "12pt", derived.fetch("body_size")
      assert_equal File.expand_path("../out/config-outsourced.tex", __dir__), resolved.fetch("output").fetch("tex_path")
    end
  end

  def test_default_preset_derives_expected_grid
    with_temp_markdown do |input_path, config_path|
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      derived = resolved.fetch("derived")
      assert_equal 35, derived.fetch("characters_per_line")
      assert_equal 30, derived.fetch("lines_per_page")
      assert_equal "12pt", derived.fetch("body_size")
      assert_equal(
        {
          "top" => "3cm",
          "right" => "3cm",
          "bottom" => "2cm",
          "left" => "3cm"
        },
        resolved.dig("settings", "layout", "margins")
      )
      assert_equal File.join(File.dirname(config_path), "out", "sample.pdf"), resolved.fetch("output").fetch("pdf_path")
      assert_nil resolved.fetch("output").fetch("tex_path")
      assert_operator derived.fetch("kanjiskip_pt"), :>, 0
      assert_operator derived.fetch("baselineskip_pt"), :>, 0
    end
  end

  def test_missing_project_config_matches_repository_default
    with_temp_markdown do |input_path, empty_config_path|
      missing_config_path = File.join(File.dirname(empty_config_path), "missing-jpmd.yml")
      refute_path_exists missing_config_path

      builtin = JPMD::Config.new(
        input_path: input_path,
        config_path: missing_config_path
      ).resolve
      repository = JPMD::Config.new(
        input_path: input_path,
        config_path: File.expand_path("../jpmd.yml", __dir__)
      ).resolve

      assert_equal repository.fetch("settings"), builtin.fetch("settings")
      assert_equal repository.fetch("derived"), builtin.fetch("derived")
    end
  end

  def test_default_csl_is_resolved_from_project_config
    with_temp_markdown do |input_path, config_path|
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      assert_equal File.join(JPMD::Compiler::APP_ROOT, "references", "word-japanese-note.csl"), resolved.fetch("csl")
    end
  end

  def test_document_overrides_change_layout
    frontmatter = {
      "layout" => {
        "grid" => {
          "characters_per_line" => 20,
          "lines_per_page" => 24
        },
        "font" => {
          "body_size" => "10pt"
        }
      }
    }

    with_temp_markdown(frontmatter) do |input_path, config_path|
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      derived = resolved.fetch("derived")
      assert_equal 20, derived.fetch("characters_per_line")
      assert_equal 24, derived.fetch("lines_per_page")
      assert_equal "10pt", derived.fetch("body_size")
    end
  end

  def test_document_can_override_first_line_indent
    frontmatter = {
      "layout" => {
        "paragraph" => {
          "first_line_indent" => "0pt"
        }
      }
    }

    with_temp_markdown(frontmatter) do |input_path, config_path|
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      assert_equal "0pt", resolved.fetch("derived").fetch("first_line_indent")
    end
  end

  def test_document_can_disable_page_numbers
    frontmatter = {
      "layout" => {
        "page_numbers" => false
      }
    }

    with_temp_markdown(frontmatter) do |input_path, config_path|
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      assert_equal false, resolved.fetch("derived").fetch("page_numbers")
    end
  end

  def test_invalid_page_numbers_value_is_rejected
    frontmatter = {
      "layout" => {
        "page_numbers" => "false"
      }
    }

    with_temp_markdown(frontmatter) do |input_path, config_path|
      error = assert_raises(JPMD::ValidationError) do
        JPMD::Config.new(
          input_path: input_path,
          config_path: config_path
        ).resolve
      end

      assert_match(/layout\.page_numbers/, error.message)
    end
  end

  def test_invalid_negative_shift_is_rejected
    frontmatter = {
      "kanbun" => {
        "furigana" => {
          "shift" => {
            "left" => "-1pt"
          }
        }
      }
    }

    with_temp_markdown(frontmatter) do |input_path, config_path|
      error = assert_raises(JPMD::ValidationError) do
        JPMD::Config.new(
          input_path: input_path,
          config_path: config_path
        ).resolve
      end

      assert_match(/kanbun\.furigana\.shift\.left/, error.message)
    end
  end

  def test_document_writing_mode_option_is_rejected
    frontmatter = {
      "layout" => {
        "writing_mode" => "tate"
      }
    }

    with_temp_markdown(frontmatter) do |input_path, config_path|
      error = assert_raises(JPMD::ValidationError) do
        JPMD::Config.new(
          input_path: input_path,
          config_path: config_path
        ).resolve
      end

      assert_match(/jpmd\.layout\.writing_mode/, error.message)
      assert_match(/no longer configurable/, error.message)
    end
  end

  def test_project_writing_mode_option_is_rejected
    with_temp_markdown do |input_path, config_path|
      File.write(config_path, <<~YAML, mode: "w:utf-8")
        presets:
          academic:
            layout:
              writing_mode: tate
      YAML

      error = assert_raises(JPMD::ValidationError) do
        JPMD::Config.new(
          input_path: input_path,
          config_path: config_path
        ).resolve
      end

      assert_match(/presets\.academic\.layout\.writing_mode/, error.message)
      assert_match(/no longer configurable/, error.message)
    end
  end

  def test_impossible_character_count_is_rejected
    frontmatter = {
      "layout" => {
        "grid" => {
          "characters_per_line" => 40
        }
      }
    }

    with_temp_markdown(frontmatter) do |input_path, config_path|
      error = assert_raises(JPMD::ValidationError) do
        JPMD::Config.new(
          input_path: input_path,
          config_path: config_path
        ).resolve
      end

      assert_match(/negative kanjiskip/, error.message)
    end
  end

  def test_project_preset_overrides_builtin_defaults
    with_temp_markdown do |input_path, config_path|
      File.write(config_path, <<~YAML, mode: "w:utf-8")
        default_preset: academic
        presets:
          academic:
            layout:
              font:
                body_size: 11pt
      YAML

      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      assert_equal "11pt", resolved.fetch("derived").fetch("body_size")
    end
  end

  def test_document_output_paths_are_resolved_relative_to_document
    Dir.mktmpdir("jpmd-config-") do |dir|
      docs_dir = File.join(dir, "docs")
      FileUtils.mkdir_p(docs_dir)
      input_path = File.join(docs_dir, "sample.md")
      config_path = File.join(dir, "jpmd.yml")

      File.write(config_path, "{}\n", mode: "w:utf-8")
      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        jpmd:
          output:
            pdf: builds/sample.pdf
            tex: builds/sample.tex
        ---

        本文
      MARKDOWN

      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      assert_equal File.join(docs_dir, "builds", "sample.pdf"), resolved.fetch("output").fetch("pdf_path")
      assert_equal File.join(docs_dir, "builds", "sample.tex"), resolved.fetch("output").fetch("tex_path")
    end
  end

  def test_linear_preset_uses_tate_writing_mode_and_swapped_page_axes
    with_temp_markdown({ "preset" => "linear" }) do |input_path, config_path|
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve

      derived = resolved.fetch("derived")
      assert_equal "tate", derived.fetch("writing_mode")
      assert_equal 24, derived.fetch("characters_per_line")
      assert_equal 11, derived.fetch("lines_per_page")
      assert_operator derived.fetch("kanjiskip_pt"), :>, 0
      assert_operator derived.fetch("baselineskip_pt"), :>, 0
      assert_operator derived.fetch("baselineskip_pt"), :>, derived.fetch("kanjiskip_pt")
    end
  end

  def test_missing_document_referenced_yaml_is_rejected
    Dir.mktmpdir("jpmd-config-") do |dir|
      input_path = File.join(dir, "sample.md")
      config_path = File.join(dir, "jpmd.yml")

      File.write(config_path, "{}\n", mode: "w:utf-8")
      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        jpmd:
          config: missing.yml
        ---

        本文
      MARKDOWN

      error = assert_raises(JPMD::ValidationError) do
        JPMD::Config.new(
          input_path: input_path,
          config_path: config_path
        ).resolve
      end

      assert_match(/Referenced YAML file not found/, error.message)
    end
  end

  private

  def fixture_path(name)
    File.expand_path(File.join("fixtures", name), __dir__)
  end

  def with_empty_project_config
    Dir.mktmpdir("jpmd-config-") do |dir|
      config_path = File.join(dir, "jpmd.yml")
      File.write(config_path, "{}\n", mode: "w:utf-8")
      yield config_path
    end
  end
end
