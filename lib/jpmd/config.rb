# frozen_string_literal: true

require "yaml"

module JPMD
  class Config
    APP_ROOT = File.expand_path("../..", __dir__)
    A4_WIDTH_PT = 210.0 * 72.27 / 25.4
    A4_HEIGHT_PT = 297.0 * 72.27 / 25.4

    BUILTIN_PRESETS = {
      "academic" => {
        "layout" => {
          "writing_mode" => "yoko",
          "margins" => {
            "top" => "3cm",
            "right" => "3cm",
            "bottom" => "2cm",
            "left" => "3cm"
          },
          "grid" => {
            "characters_per_line" => 35,
            "lines_per_page" => 30
          },
          "font" => {
            "body_size" => "12pt"
          },
          "paragraph" => {
            "first_line_indent" => "1zw"
          }
        },
        "kanbun" => {
          "side" => {
            "gap" => "0.10zw",
            "min_width" => "0.35zw"
          },
          "furigana" => {
            "size" => "7pt",
            "shift" => {
              "up" => "0pt",
              "right" => "0pt",
              "down" => "0pt",
              "left" => "0pt"
            }
          },
          "kaeriten" => {
            "size" => "7pt",
            "shift" => {
              "up" => "0pt",
              "right" => "0pt",
              "down" => "0.35ex",
              "left" => "0pt"
            }
          },
          "okurigana" => {
            "size" => "7pt",
            "shift" => {
              "up" => "0pt",
              "right" => "0pt",
              "down" => "0pt",
              "left" => "0pt"
            }
          }
        }
      },
      "linear" => {
        "layout" => {
          "writing_mode" => "tate",
          "margins" => {
            "top" => "2.0cm",
            "right" => "2.2cm",
            "bottom" => "2.0cm",
            "left" => "2.2cm"
          },
          "grid" => {
            "characters_per_line" => 24,
            "lines_per_page" => 11
          },
          "font" => {
            "body_size" => "14pt"
          },
          "paragraph" => {
            "first_line_indent" => "1zw"
          }
        },
        "kanbun" => {
          "kumi" => "beta",
          "tateaki" => 1,
          "okuriintrusion" => 1,
          "side" => {
            "gap" => "0.18zw",
            "min_width" => "0.90zw"
          },
          "furigana" => {
            "size" => "8pt",
            "shift" => {
              "up" => "0pt",
              "right" => "0.20zw",
              "down" => "0pt",
              "left" => "0pt"
            }
          },
          "kaeriten" => {
            "size" => "8pt",
            "shift" => {
              "up" => "0pt",
              "right" => "0.20zw",
              "down" => "0.20zw",
              "left" => "0pt"
            }
          },
          "okurigana" => {
            "size" => "8pt",
            "shift" => {
              "up" => "0pt",
              "right" => "0.20zw",
              "down" => "0.10zw",
              "left" => "0pt"
            }
          }
        }
      }
    }.freeze

    PROJECT_DEFAULTS = {
      "default_preset" => "academic",
      "default_csl" => File.join(APP_ROOT, "references", "word-japanese-note.csl"),
      "presets" => {}
    }.freeze

    PHYSICAL_UNIT_FACTORS = {
      "pt" => 1.0,
      "mm" => 72.27 / 25.4,
      "cm" => 72.27 / 2.54,
      "in" => 72.27
    }.freeze

    PHYSICAL_DIMENSION_PATTERN = /\A(0|[0-9]+(?:\.[0-9]+)?)(pt|mm|cm|in)\z/
    GENERIC_DIMENSION_PATTERN = /\A(0|[0-9]+(?:\.[0-9]+)?)(pt|mm|cm|in|bp|dd|cc|sp|ex|em|zw|zh)\z/
    WRITING_MODES = %w[yoko tate].freeze

    def initialize(input_path:, config_path:, cli_preset: nil)
      @input_path = input_path
      @config_path = config_path
      @cli_preset = cli_preset
    end

    def resolve
      project_config = load_project_config
      document_config = load_document_config
      reject_writing_mode_option!(document_config, "jpmd.layout.writing_mode")
      reject_project_writing_mode_options!(project_config)

      output = resolve_output_settings(document_config.delete("output"))
      csl = resolve_csl_path(document_config.delete("csl"), project_config["default_csl"])

      preset_name = @cli_preset ||
        string_or_nil(document_config.delete("preset")) ||
        string_or_nil(project_config["default_preset"]) ||
        PROJECT_DEFAULTS["default_preset"]

      builtin_preset = BUILTIN_PRESETS[preset_name]
      raise JPMD::ValidationError, "Unknown preset: #{preset_name}" unless builtin_preset

      project_preset = hash_at(project_config, "presets", preset_name) || {}
      merged = deep_merge(builtin_preset, project_preset)
      merged = deep_merge(merged, document_config)

      {
        "preset_name" => preset_name,
        "project_root" => project_root,
        "settings" => merged,
        "derived" => validate_and_derive(merged),
        "output" => output,
        "csl" => csl
      }
    end

    private

    def load_project_config
      config_hash =
        if File.file?(@config_path)
          normalize_hash(load_yaml_file(@config_path))
        else
          {}
        end

      deep_merge(PROJECT_DEFAULTS, config_hash)
    end

    def load_document_config
      metadata = JPMD::DocumentMetadata.load(@input_path)

      jpmd_metadata = metadata.fetch("jpmd", {})
      return {} if jpmd_metadata.nil?

      raise JPMD::ValidationError, "jpmd frontmatter in #{@input_path} must decode to a mapping" unless jpmd_metadata.is_a?(Hash)

      normalize_hash(jpmd_metadata)
    end

    def load_yaml_file(path)
      content = File.read(path, mode: "r:utf-8")
      JPMD.safe_yaml_load(content)
    rescue Psych::SyntaxError => e
      raise JPMD::ValidationError, "Invalid YAML in #{path}: #{e.message}"
    end

    def resolve_output_settings(value)
      output = value || {}
      raise JPMD::ValidationError, "jpmd.output must be a map" unless output.is_a?(Hash)

      output = normalize_hash(output)

      {
        "pdf_path" => resolve_output_path(output["pdf"]) || default_pdf_output_path,
        "tex_path" => resolve_output_path(output["tex"])
      }
    end

    def resolve_csl_path(document_value, project_value)
      value = document_value || project_value
      return nil if value.nil?

      path = required_string(value, "csl path")
      File.expand_path(path, project_root)
    end

    def resolve_output_path(value)
      return nil if value.nil?

      path = required_string(value, "jpmd.output path")
      File.expand_path(path, File.dirname(@input_path))
    end

    def default_pdf_output_path
      File.join(project_root, "out", "#{File.basename(@input_path, File.extname(@input_path))}.pdf")
    end

    def validate_and_derive(settings)
      layout = fetch_hash(settings, "layout")
      margins = fetch_hash(layout, "margins")
      grid = fetch_hash(layout, "grid")
      font = fetch_hash(layout, "font")
      paragraph = fetch_hash(layout, "paragraph")
      kanbun = fetch_hash(settings, "kanbun")
      writing_mode = resolve_writing_mode(layout["writing_mode"])

      top_pt = parse_physical_dimension(fetch_required(margins, "top"), "layout.margins.top")
      right_pt = parse_physical_dimension(fetch_required(margins, "right"), "layout.margins.right")
      bottom_pt = parse_physical_dimension(fetch_required(margins, "bottom"), "layout.margins.bottom")
      left_pt = parse_physical_dimension(fetch_required(margins, "left"), "layout.margins.left")
      body_size_pt = parse_physical_dimension(fetch_required(font, "body_size"), "layout.font.body_size")

      characters_per_line = parse_positive_integer(fetch_required(grid, "characters_per_line"), "layout.grid.characters_per_line", minimum: 2)
      lines_per_page = parse_positive_integer(fetch_required(grid, "lines_per_page"), "layout.grid.lines_per_page", minimum: 1)
      page_numbers = parse_boolean(layout.fetch("page_numbers", writing_mode != "tate"), "layout.page_numbers")
      first_line_indent = fetch_required(paragraph, "first_line_indent")
      validate_non_negative_dimension(first_line_indent, "layout.paragraph.first_line_indent")

      validate_kanbun_dimensions(kanbun)

      text_width_pt = A4_WIDTH_PT - left_pt - right_pt
      text_height_pt = A4_HEIGHT_PT - top_pt - bottom_pt

      raise JPMD::ValidationError, "Margins leave no usable text width on A4 paper" unless text_width_pt.positive?
      raise JPMD::ValidationError, "Margins leave no usable text height on A4 paper" unless text_height_pt.positive?

      line_length_pt, line_progression_pt =
        if writing_mode == "tate"
          [text_height_pt, text_width_pt]
        else
          [text_width_pt, text_height_pt]
        end

      kanjiskip_pt = (line_length_pt - (characters_per_line * body_size_pt)) / (characters_per_line - 1)
      raise JPMD::ValidationError, "Layout requires negative kanjiskip; reduce font size, widen the text block, or lower characters_per_line" if kanjiskip_pt.negative?

      baselineskip_pt = line_progression_pt / lines_per_page
      raise JPMD::ValidationError, "Layout requires nonpositive baselineskip" unless baselineskip_pt.positive?

      {
        "writing_mode" => writing_mode,
        "characters_per_line" => characters_per_line,
        "lines_per_page" => lines_per_page,
        "body_size" => fetch_required(font, "body_size"),
        "page_numbers" => page_numbers,
        "first_line_indent" => first_line_indent,
        "kanjiskip_pt" => kanjiskip_pt,
        "baselineskip_pt" => baselineskip_pt
      }
    end

    def validate_kanbun_dimensions(kanbun)
      side = fetch_hash(kanbun, "side")
      validate_non_negative_dimension(fetch_required(side, "gap"), "kanbun.side.gap")
      validate_non_negative_dimension(fetch_required(side, "min_width"), "kanbun.side.min_width")

      %w[furigana kaeriten okurigana].each do |name|
        annotation = fetch_hash(kanbun, name)
        validate_positive_dimension(fetch_required(annotation, "size"), "kanbun.#{name}.size")
        shift = fetch_hash(annotation, "shift")

        %w[up right down left].each do |direction|
          validate_non_negative_dimension(fetch_required(shift, direction), "kanbun.#{name}.shift.#{direction}")
        end
      end
    end

    def reject_project_writing_mode_options!(project_config)
      presets = project_config["presets"]
      return unless presets.is_a?(Hash)

      presets.each do |preset_name, preset|
        next unless preset.is_a?(Hash)

        reject_writing_mode_option!(preset, "presets.#{preset_name}.layout.writing_mode")
      end
    end

    def reject_writing_mode_option!(config, path)
      return unless config.is_a?(Hash)

      layout = config["layout"]
      return unless layout.is_a?(Hash) && layout.key?("writing_mode")

      raise JPMD::ValidationError, "#{path} is no longer configurable; use the default horizontal writing mode"
    end

    def parse_physical_dimension(value, path)
      string = string_or_nil(value)
      match = string&.match(PHYSICAL_DIMENSION_PATTERN)
      raise JPMD::ValidationError, "#{path} must be a dimension in pt, mm, cm, or in" unless match

      number = match[1].to_f
      raise JPMD::ValidationError, "#{path} must be positive" unless number.positive?

      number * PHYSICAL_UNIT_FACTORS.fetch(match[2])
    end

    def validate_positive_dimension(value, path)
      string = string_or_nil(value)
      match = string&.match(GENERIC_DIMENSION_PATTERN)
      raise JPMD::ValidationError, "#{path} must be a TeX dimension" unless match
      raise JPMD::ValidationError, "#{path} must be positive" unless match[1].to_f.positive?
    end

    def validate_non_negative_dimension(value, path)
      string = string_or_nil(value)
      match = string&.match(GENERIC_DIMENSION_PATTERN)
      raise JPMD::ValidationError, "#{path} must be a TeX dimension" unless match
      raise JPMD::ValidationError, "#{path} must be nonnegative" if match[1].to_f.negative?
    end

    def parse_positive_integer(value, path, minimum:)
      parsed =
        case value
        when Integer
          value
        when String
          Integer(value, exception: false)
        end

      raise JPMD::ValidationError, "#{path} must be an integer" unless parsed
      raise JPMD::ValidationError, "#{path} must be at least #{minimum}" unless parsed >= minimum

      parsed
    end

    def parse_boolean(value, path)
      return value if value == true || value == false

      raise JPMD::ValidationError, "#{path} must be true or false"
    end

    def normalize_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), hash|
          hash[key.to_s] = normalize_hash(nested_value)
        end
      when Array
        value.map { |item| normalize_hash(item) }
      else
        value
      end
    end

    def resolve_writing_mode(value)
      mode = string_or_nil(value) || "yoko"
      raise JPMD::ValidationError, "Internal preset writing mode must be one of: #{WRITING_MODES.join(", ")}" unless WRITING_MODES.include?(mode)

      mode
    end

    def deep_merge(base, override)
      merged = normalize_hash(base)

      normalize_hash(override).each do |key, value|
        merged[key] =
          if merged[key].is_a?(Hash) && value.is_a?(Hash)
            deep_merge(merged[key], value)
          else
            value
          end
      end

      merged
    end

    def fetch_hash(hash, key)
      value = fetch_required(hash, key)
      raise JPMD::ValidationError, "#{key} must be a map" unless value.is_a?(Hash)

      value
    end

    def fetch_required(hash, key)
      raise JPMD::ValidationError, "Missing required key: #{key}" unless hash.key?(key)

      hash[key]
    end

    def hash_at(hash, *keys)
      keys.reduce(hash) do |memo, key|
        return nil unless memo.is_a?(Hash)

        memo[key]
      end
    end

    def string_or_nil(value)
      value.nil? ? nil : value.to_s
    end

    def required_string(value, path)
      raise JPMD::ValidationError, "#{path} must be a string" unless value.is_a?(String)
      raise JPMD::ValidationError, "#{path} must not be empty" if value.strip.empty?

      value
    end

    def project_root
      File.expand_path(File.dirname(@config_path))
    end
  end
end
