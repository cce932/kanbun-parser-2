# frozen_string_literal: true

require "erb"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "tmpdir"
require "yaml"

module JPMD
  class Compiler
    WINDOWS_PANDOC = File.expand_path("~/AppData/Local/Pandoc/pandoc.exe")
    WINDOWS_LUALATEX = "C:/texlive/2025/bin/windows/lualatex.exe"
    APP_ROOT = File.expand_path("../..", __dir__)
    TIMES_NEW_ROMAN_ENV_VARS = {
      regular: "JPMD_TIMES_NEW_ROMAN_REGULAR",
      bold: "JPMD_TIMES_NEW_ROMAN_BOLD",
      italic: "JPMD_TIMES_NEW_ROMAN_ITALIC",
      bold_italic: "JPMD_TIMES_NEW_ROMAN_BOLD_ITALIC"
    }.freeze
    TIMES_NEW_ROMAN_FILENAMES = {
      regular: "times.ttf",
      bold: "timesbd.ttf",
      italic: "timesi.ttf",
      bold_italic: "timesbi.ttf"
    }.freeze
    MS_MINCHO_ENV_VAR = "JPMD_MS_MINCHO"
    MS_MINCHO_FILENAME = "msmincho.ttc"
    PMINGLIU_FILENAME = "PMingLiU.ttf"
    PMINGLIU_COLLECTION_FILENAME = "mingliu.ttc"

    def initialize(input_path:, output_path: nil, config_path:, preset_name: nil, emit_tex_path: nil, metadata_overrides: {})
      @input_path = File.expand_path(input_path)
      @output_path = output_path && File.expand_path(output_path)
      @config_path = File.expand_path(config_path)
      @preset_name = preset_name
      @emit_tex_path = emit_tex_path && File.expand_path(emit_tex_path)
      @metadata_overrides = normalize_metadata_overrides(metadata_overrides)
    end

    def build
      ensure_input_exists

      resolved = JPMD::Config.new(
        input_path: @input_path,
        config_path: @config_path,
        cli_preset: @preset_name
      ).resolve

      @config = resolved
      @settings = resolved.fetch("settings")
      @derived = resolved.fetch("derived")
      @output_path ||= resolved.fetch("output").fetch("pdf_path")
      @emit_tex_path ||= resolved.fetch("output").fetch("tex_path")

      FileUtils.mkdir_p(File.dirname(@output_path))
      FileUtils.mkdir_p(File.dirname(@emit_tex_path)) if @emit_tex_path

      Dir.mktmpdir("jpmd-") do |tmpdir|
        pandoc_input_path = prepare_pandoc_input(tmpdir)
        template_path = write_file(tmpdir, "template.tex", render_template)
        preamble_path = write_file(tmpdir, "preamble.tex", render_preamble)
        metadata_path = write_file(tmpdir, "metadata.yml", render_metadata(preamble_path, tmpdir: tmpdir))
        tex_basename = "#{File.basename(@output_path, ".pdf")}.tex"
        tex_path = File.join(tmpdir, tex_basename)

        run_pandoc(input_path: pandoc_input_path, template_path: template_path, metadata_path: metadata_path, tex_path: tex_path)
        FileUtils.cp(tex_path, @emit_tex_path) if @emit_tex_path

        2.times { run_lualatex(tex_path, tmpdir) }

        pdf_path = tex_path.sub(/\.tex\z/, ".pdf")
        raise JPMD::CommandError, "Expected PDF was not generated: #{pdf_path}" unless File.file?(pdf_path)

        FileUtils.cp(pdf_path, @output_path)
      end

      @output_path
    end

    private

    def ensure_input_exists
      raise JPMD::ValidationError, "Input file not found: #{@input_path}" unless File.file?(@input_path)
    end

    def render_template
      source = File.read(File.join(APP_ROOT, "template.tex"), mode: "r:utf-8")
      class_options = [
        "lualatex",
        "paper=a4",
        ("tate" if @derived.fetch("writing_mode") == "tate"),
        "fontsize=#{@derived.fetch("body_size")}",
        "jafontsize=#{@derived.fetch("body_size")}",
        "line_length=#{@derived.fetch("characters_per_line")}zw",
        "number_of_lines=#{@derived.fetch("lines_per_page")}",
        "baselineskip=#{format_pt(@derived.fetch("baselineskip_pt"))}"
      ].compact.join(",")

      rendered = source.sub(
        /\\documentclass\[[^\n]+\]\{jlreq\}/,
        "\\documentclass[#{class_options}]{jlreq}"
      )

      raise JPMD::CommandError, "Could not find jlreq documentclass line in template.tex" if rendered == source

      rendered
    end

    def render_preamble
      template = File.read(File.join(APP_ROOT, "templates", "preamble.tex.erb"), mode: "r:utf-8")
      layout = @settings.fetch("layout")
      kanbun = @settings.fetch("kanbun")
      font_setup = resolve_font_setup

      ERB.new(template, trim_mode: "-").result_with_hash(
        latin_font_setup: font_setup.fetch(:latin),
        japanese_font_setup: font_setup.fetch(:japanese),
        kanjiskip: format_pt(@derived.fetch("kanjiskip_pt")),
        furigana_size: tex_dimension(kanbun.fetch("furigana").fetch("size")),
        furigana_up: tex_dimension(kanbun.fetch("furigana").fetch("shift").fetch("up")),
        furigana_right: tex_dimension(kanbun.fetch("furigana").fetch("shift").fetch("right")),
        furigana_down: tex_dimension(kanbun.fetch("furigana").fetch("shift").fetch("down")),
        furigana_left: tex_dimension(kanbun.fetch("furigana").fetch("shift").fetch("left")),
        kaeriten_size: tex_dimension(kanbun.fetch("kaeriten").fetch("size")),
        kaeriten_up: tex_dimension(kanbun.fetch("kaeriten").fetch("shift").fetch("up")),
        kaeriten_right: tex_dimension(kanbun.fetch("kaeriten").fetch("shift").fetch("right")),
        kaeriten_down: tex_dimension(kanbun.fetch("kaeriten").fetch("shift").fetch("down")),
        kaeriten_left: tex_dimension(kanbun.fetch("kaeriten").fetch("shift").fetch("left")),
        okurigana_size: tex_dimension(kanbun.fetch("okurigana").fetch("size")),
        okurigana_up: tex_dimension(kanbun.fetch("okurigana").fetch("shift").fetch("up")),
        okurigana_right: tex_dimension(kanbun.fetch("okurigana").fetch("shift").fetch("right")),
        okurigana_down: tex_dimension(kanbun.fetch("okurigana").fetch("shift").fetch("down")),
        okurigana_left: tex_dimension(kanbun.fetch("okurigana").fetch("shift").fetch("left")),
        side_gap: tex_dimension(kanbun.fetch("side").fetch("gap")),
        side_min_width: tex_dimension(kanbun.fetch("side").fetch("min_width")),
        body_size: tex_dimension(layout.fetch("font").fetch("body_size")),
        writing_mode: @derived.fetch("writing_mode"),
        page_numbers: @derived.fetch("page_numbers"),
        tate_kanbun_kumi: kanbun.fetch("kumi", "beta"),
        tate_kanbun_tateaki: tate_kanbun_float(kanbun.fetch("tateaki", 1)),
        tate_kanbun_okuriintrusion: tate_kanbun_float(kanbun.fetch("okuriintrusion", 1)),
        tate_kanbun_scale: tate_kanbun_scale(layout.fetch("font").fetch("body_size"), kanbun.fetch("furigana").fetch("size"))
      )
    end

    def resolve_font_setup
      latin = resolve_latin_font_setup
      japanese = resolve_japanese_font_setup

      return { latin: latin, japanese: japanese } if latin && japanese

      missing = []
      missing << "Times New Roman" unless latin
      missing << "MS Mincho" unless japanese

      raise JPMD::CommandError, <<~TEXT.chomp
        Missing required fonts on this machine: #{missing.join(", ")}
        Keep the same fonts by either:
        - installing those exact fonts so LuaLaTeX can resolve the family names, or
        - setting JPMD_WINDOWS_FONT_DIR to a directory containing #{TIMES_NEW_ROMAN_FILENAMES.values.join(", ")} and #{MS_MINCHO_FILENAME}, or
        - setting #{TIMES_NEW_ROMAN_ENV_VARS.values.join(", ")}, and #{MS_MINCHO_ENV_VAR} to the exact font files
      TEXT
    end

    def resolve_latin_font_setup
      return "\\setmainfont{Times New Roman}" if windows?

      files = resolve_times_new_roman_files
      return render_times_new_roman_file_setup(files) if files
      return "\\setmainfont{Times New Roman}" if font_family_available?("Times New Roman")

      nil
    end

    def resolve_japanese_font_setup
      pmingliu = resolve_pmingliu_source
      file = resolve_ms_mincho_file
      return render_ms_mincho_file_setup(file, altfont_entries: pmingliu_altfont_entries(file, pmingliu)) if file
      family_probe_file = font_family_file("MS Mincho")
      family_entries = pmingliu_altfont_entries(family_probe_file, pmingliu)
      return render_ms_mincho_family_setup("MS Mincho", altfont_entries: family_entries) if windows?
      return render_ms_mincho_family_setup("MS Mincho", altfont_entries: family_entries) if font_family_available?("MS Mincho")

      nil
    end

    def resolve_times_new_roman_files
      explicit = TIMES_NEW_ROMAN_ENV_VARS.transform_values { |env_name| env_file(env_name) }
      return validate_explicit_times_new_roman_files(explicit) if explicit.values.any?

      font_dir_candidates.each do |dir|
        files = TIMES_NEW_ROMAN_FILENAMES.transform_values { |filename| File.join(dir, filename) }
        return files if files.values.all? { |path| File.file?(path) }
      end

      nil
    end

    def validate_explicit_times_new_roman_files(files)
      missing = files.select { |_style, path| path.nil? || !File.file?(path) }
      return files if missing.empty?

      missing_vars = missing.keys.map { |style| TIMES_NEW_ROMAN_ENV_VARS.fetch(style) }
      raise JPMD::CommandError, "Explicit Times New Roman font files are missing: #{missing_vars.join(", ")}"
    end

    def resolve_ms_mincho_file
      explicit = env_file(MS_MINCHO_ENV_VAR)
      return explicit if explicit && File.file?(explicit)
      raise JPMD::CommandError, "Explicit MS Mincho font file is missing: #{MS_MINCHO_ENV_VAR}" if explicit

      font_dir_candidates.each do |dir|
        path = File.join(dir, MS_MINCHO_FILENAME)
        return path if File.file?(path)
      end

      nil
    end

    def resolve_pmingliu_file
      font_dir_candidates.each do |dir|
        path = File.join(dir, PMINGLIU_FILENAME)
        return path if File.file?(path)
      end

      nil
    end

    def resolve_pmingliu_source
      file = resolve_pmingliu_file
      return pmingliu_file_source(file) if file

      collection = resolve_pmingliu_collection_file
      return pmingliu_collection_source(collection) if collection

      nil
    end

    def resolve_pmingliu_collection_file
      font_dir_candidates.each do |dir|
        path = File.join(dir, PMINGLIU_COLLECTION_FILENAME)
        return path if File.file?(path)
      end

      nil
    end

    def pmingliu_file_source(path)
      {
        probe_path: path,
        font: File.basename(path),
        path: "#{tex_path(File.dirname(path))}/"
      }
    end

    def pmingliu_family_source(probe_path)
      {
        probe_path: probe_path,
        font: "PMingLiU"
      }
    end

    def pmingliu_collection_source(path)
      return pmingliu_family_source(path) if windows? || font_family_available?("PMingLiU")

      pmingliu_file_source(path)
    end

    def render_times_new_roman_file_setup(files)
      dir = "#{tex_path(File.dirname(files.fetch(:regular)))}/"

      <<~TEX.chomp
        \\setmainfont[
          Path={#{dir}},
          UprightFont={#{File.basename(files.fetch(:regular))}},
          BoldFont={#{File.basename(files.fetch(:bold))}},
          ItalicFont={#{File.basename(files.fetch(:italic))}},
          BoldItalicFont={#{File.basename(files.fetch(:bold_italic))}}
        ]{}
      TEX
    end

    def render_ms_mincho_family_setup(font_name, altfont_entries: [])
      <<~TEX.chomp
        \\setmainjfont[
      #{indented_tex_options(ms_mincho_option_lines(bold_font: "MS Mincho", altfont_entries: altfont_entries))}
        ]{#{font_name}}
      TEX
    end

    def render_ms_mincho_file_setup(path, altfont_entries:)
      dir = "#{tex_path(File.dirname(path))}/"
      basename = File.basename(path)

      <<~TEX.chomp
        \\setmainjfont[
      #{indented_tex_options([
        "Path={#{dir}}",
        "UprightFont={#{basename}}",
        *ms_mincho_option_lines(bold_font: basename, altfont_entries: altfont_entries)
      ])}
        ]{}
      TEX
    end

    def ms_mincho_option_lines(bold_font:, altfont_entries:)
      options = [
        "BoldFont={#{bold_font}}",
        "BoldFeatures={FakeBold=2}"
      ]
      options << "AltFont={\n#{render_altfont_entries(altfont_entries)}\n          }" unless altfont_entries.empty?
      options
    end

    def indented_tex_options(options)
      options.map { |line| "          #{line}" }.join(",\n")
    end

    def render_altfont_entries(entries)
      entries.map { |entry| "            {#{entry}}" }.join(",\n")
    end

    def font_dir_candidates
      @font_dir_candidates ||= begin
        [
          File.join(APP_ROOT, "vendor", "fonts"),
          ENV["JPMD_WINDOWS_FONT_DIR"],
          (File.join(ENV["WINDIR"], "Fonts") if ENV["WINDIR"] && !ENV["WINDIR"].empty?),
          "C:/Windows/Fonts",
          "/mnt/c/Windows/Fonts",
          File.expand_path("~/AppData/Local/Microsoft/Windows/Fonts"),
          File.expand_path("~/.wine/drive_c/windows/Fonts")
        ].compact.reject(&:empty?).uniq.select { |path| File.directory?(path) }
      end
    end

    def font_family_available?(family_name)
      @font_family_names ||= begin
        stdout, status = Open3.capture2("fc-list", ":family")
        if status.success?
          stdout.lines.flat_map { |line| line.split(":").last.to_s.split(",") }.map(&:strip).reject(&:empty?).uniq
        else
          []
        end
      rescue Errno::ENOENT
        []
      end

      @font_family_names.include?(family_name)
    end

    def font_family_file(family_name)
      @font_family_files ||= {}
      return @font_family_files[family_name] if @font_family_files.key?(family_name)

      stdout, status = Open3.capture2("fc-match", "-f", "%{file}", family_name)
      path = stdout.strip
      @font_family_files[family_name] = status.success? && !path.empty? && File.file?(path) ? path : nil
    rescue Errno::ENOENT
      @font_family_files[family_name] = nil
    end

    def env_file(env_name)
      value = ENV[env_name]
      return nil if value.nil? || value.empty?

      File.expand_path(value)
    end

    def render_metadata(preamble_path, tmpdir: nil)
      margins = @settings.fetch("layout").fetch("margins")
      document_metadata = effective_document_metadata.dup
      document_metadata["csl"] ||= @config.fetch("csl", nil) if @config
      document_metadata = prepare_bibliography_metadata(document_metadata, tmpdir) if tmpdir
      header_includes = Array(document_metadata.delete("header-includes"))

      metadata = document_metadata.merge(
        "geometry" => [
          "top=#{margins.fetch("top")}",
          "bottom=#{margins.fetch("bottom")}",
          "left=#{margins.fetch("left")}",
          "right=#{margins.fetch("right")}"
        ],
        "jpmd-writing-mode" => @derived.fetch("writing_mode"),
        "header-includes" => header_includes + [
          "\\input{#{tex_path(preamble_path)}}"
        ]
      )

      YAML.dump(metadata)
    end

    def prepare_bibliography_metadata(metadata, tmpdir)
      bibliography = metadata["bibliography"]
      return metadata unless bibliography

      entries = bibliography.is_a?(Array) ? bibliography : [bibliography]
      converted_entries = entries.each_with_index.map do |entry, index|
        prepare_bibliography_entry(entry, tmpdir, index)
      end

      metadata.merge(
        "bibliography" => bibliography.is_a?(Array) ? converted_entries : converted_entries.first
      )
    end

    def prepare_bibliography_entry(entry, tmpdir, index)
      return entry unless entry.is_a?(String) && !entry.empty?

      path = expand_document_relative_path(entry)
      return entry unless File.file?(path) && File.extname(path).downcase == ".json"

      data = JSON.parse(File.read(path, mode: "r:utf-8"))
      converted = convert_bibliography_dates(data)
      output_path = File.join(tmpdir, "bibliography-#{index}.json")
      File.write(output_path, JSON.pretty_generate(converted), mode: "w:utf-8")
      output_path
    rescue JSON::ParserError
      entry
    end

    def convert_bibliography_dates(data)
      case data
      when Array
        data.map { |item| convert_bibliography_item_dates(item) }
      when Hash
        convert_bibliography_item_dates(data)
      else
        data
      end
    end

    def convert_bibliography_item_dates(item)
      return item unless item.is_a?(Hash)

      item.dup.tap do |converted|
        %w[issued accessed].each do |key|
          literal = japanese_date_literal(converted[key])
          converted[key] = { "literal" => literal } if literal
        end
      end
    end

    def japanese_date_literal(date)
      return nil unless date.is_a?(Hash)
      return nil if date["literal"]

      first_part = date["date-parts"]&.first
      return nil unless first_part.is_a?(Array)

      year = first_part[0]
      return nil if year.nil? || year.to_s.empty?

      month = first_part[1]
      literal = "#{kanji_digits(year)}年"
      literal += "#{kanji_month(month)}月" unless month.nil? || month.to_s.empty?
      literal
    end

    def kanji_digits(value)
      value.to_s.each_char.map do |char|
        case char
        when "0" then "〇"
        when "1" then "一"
        when "2" then "二"
        when "3" then "三"
        when "4" then "四"
        when "5" then "五"
        when "6" then "六"
        when "7" then "七"
        when "8" then "八"
        when "9" then "九"
        else char
        end
      end.join
    end

    def kanji_month(value)
      month = Integer(value.to_s, 10)
      case month
      when 1..9
        kanji_digits(month)
      when 10
        "十"
      when 11
        "十一"
      when 12
        "十二"
      else
        value.to_s
      end
    rescue ArgumentError
      value.to_s
    end

    def run_pandoc(input_path:, template_path:, metadata_path:, tex_path:)
      command = [
        resolve_pandoc,
        input_path,
        "-f", pandoc_input_format,
        "--standalone",
        "--citeproc",
        "--template", template_path,
        "--metadata-file", metadata_path,
        "--lua-filter", File.join(APP_ROOT, "filter.lua"),
        "-t", "latex",
        "-o", tex_path
      ]

      execute(command, chdir: APP_ROOT, failure_label: "Pandoc")
    end

    def pandoc_input_format
      "markdown+bracketed_spans-yaml_metadata_block"
    end

    def run_lualatex(tex_path, workdir)
      command = [
        resolve_lualatex,
        "-interaction=nonstopmode",
        "-halt-on-error",
        "-file-line-error",
        File.basename(tex_path)
      ]

      execute(command, chdir: workdir, failure_label: "LuaLaTeX")
    end

    def execute(command, chdir:, failure_label:)
      stdout, stderr, status = Open3.capture3(*command, chdir: chdir)
      return if status.success?

      output = [stdout, stderr].reject(&:empty?).join("\n")
      raise JPMD::CommandError, "#{failure_label} failed:\n#{output}"
    end

    def resolve_pandoc
      @pandoc_path ||= resolve_binary(
        env_name: "PANDOC_PATH",
        fallback_paths: [WINDOWS_PANDOC],
        command_name: "pandoc"
      )
    end

    def resolve_lualatex
      @lualatex_path ||= resolve_binary(
        env_name: "LUALATEX_PATH",
        fallback_paths: [WINDOWS_LUALATEX],
        command_name: "lualatex"
      )
    end

    def resolve_binary(env_name:, fallback_paths:, command_name:)
      explicit = ENV[env_name]
      return explicit if explicit && !explicit.empty? && File.exist?(explicit)

      fallback_paths.each do |path|
        return path if File.exist?(path)
      end

      locator = windows? ? "where.exe" : "which"
      stdout, status = Open3.capture2(locator, command_name)
      candidate = stdout.lines.first&.strip
      return candidate if status.success? && candidate && !candidate.empty?

      raise JPMD::CommandError, "Could not find #{command_name}; set #{env_name} or install it on PATH"
    end

    def write_file(dir, name, content)
      path = File.join(dir, name)
      File.write(path, content, mode: "w:utf-8")
      path
    end

    def prepare_pandoc_input(dir)
      write_file(dir, File.basename(@input_path), pandoc_input_content)
    end

    def pandoc_input_content
      content = File.read(@input_path, mode: "r:utf-8").sub(/\A\uFEFF/, "")
      content = content.sub(/\A---\s*\r?\n.*?\r?\n(?:---|\.\.\.)\s*(?:\r?\n|$)/m, "")
      content.lines.reject { |line| line.match?(/\A[ \t]*---[ \t]*(?:\r?\n)?\z/) }.join
    end

    def pmingliu_altfont_entries(primary_font_path, fallback_source)
      return [] unless primary_font_path && fallback_source

      codepoints = missing_codepoints_for_fallback(primary_font_path, fallback_source.fetch(:probe_path))
      return [] if codepoints.empty?

      range_literal = codepoint_range_literal(codepoints)
      fallback_font = fallback_source.fetch(:font)
      options = [
        "Range={#{range_literal}}",
        "Font={#{fallback_font}}"
      ]
      options << "Path={#{fallback_source.fetch(:path)}}" if fallback_source.key?(:path)
      options.concat([
        "TateFont={#{fallback_font}}",
        "YokoFeatures={JFM=jlreq}",
        "TateFeatures={JFM=jlreqv}"
      ])

      [options.join(",")]
    rescue JPMD::CommandError
      []
    end

    def missing_codepoints_for_fallback(primary_font_path, fallback_font_path)
      source_paths = [@input_path, *bibliography_source_paths].uniq.select { |path| File.file?(path) }
      return [] if source_paths.empty?

      script_path = write_font_coverage_script
      stdout = stderr = status = nil
      with_font_coverage_source_copies(source_paths) do |probe_paths|
        stdout, stderr, status = Open3.capture3(
          resolve_texlua,
          script_path,
          primary_font_path,
          fallback_font_path,
          *probe_paths
        )
      end
      return stdout.lines.map { |line| Integer(line.strip, 16) } if status.success?

      raise JPMD::CommandError, "texlua font coverage probe failed:\n#{[stdout, stderr].reject(&:empty?).join("\n")}"
    ensure
      FileUtils.rm_f(script_path) if script_path
    end

    def with_font_coverage_source_copies(source_paths)
      Dir.mktmpdir("jpmd-font-coverage-sources-") do |dir|
        probe_paths = source_paths.each_with_index.map do |path, index|
          extension = File.extname(path)
          destination = File.join(dir, "source-#{index}#{extension}")
          File.binwrite(destination, File.binread(path))
          destination
        end

        yield probe_paths
      end
    end

    def write_font_coverage_script
      file = Tempfile.new(["jpmd-font-coverage", ".lua"])
      file.write(<<~LUA)
        local function load_map(path, index)
          local font = fontloader.open(path, index or 0)
          if not font then
            io.stderr:write("open failed: " .. path .. "\\n")
            os.exit(2)
          end

          local tabled = fontloader.to_table(font)
          local map = tabled.map and tabled.map.map or {}
          fontloader.close(font)
          return map
        end

        local primary = load_map(arg[1], 0)
        local fallback = load_map(arg[2], 0)
        local seen = {}
        local missing = {}

        local function scan_file(path)
          local handle = io.open(path, "rb")
          if not handle then
            return
          end

          local content = handle:read("*a") or ""
          handle:close()

          for _, codepoint in utf8.codes(content) do
            if codepoint >= 0x80 and (not primary[codepoint]) and fallback[codepoint] and (not seen[codepoint]) then
              seen[codepoint] = true
              missing[#missing + 1] = codepoint
            end
          end
        end

        for index = 3, #arg do
          scan_file(arg[index])
        end

        table.sort(missing)
        for _, codepoint in ipairs(missing) do
          print(string.format("%X", codepoint))
        end
      LUA
      file.close
      file.path
    end

    def codepoint_range_literal(codepoints)
      contiguous_codepoint_ranges(codepoints).map do |start_codepoint, end_codepoint|
        if start_codepoint == end_codepoint
          tex_hex_codepoint(start_codepoint)
        else
          "#{tex_hex_codepoint(start_codepoint)}-#{tex_hex_codepoint(end_codepoint)}"
        end
      end.join(",")
    end

    def contiguous_codepoint_ranges(codepoints)
      codepoints.sort.each_with_object([]) do |codepoint, ranges|
        if ranges.empty? || codepoint > ranges.last.last + 1
          ranges << [codepoint, codepoint]
        else
          ranges.last[1] = codepoint
        end
      end
    end

    def tex_hex_codepoint(codepoint)
      format('"%X', codepoint)
    end

    def bibliography_source_paths
      bibliography = effective_document_metadata["bibliography"]
      Array(bibliography).filter_map do |entry|
        next unless entry.is_a?(String) && !entry.empty?

        expand_document_relative_path(entry)
      end
    end

    def expand_document_relative_path(path)
      return path if Pathname(path).absolute?

      File.expand_path(path, File.dirname(@input_path))
    end

    def resolve_texlua
      @texlua_path ||= begin
        lualatex_dir = File.dirname(resolve_lualatex)
        candidates = ["texlua", "texlua.exe"].map { |name| File.join(lualatex_dir, name) }
        candidate = candidates.find { |path| File.exist?(path) }
        if candidate
          candidate
        else
          locator = windows? ? "where.exe" : "which"
          stdout, status = Open3.capture2(locator, "texlua")
          discovered = stdout.lines.first&.strip
          if status.success? && discovered && !discovered.empty?
            discovered
          else
            raise JPMD::CommandError, "Could not find texlua to probe font coverage"
          end
        end
      end
    end

    def document_frontmatter_metadata
      JPMD::DocumentMetadata.load(@input_path).reject { |key, _value| key.to_s == "jpmd" }
    end

    def effective_document_metadata
      @effective_document_metadata ||= document_frontmatter_metadata.merge(@metadata_overrides)
    end

    def normalize_metadata_overrides(overrides)
      return {} if overrides.nil?

      overrides.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_s] = value
      end
    end

    def tex_path(path)
      Pathname(path).to_s.tr("\\", "/")
    end

    def format_pt(value)
      format("%.5fpt", value)
    end

    def tex_dimension(value)
      value.to_s.sub(/zw\z/, "\\\\zw").sub(/zh\z/, "\\\\zh")
    end

    def tate_kanbun_float(value)
      number = Float(value.to_s)
      format("%.3f", number).sub(/\.?0+\z/, "")
    rescue ArgumentError, TypeError
      "1"
    end

    def tate_kanbun_scale(body_size, furigana_size)
      body = parse_number_and_unit(body_size)
      ruby = parse_number_and_unit(furigana_size)
      return "2" unless body && ruby
      return "2" unless body.fetch(:unit) == ruby.fetch(:unit)
      return "2" unless ruby.fetch(:value).positive?

      format("%.3f", body.fetch(:value) / ruby.fetch(:value)).sub(/\.?0+\z/, "")
    end

    def parse_number_and_unit(value)
      match = value.to_s.match(/\A([0-9]+(?:\.[0-9]+)?)([A-Za-z]+)\z/)
      return nil unless match

      {
        value: match[1].to_f,
        unit: match[2]
      }
    end

    def windows?
      RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/i)
    end
  end
end
