# frozen_string_literal: true

require "open3"
require "rexml/document"
require "rexml/xpath"
require_relative "test_helper"

class CSLStyleTest < Minitest::Test
  def test_contributors_use_japanese_list_delimiter
    style = REXML::Document.new(File.read(style_path, mode: "r:utf-8"))
    author_name = REXML::XPath.first(style, "//*[local-name()='macro' and @name='contributors']/*[local-name()='names' and @variable='author']/*[local-name()='name']")
    editor_name = REXML::XPath.first(style, "//*[local-name()='macro' and @name='contributors']/*[local-name()='names' and @variable='author']/*[local-name()='substitute']/*[local-name()='names' and @variable='editor']/*[local-name()='name']")

    assert_equal "、", author_name.attributes["delimiter"]
    assert_equal "、", editor_name.attributes["delimiter"]
  end

  def test_editor_substitute_adds_kochu_suffix
    style = REXML::Document.new(File.read(style_path, mode: "r:utf-8"))
    editor_names = REXML::XPath.first(style, "//*[local-name()='macro' and @name='contributors']/*[local-name()='names' and @variable='author']/*[local-name()='substitute']/*[local-name()='names' and @variable='editor']")

    assert_equal "（校注）", editor_names.attributes["suffix"]
  end

  def test_book_title_uses_double_corner_brackets
    style = REXML::Document.new(File.read(style_path, mode: "r:utf-8"))
    book_title = REXML::XPath.first(style, "//*[local-name()='macro' and @name='title']/*[local-name()='choose']/*[local-name()='if' and @match='any' and @type='book collection']/*[local-name()='text']")

    assert_equal "『", book_title.attributes["prefix"]
    assert_equal "』", book_title.attributes["suffix"]
  end

  def test_paper_title_uses_corner_brackets
    style = REXML::Document.new(File.read(style_path, mode: "r:utf-8"))
    paper_title = REXML::XPath.first(style, "//*[local-name()='macro' and @name='title']/*[local-name()='choose']/*[local-name()='else']/*[local-name()='text']")

    assert_equal "「", paper_title.attributes["prefix"]
    assert_equal "」", paper_title.attributes["suffix"]
  end

  def test_webpage_publication_uses_website_and_both_dates
    style = REXML::Document.new(File.read(style_path, mode: "r:utf-8"))
    webpage_group = REXML::XPath.first(style, "//*[local-name()='macro' and @name='publication']/*[local-name()='choose']/*[local-name()='if' and @type='webpage']//*[local-name()='group']")
    website_text = REXML::XPath.first(webpage_group, "./*[local-name()='text' and @macro='website']")
    issued_text = REXML::XPath.first(webpage_group, "./*[local-name()='text' and @macro='webpage-issued']")
    accessed_text = REXML::XPath.first(webpage_group, "./*[local-name()='text' and @macro='webpage-accessed']")

    assert_equal "（", webpage_group.attributes["prefix"]
    assert_equal "）", webpage_group.attributes["suffix"]
    assert_equal "、", webpage_group.attributes["delimiter"]
    refute_nil website_text
    refute_nil issued_text
    refute_nil accessed_text
  end

  def test_webpage_issued_date_is_publication_and_accessed_date_is_viewing
    Dir.mktmpdir("jpmd-csl-") do |dir|
      input_path = File.join(dir, "sample.md")
      bibliography_path = File.join(dir, "refs.json")
      File.write(input_path, "本文[@web]。\n", mode: "w:utf-8")
      File.write(bibliography_path, <<~JSON, mode: "w:utf-8")
        [{
          "id": "web",
          "type": "webpage",
          "title": "漢文資料の読み方（架空のページ）",
          "container-title": "資料案内サイト（架空）",
          "issued": { "literal": "二〇一四年十二月" },
          "accessed": { "literal": "二〇二六年十月" }
        }]
      JSON

      stdout, status = Open3.capture2(
        "pandoc", input_path, "-f", "markdown", "-t", "latex",
        "--citeproc", "--bibliography", bibliography_path, "--csl", style_path
      )

      assert status.success?, stdout
      assert_includes stdout, "二〇一四年十二月刊、二〇二六年十月閲"
      refute_includes stdout, "二〇一四年十二月閲"
    end
  end

  def test_article_journal_publication_uses_journal_volume_issue_and_date
    style = REXML::Document.new(File.read(style_path, mode: "r:utf-8"))
    article_publication = REXML::XPath.first(style, "//*[local-name()='macro' and @name='publication']/*[local-name()='choose']/*[local-name()='else-if' and @type='article-journal']/*[local-name()='text' and @macro='journal-publication']")
    journal_group = REXML::XPath.first(style, "//*[local-name()='macro' and @name='journal-publication']/*[local-name()='group']")
    journal_title = REXML::XPath.first(journal_group, ".//*[local-name()='text' and @variable='container-title']")
    volume_issue = REXML::XPath.first(journal_group, ".//*[local-name()='group' and @delimiter='-']")
    issued_date = REXML::XPath.first(journal_group, "./*[local-name()='text' and @macro='issued-date']")

    refute_nil article_publication
    assert_equal "（", journal_group.attributes["prefix"]
    assert_equal "）", journal_group.attributes["suffix"]
    assert_equal "、", journal_group.attributes["delimiter"]
    assert_equal "『", journal_title.attributes["prefix"]
    assert_equal "』", journal_title.attributes["suffix"]
    refute_nil volume_issue
    refute_nil issued_date
  end

  def test_webpage_citations_skip_contributors
    style = REXML::Document.new(File.read(style_path, mode: "r:utf-8"))
    webpage_citation_group = REXML::XPath.first(style, "//*[local-name()='citation']/*[local-name()='layout']/*[local-name()='choose']/*[local-name()='if' and @type='webpage']/*[local-name()='group']")
    contributors = REXML::XPath.first(webpage_citation_group, ".//*[local-name()='text' and @macro='contributors']")
    title = REXML::XPath.first(webpage_citation_group, "./*[local-name()='text' and @macro='title']")

    assert_nil contributors
    refute_nil title
  end

  private

  def style_path
    File.join(JPMD::Compiler::APP_ROOT, "references", "word-japanese-note.csl")
  end
end
