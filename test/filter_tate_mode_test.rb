# frozen_string_literal: true

require "open3"
require_relative "test_helper"

class FilterTateModeTest < Minitest::Test
  def test_tate_mode_converts_annotated_paragraph_to_kanbun_block
    Dir.mktmpdir("jpmd-filter-") do |dir|
      input_path = File.join(dir, "sample.md")
      metadata_path = File.join(dir, "metadata.yml")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        [世]{f="よ" o="ニ"}[有]{f="あ" o="リ" k="二"}[伯]{f="はく"}[樂]{f="らく" k="一"}。
      MARKDOWN
      File.write(metadata_path, YAML.dump({ "jpmd-writing-mode" => "tate" }), mode: "w:utf-8")

      stdout, status = Open3.capture2(
        "pandoc",
        input_path,
        "-f", "markdown+bracketed_spans",
        "--metadata-file", metadata_path,
        "--lua-filter", File.expand_path("../filter.lua", __dir__),
        "-t", "latex"
      )

      assert status.success?, stdout
      assert_includes stdout, "\\Kanbun"
      assert_includes stdout, "世(よ){ニ}"
      assert_includes stdout, "有(あ){リ}[二]"
      assert_includes stdout, "\\printkanbunnopar\\par"
      refute_includes stdout, "\\kanbun{"
    end
  end

  def test_horizontal_rules_are_dropped
    Dir.mktmpdir("jpmd-filter-") do |dir|
      input_path = File.join(dir, "sample.md")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        first

        ---

        second
      MARKDOWN

      stdout, status = Open3.capture2(
        "pandoc",
        input_path,
        "-f", "markdown+hard_line_breaks",
        "--lua-filter", File.expand_path("../filter.lua", __dir__),
        "-t", "latex"
      )

      assert status.success?, stdout
      assert_includes stdout, "first"
      assert_includes stdout, "second"
      refute_includes stdout, "\\begin{center}\\rule{0.5\\linewidth}{0.5pt}\\end{center}"
    end
  end

  def test_soft_breaks_become_latex_line_breaks_without_breaking_headers
    Dir.mktmpdir("jpmd-filter-") do |dir|
      input_path = File.join(dir, "sample.md")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        first
        second

        #### Heading

        third
        fourth
      MARKDOWN

      stdout, status = Open3.capture2(
        "pandoc",
        input_path,
        "-f", "markdown+bracketed_spans",
        "--lua-filter", File.expand_path("../filter.lua", __dir__),
        "-t", "latex"
      )

      assert status.success?, stdout
      assert_includes stdout, "first\\\\\nsecond"
      assert_includes stdout, "\\paragraph{Heading}"
      assert_includes stdout, "third\\\\\nfourth"
    end
  end

  def test_single_asterisks_render_as_underline
    Dir.mktmpdir("jpmd-filter-") do |dir|
      input_path = File.join(dir, "sample.md")
      File.write(input_path, "*底線文字*\n", mode: "w:utf-8")

      stdout, status = Open3.capture2(
        "pandoc",
        input_path,
        "-f", "markdown+bracketed_spans",
        "--lua-filter", File.expand_path("../filter.lua", __dir__),
        "-t", "latex"
      )

      assert status.success?, stdout
      assert_includes stdout, "\\ul{底線文字}"
      refute_includes stdout, "\\emph{底線文字}"
    end
  end

  def test_citation_inside_manual_footnote_uses_fullwidth_parentheses
    Dir.mktmpdir("jpmd-filter-") do |dir|
      input_path = File.join(dir, "sample.md")
      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        本文。^[説明[@sakuma1922, pp. 108]]

        別の本文[@sakuma1922]。
      MARKDOWN

      stdout, status = Open3.capture2(
        "pandoc",
        input_path,
        "-f", "markdown",
        "--citeproc",
        "--bibliography", File.expand_path("../references/sample-zotero.json", __dir__),
        "--csl", File.expand_path("../references/word-japanese-note.csl", __dir__),
        "--lua-filter", File.expand_path("../filter.lua", __dir__),
        "-t", "latex"
      )

      assert status.success?, stdout
      assert_match(/\\footnote\{説明\s+（佐久間鼎（1922）.*108頁）\}/m, stdout)
      assert_match(/別の本文\\footnote\{佐久間鼎（1922）.*\}。/m, stdout)
    end
  end

  def test_tables_render_with_inner_rules_only
    Dir.mktmpdir("jpmd-filter-") do |dir|
      input_path = File.join(dir, "sample.md")

      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        | [風]{f="かぜ"} | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        | 4 | 5 | 6 |
      MARKDOWN

      stdout, status = Open3.capture2(
        "pandoc",
        input_path,
        "-f", "markdown+bracketed_spans",
        "--lua-filter", File.expand_path("../filter.lua", __dir__),
        "-t", "latex"
      )

      assert status.success?, stdout
      assert_includes stdout, "\\begin{longtable}[]{@{}l|l|l@{}}"
      assert_includes stdout, "\\kanbun{風}{かぜ}{}{} & B & C \\\\"
      assert_includes stdout, "\\cline{1-3}"
      refute_includes stdout, "\\toprule"
      refute_includes stdout, "\\midrule"
      refute_includes stdout, "\\bottomrule"
      refute_match(/\\cline\{1-3\}\n\\end\{longtable\}/, stdout)
    end
  end

  def test_volume_page_citation_moves_volume_after_title_and_removes_page_label
    Dir.mktmpdir("jpmd-filter-") do |dir|
      input_path = File.join(dir, "sample.md")
      bibliography_path = File.join(dir, "refs.json")

      File.write(bibliography_path, <<~JSON, mode: "w:utf-8")
        [
          {
            "id": "hakushi",
            "type": "book",
            "title": "白氏文集",
            "editor": [{ "family": "岡村", "given": "繁" }],
            "publisher": "明治書院",
            "issued": { "literal": "一九八八年" }
          },
          {
            "id": "manyo",
            "type": "book",
            "title": "萬葉集",
            "editor": [{ "family": "小島", "given": "憲之" }],
            "publisher": "小学館",
            "issued": { "literal": "一九九四年" }
          },
          {
            "id": "bunso",
            "type": "book",
            "title": "菅家文草注釈",
            "author": [{ "family": "文草の会", "given": "" }],
            "publisher": "勉誠出版",
            "issued": { "literal": "二〇一四年" }
          }
        ]
      JSON
      File.write(input_path, <<~MARKDOWN, mode: "w:utf-8")
        ---
        bibliography: #{bibliography_path}
        csl: #{File.expand_path("../references/word-japanese-note.csl", __dir__)}
        suppress-bibliography: true
        ---

        First [@hakushi, vol. 108, p. 176-177]

        Second [@manyo, vol.6, p.122-123]

        Third [@hakushi, vol.2 p.56]

        Fourth [@bunso, vol. 上, p.16]
      MARKDOWN

      stdout, status = Open3.capture2(
        "pandoc",
        input_path,
        "-f", "markdown+yaml_metadata_block",
        "--citeproc",
        "--lua-filter", File.expand_path("../filter.lua", __dir__),
        "-t", "plain"
      )

      assert status.success?, stdout
      assert_includes stdout, "岡村繁（校注）『白氏文集』108（明治書院、一九八八年）176-177頁。"
      assert_includes stdout, "小島憲之（校注）『萬葉集』6（小学館、一九九四年）122-123頁。"
      assert_includes stdout, "岡村繁（校注）『白氏文集』2（明治書院、一九八八年）56頁。"
      assert_includes stdout, "文草の会『菅家文草注釈』上（勉誠出版、二〇一四年）16頁。"
      refute_includes stdout, "p."
      refute_includes stdout, "pp."
    end
  end
end
