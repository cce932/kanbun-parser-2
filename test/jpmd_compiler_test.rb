# frozen_string_literal: true

require_relative "test_helper"

class JPMDCompilerTest < Minitest::Test
  include JPMDTestHelper

  def test_resolve_font_setup_uses_exact_font_files_from_linux_directory
    with_temp_markdown do |input_path, config_path|
      Dir.mktmpdir("jpmd-fonts-") do |font_dir|
        %w[times.ttf timesbd.ttf timesi.ttf timesbi.ttf msmincho.ttc PMingLiU.ttf].each do |name|
          File.write(File.join(font_dir, name), "", mode: "wb")
        end

        compiler = compiler_for(input_path, config_path)
        previous = ENV["JPMD_WINDOWS_FONT_DIR"]
        ENV["JPMD_WINDOWS_FONT_DIR"] = font_dir

        compiler.stub(:windows?, false) do
          compiler.stub(:pmingliu_altfont_entries, ['Range={"503C},Font={PMingLiU.ttf},Path={/tmp/fonts/},TateFont={PMingLiU.ttf},YokoFeatures={JFM=jlreq},TateFeatures={JFM=jlreqv}']) do
            font_setup = compiler.send(:resolve_font_setup)
            assert_includes font_setup.fetch(:latin), "times.ttf"
            assert_includes font_setup.fetch(:japanese), "msmincho.ttc"
            assert_includes font_setup.fetch(:japanese), "BoldFeatures={FakeBold=2}"
            assert_includes font_setup.fetch(:japanese), "AltFont={"
            assert_includes font_setup.fetch(:japanese), "PMingLiU.ttf"
            assert_includes font_setup.fetch(:japanese), "Range={\"503C}"
            assert_includes font_setup.fetch(:japanese), "YokoFeatures={JFM=jlreq}"
            assert_includes font_setup.fetch(:japanese), "TateFeatures={JFM=jlreqv}"
          end
        end
      ensure
        ENV["JPMD_WINDOWS_FONT_DIR"] = previous
      end
    end
  end

  def test_missing_codepoints_for_fallback_detects_document_characters_not_in_ms_mincho
    with_temp_markdown("# 値 值 内 內\n") do |input_path, config_path|
      compiler = compiler_for(input_path, config_path)

      missing = compiler.send(
        :missing_codepoints_for_fallback,
        File.join(JPMD::Compiler::APP_ROOT, "vendor", "fonts", "msmincho.ttc"),
        File.join(JPMD::Compiler::APP_ROOT, "vendor", "fonts", "PMingLiU.ttf")
      )

      assert_equal [0x503C, 0x5167], missing
    end
  end

  def test_missing_codepoints_for_fallback_detects_sai_character
    with_temp_markdown("三九歲\n") do |input_path, config_path|
      compiler = compiler_for(input_path, config_path)

      missing = compiler.send(
        :missing_codepoints_for_fallback,
        File.join(JPMD::Compiler::APP_ROOT, "vendor", "fonts", "msmincho.ttc"),
        File.join(JPMD::Compiler::APP_ROOT, "vendor", "fonts", "PMingLiU.ttf")
      )

      assert_includes missing, 0x6B72
    end
  end

  def test_font_coverage_probe_uses_ascii_temp_copies_for_sources
    Dir.mktmpdir("jpmd-nonascii-") do |root|
      source_dir = File.join(root, "研究")
      FileUtils.mkdir_p(source_dir)
      input_path = File.join(source_dir, "sample.md")
      config_path = File.join(root, "jpmd.yml")
      File.write(input_path, [0x588E].pack("U*"), mode: "w:utf-8")
      File.write(config_path, "{}\n", mode: "w:utf-8")

      compiler = compiler_for(input_path, config_path)
      captured_sources = nil
      captured_contents = nil
      status = Object.new
      status.define_singleton_method(:success?) { true }

      compiler.stub(:resolve_texlua, "texlua") do
        Open3.stub(:capture3, lambda do |*args|
          captured_sources = args.drop(4)
          captured_contents = captured_sources.map { |path| File.read(path, mode: "r:utf-8") }
          ["588E\n", "", status]
        end) do
          missing = compiler.send(
            :missing_codepoints_for_fallback,
            File.join(JPMD::Compiler::APP_ROOT, "vendor", "fonts", "msmincho.ttc"),
            File.join(JPMD::Compiler::APP_ROOT, "vendor", "fonts", "PMingLiU.ttf")
          )

          assert_equal [0x588E], missing
        end
      end

      assert_equal ["source-0.md"], captured_sources.map { |path| File.basename(path) }
      refute_equal input_path, captured_sources.first
      assert_equal [[0x588E].pack("U*")], captured_contents
    end
  end

  def test_pmingliu_source_can_use_windows_collection_font
    with_temp_markdown("三九歲\n") do |input_path, config_path|
      Dir.mktmpdir("jpmd-fonts-") do |font_dir|
        File.write(File.join(font_dir, "mingliu.ttc"), "", mode: "wb")
        compiler = compiler_for(input_path, config_path)
        previous = ENV["JPMD_WINDOWS_FONT_DIR"]
        ENV["JPMD_WINDOWS_FONT_DIR"] = font_dir

        compiler.stub(:windows?, true) do
          compiler.stub(:resolve_pmingliu_file, nil) do
            source = compiler.send(:resolve_pmingliu_source)

            assert_equal File.join(font_dir, "mingliu.ttc"), source.fetch(:probe_path)
            assert_equal "PMingLiU", source.fetch(:font)
            refute source.key?(:path)
          end
        end
      ensure
        ENV["JPMD_WINDOWS_FONT_DIR"] = previous
      end
    end
  end

  def test_pmingliu_altfont_entries_can_render_family_font
    with_temp_markdown("三九歲\n") do |input_path, config_path|
      compiler = compiler_for(input_path, config_path)
      source = {
        probe_path: File.join(JPMD::Compiler::APP_ROOT, "vendor", "fonts", "PMingLiU.ttf"),
        font: "PMingLiU"
      }

      compiler.stub(:missing_codepoints_for_fallback, [0x6B72]) do
        entries = compiler.send(:pmingliu_altfont_entries, "msmincho.ttc", source)

        assert_equal 1, entries.length
        assert_includes entries.first, 'Range={"6B72}'
        assert_includes entries.first, "Font={PMingLiU}"
        assert_includes entries.first, "TateFont={PMingLiU}"
        refute_includes entries.first, "Path="
      end
    end
  end

  def test_render_ms_mincho_family_setup_keeps_altfont_entries
    with_temp_markdown("三九歲\n") do |input_path, config_path|
      compiler = compiler_for(input_path, config_path)
      setup = compiler.send(
        :render_ms_mincho_family_setup,
        "MS Mincho",
        altfont_entries: ['Range={"6B72},Font={PMingLiU},TateFont={PMingLiU}']
      )

      assert_includes setup, "AltFont={"
      assert_includes setup, "Font={PMingLiU}"
    end
  end

  def test_resolve_font_setup_explains_missing_fonts
    with_temp_markdown do |input_path, config_path|
      compiler = compiler_for(input_path, config_path)

      compiler.stub(:windows?, false) do
        compiler.stub(:resolve_times_new_roman_files, nil) do
          compiler.stub(:resolve_ms_mincho_file, nil) do
            compiler.stub(:font_family_available?, false) do
              error = assert_raises(JPMD::CommandError) { compiler.send(:resolve_font_setup) }
              assert_match(/Missing required fonts/, error.message)
              assert_match(/JPMD_WINDOWS_FONT_DIR/, error.message)
              assert_match(/JPMD_MS_MINCHO/, error.message)
            end
          end
        end
      end
    end
  end

  def test_render_template_adds_tate_class_option_for_linear_preset
    with_temp_markdown({ "preset" => "linear" }) do |input_path, config_path|
      compiler = JPMD::Compiler.new(
        input_path: input_path,
        config_path: config_path
      )

      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))

      template = compiler.send(:render_template)
      assert_includes template, "\\documentclass["
      assert_includes template, ",tate,"
    end
  end

  def test_render_metadata_exposes_tate_writing_mode_for_filter
    with_temp_markdown({ "preset" => "linear" }) do |input_path, config_path|
      compiler = JPMD::Compiler.new(
        input_path: input_path,
        config_path: config_path
      )

      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))

      metadata = compiler.send(:render_metadata, "/tmp/preamble.tex")
      assert_includes metadata, "jpmd-writing-mode: tate"
    end
  end

  def test_pandoc_input_format_disables_yaml_metadata_blocks
    Dir.mktmpdir("jpmd-pandoc-format-") do |dir|
      input_path = File.join(dir, "input.md")
      config_path = File.join(dir, "jpmd.yml")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        <!-- comment -->

        ## Heading

        Paragraph

        ---

        More text
      MARKDOWN
      File.write(config_path, "default_preset: academic\n", mode: "w:utf-8")

      compiler = compiler_for(input_path, config_path)
      assert_equal "markdown+bracketed_spans-yaml_metadata_block", compiler.send(:pandoc_input_format)
    end
  end

  def test_pandoc_input_content_strips_yaml_frontmatter_before_pandoc
    Dir.mktmpdir("jpmd-pandoc-format-") do |dir|
      input_path = File.join(dir, "input.md")
      config_path = File.join(dir, "jpmd.yml")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        bibliography: refs.json
        ---

        # Heading
      MARKDOWN
      File.write(config_path, "default_preset: academic\n", mode: "w:utf-8")

      compiler = compiler_for(input_path, config_path)
      assert_equal "# Heading\n", compiler.send(:pandoc_input_content)
    end
  end

  def test_pandoc_input_content_removes_standalone_dash_rules_from_body
    Dir.mktmpdir("jpmd-pandoc-format-") do |dir|
      input_path = File.join(dir, "input.md")
      config_path = File.join(dir, "jpmd.yml")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        first

        ---
        ### heading

        second
      MARKDOWN
      File.write(config_path, "default_preset: academic\n", mode: "w:utf-8")

      compiler = compiler_for(input_path, config_path)
      assert_equal "first\n\n### heading\n\nsecond\n", compiler.send(:pandoc_input_content)
    end
  end

  def test_render_metadata_merges_document_frontmatter_except_jpmd
    Dir.mktmpdir("jpmd-pandoc-format-") do |dir|
      input_path = File.join(dir, "input.md")
      config_path = File.join(dir, "jpmd.yml")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        title: Sample Title
        subtitle: Sample Subtitle
        author:
          - Sample Author
        institute:
          - Department
          - sample@example.jp
        bibliography: refs.json
        csl: refs.csl
        suppress-bibliography: true
        header-includes:
          - \\foo
        jpmd:
          preset: academic
        ---

        # Heading
      MARKDOWN
      File.write(config_path, "default_preset: academic\n", mode: "w:utf-8")

      compiler = compiler_for(input_path, config_path)
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))

      metadata = YAML.safe_load(compiler.send(:render_metadata, "/tmp/preamble.tex"))
      assert_equal "Sample Title", metadata["title"]
      assert_equal "Sample Subtitle", metadata["subtitle"]
      assert_equal ["Sample Author"], metadata["author"]
      assert_equal ["Department", "sample@example.jp"], metadata["institute"]
      assert_equal File.join(dir, "refs.json"), metadata["bibliography"]
      assert_equal File.join(dir, "refs.csl"), metadata["csl"]
      assert_equal true, metadata["suppress-bibliography"]
      assert_equal ["\\foo", "\\input{/tmp/preamble.tex}"], metadata["header-includes"]
      refute_includes metadata.keys, "jpmd"
    end
  end

  def test_render_metadata_uses_default_csl_when_document_does_not_specify_one
    with_temp_markdown do |input_path, config_path|
      compiler = compiler_for(input_path, config_path)
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))
      compiler.instance_variable_set(:@config, resolved)

      metadata = YAML.safe_load(compiler.send(:render_metadata, "/tmp/preamble.tex"))

      assert_equal File.join(JPMD::Compiler::APP_ROOT, "references", "word-japanese-note.csl"), metadata.fetch("csl")
    end
  end

  def test_render_metadata_applies_cli_metadata_overrides
    Dir.mktmpdir("jpmd-metadata-overrides-") do |dir|
      input_path = File.join(dir, "input.md")
      config_path = File.join(dir, "jpmd.yml")
      cli_refs_path = File.join(dir, "cli-refs.json")
      cli_csl_path = File.join(dir, "cli-style.csl")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        bibliography: document-refs.json
        csl: document-style.csl
        suppress-bibliography: false
        ---

        # Heading
      MARKDOWN
      File.write(config_path, "default_preset: academic\n", mode: "w:utf-8")

      compiler = JPMD::Compiler.new(
        input_path: input_path,
        config_path: config_path,
        metadata_overrides: {
          "bibliography" => [cli_refs_path],
          "csl" => cli_csl_path,
          "suppress-bibliography" => true
        }
      )
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))
      compiler.instance_variable_set(:@config, resolved)

      metadata = YAML.safe_load(compiler.send(:render_metadata, "/tmp/preamble.tex"))

      assert_equal [cli_refs_path], metadata["bibliography"]
      assert_equal cli_csl_path, metadata["csl"]
      assert_equal true, metadata["suppress-bibliography"]
    end
  end

  def test_render_metadata_uses_temporary_bibliography_with_japanese_date_literals
    Dir.mktmpdir("jpmd-bibliography-") do |dir|
      input_path = File.join(dir, "input.md")
      config_path = File.join(dir, "jpmd.yml")
      refs_path = File.join(dir, "refs.json")

      File.write(refs_path, <<~JSON, mode: "w:utf-8")
        [
          {
            "id": "book2008",
            "type": "book",
            "title": "Sample Book",
            "issued": { "date-parts": [[2008]] }
          },
          {
            "id": "article1996",
            "type": "article-journal",
            "title": "Sample Article",
            "issued": { "date-parts": [[1996, 3, 12]] }
          }
        ]
      JSON
      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        bibliography: refs.json
        ---

        # Heading
      MARKDOWN
      File.write(config_path, "default_preset: academic\n", mode: "w:utf-8")

      compiler = compiler_for(input_path, config_path)
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))
      compiler.instance_variable_set(:@config, resolved)

      metadata = YAML.safe_load(compiler.send(:render_metadata, "/tmp/preamble.tex", tmpdir: dir))
      converted = JSON.parse(File.read(metadata.fetch("bibliography"), mode: "r:utf-8"))

      refute_equal refs_path, metadata.fetch("bibliography")
      assert_equal({ "literal" => "二〇〇八年" }, converted[0].fetch("issued"))
      assert_equal({ "literal" => "一九九六年三月" }, converted[1].fetch("issued"))
      assert_includes File.read(refs_path, mode: "r:utf-8"), '"date-parts": [[1996, 3, 12]]'
    end
  end

  def test_render_metadata_merges_top_level_metadata_from_outsourced_yaml
    Dir.mktmpdir("jpmd-pandoc-format-") do |dir|
      settings_path = File.join(dir, "settings.yml")
      input_path = File.join(dir, "input.md")
      config_path = File.join(dir, "jpmd.yml")
      File.write(config_path, "{}\n", mode: "w:utf-8")
      File.write(settings_path, <<~YAML, mode: "w:utf-8")
        bibliography: refs.json
        csl: refs.csl
        preset: academic
      YAML
      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        title: Outsourced Metadata Fixture
        jpmd:
          config: settings.yml
        ---

        # Heading
      MARKDOWN

      compiler = compiler_for(input_path, config_path)
      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))

      metadata = YAML.safe_load(compiler.send(:render_metadata, "/tmp/preamble.tex"))
      assert_equal "Outsourced Metadata Fixture", metadata["title"]
      assert_equal File.join(dir, "refs.json"), metadata["bibliography"]
      assert_equal File.join(dir, "refs.csl"), metadata["csl"]
      refute_includes metadata.keys, "jpmd"
    end
  end

  def test_build_only_writes_requested_pdf
    with_temp_markdown do |input_path, config_path|
      Dir.mktmpdir("jpmd-transfer-") do |dir|
        output_path = File.join(File.dirname(config_path), "out", "sample.pdf")
        copied_paths = []
        original_copy = FileUtils.method(:cp)
        compiler = JPMD::Compiler.new(
          input_path: input_path,
          config_path: config_path
        )

        compiler.stub(:render_template, "template") do
          compiler.stub(:render_preamble, "preamble") do
            compiler.stub(:render_metadata, "---\n") do
              compiler.stub(:run_pandoc, lambda { |input_path:, template_path:, metadata_path:, tex_path:|
                assert File.file?(input_path)
                File.write(tex_path, "tex", mode: "w:utf-8")
              }) do
                compiler.stub(:run_lualatex, lambda { |tex_path, _workdir|
                  File.write(tex_path.sub(/\.tex\z/, ".pdf"), "pdf", mode: "wb")
                }) do
                  FileUtils.stub(:cp, lambda { |source, destination|
                    copied_paths << destination
                    original_copy.call(source, destination)
                  }) do
                    compiler.build
                  end
                end
              end
            end
          end
        end

        assert_equal "pdf", File.binread(output_path)
        assert_equal [output_path], copied_paths
      end
    end
  end

  def test_build_allows_custom_output_directory
    with_temp_markdown do |input_path, config_path|
      Dir.mktmpdir("jpmd-transfer-") do |dir|
        transfer_dir = File.join(dir, "transfer")
        output_path = File.join(transfer_dir, "sample.pdf")
        compiler = JPMD::Compiler.new(
          input_path: input_path,
          output_path: output_path,
          config_path: config_path
        )

        compiler.stub(:render_template, "template") do
          compiler.stub(:render_preamble, "preamble") do
            compiler.stub(:render_metadata, "---\n") do
              compiler.stub(:run_pandoc, lambda { |input_path:, template_path:, metadata_path:, tex_path:|
                assert File.file?(input_path)
                File.write(tex_path, "tex", mode: "w:utf-8")
              }) do
                compiler.stub(:run_lualatex, lambda { |tex_path, _workdir|
                  File.write(tex_path.sub(/\.tex\z/, ".pdf"), "pdf", mode: "wb")
                }) do
                  assert_equal output_path, compiler.build
                end
              end
            end
          end
        end

        assert_equal "pdf", File.binread(output_path)
      end
    end
  end

  def test_template_uses_list_based_csl_references_environment
    template = File.read(File.join(JPMD::Compiler::APP_ROOT, "template.tex"), mode: "r:utf-8")

    assert_match(/\\newenvironment\{CSLReferences\}\[2\].*?\\begin\{list\}/m, template)
    assert_match(/\\newenvironment\{CSLReferences\}\[2\].*?\\setlength\{\\leftmargin\}\{\\cslhangindent\}/m, template)
    assert_match(/\\newenvironment\{CSLReferences\}\[2\].*?\\setlength\{\\itemindent\}\{-1\\cslhangindent\}/m, template)
    assert_match(/\\newenvironment\{CSLReferences\}\[2\].*?\\setlength\{\\itemsep\}\{#2\\baselineskip\}/m, template)
  end

  def test_template_indents_block_quotes_by_two_japanese_characters
    template = File.read(File.join(JPMD::Compiler::APP_ROOT, "template.tex"), mode: "r:utf-8")

    assert_match(/\\renewenvironment\{quote\}.*?\\leftmargin=\\dimexpr\\jlreq@quote@indent\\relax/m, template)
    assert_match(/\\renewenvironment\{quote\}.*?\\rightmargin=\\dimexpr\\jlreq@quote@end@indent\\relax/m, template)
    refute_match(/\\renewenvironment\{quote\}.*?\\divide\\@tempdimb/m, template)
  end

  def test_template_renders_custom_yaml_title_block
    template = File.read(File.join(JPMD::Compiler::APP_ROOT, "template.tex"), mode: "r:utf-8")

    assert_includes template, "{\\fontsize{14pt}{14pt}\\selectfont\\bfseries $title$\\par}"
    assert_includes template, "{\\normalsize $subtitle$\\par}"
    refute_includes template, "\\vspace{0.5\\baselineskip}"
    assert_includes template, "\\begin{flushright}"
    assert_match(/\$for\(institute\)\$\$institute\$\\\\\n\$endfor\$\n\$for\(author\)\$\$author\$\\\\/m, template)
    refute_includes template, "\\maketitle"
  end

  def test_render_preamble_loads_kanbun_package_for_tate_mode
    with_temp_markdown({ "preset" => "linear" }) do |input_path, config_path|
      compiler = JPMD::Compiler.new(
        input_path: input_path,
        config_path: config_path
      )

      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))

      compiler.stub(:resolve_font_setup, { latin: "\\setmainfont{Times New Roman}", japanese: "\\setmainjfont{MS Mincho}" }) do
        preamble = compiler.send(:render_preamble)
        assert_includes preamble, "\\usepackage["
        assert_includes preamble, "]{kanbun}"
        assert_includes preamble, "unit=1\\zw"
        assert_includes preamble, "\\newcommand{\\kanbun}[4]"
      end
    end
  end

  def test_render_preamble_formats_nested_headings_for_academic_mode
    with_temp_markdown do |input_path, config_path|
      compiler = JPMD::Compiler.new(
        input_path: input_path,
        config_path: config_path
      )

      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))

      compiler.stub(:resolve_font_setup, { latin: "\\setmainfont{Times New Roman}", japanese: "\\setmainjfont{MS Mincho}" }) do
        preamble = compiler.send(:render_preamble)
        assert_includes preamble, "\\titleformat{\\subsection}"
        assert_includes preamble, "\\titleformat{\\subsubsection}"
        assert_includes preamble, "\\titleformat{\\paragraph}{\\normalfont\\bfseries}"
        assert_includes preamble, "\\usepackage{indentfirst}"
        assert_includes preamble, "\\setlength{\\parindent}{1\\zw}"
        refute_includes preamble, "\\titleformat{\\paragraph}[runin]"
      end
    end
  end

  def test_render_preamble_can_disable_academic_page_numbers
    with_temp_markdown({ "layout" => { "page_numbers" => false } }) do |input_path, config_path|
      compiler = JPMD::Compiler.new(
        input_path: input_path,
        config_path: config_path
      )

      resolved = JPMD::Config.new(
        input_path: input_path,
        config_path: config_path
      ).resolve
      compiler.instance_variable_set(:@settings, resolved.fetch("settings"))
      compiler.instance_variable_set(:@derived, resolved.fetch("derived"))

      compiler.stub(:resolve_font_setup, { latin: "\\setmainfont{Times New Roman}", japanese: "\\setmainjfont{MS Mincho}" }) do
        preamble = compiler.send(:render_preamble)
        assert_includes preamble, "\\pagestyle{fancy}"
        refute_includes preamble, "\\thepage"
      end
    end
  end

  private

  def compiler_for(input_path, config_path)
    JPMD::Compiler.new(
      input_path: input_path,
      config_path: config_path
    )
  end
end
