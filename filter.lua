local function escape_latex(str)
  local replacements = {
    ["\\"] = "\\textbackslash{}",
    ["{"] = "\\{",
    ["}"] = "\\}",
    ["#"] = "\\#",
    ["$"] = "\\$",
    ["%"] = "\\%",
    ["&"] = "\\&",
    ["_"] = "\\_",
    ["^"] = "\\^{}",
    ["~"] = "\\~{}"
  }

  return (tostring(str or ""):gsub("[\\{}#$%%&_~^]", replacements))
end

local writing_mode = "yoko"

local function span_attributes(span)
  if span.attr and span.attr.attributes then
    return span.attr.attributes
  end

  if span.attributes then
    return span.attributes
  end

  return {}
end

local function has_kanbun_attributes(attributes)
  return attributes.f ~= nil or attributes.o ~= nil or attributes.k ~= nil
end

local function has_kanbun_span(inlines)
  for _, inline in ipairs(inlines or {}) do
    if inline.t == "Span" and has_kanbun_attributes(span_attributes(inline)) then
      return true
    end
  end

  return false
end

local function serialize_kanbun_inlines(inlines)
  local parts = {}

  for _, inline in ipairs(inlines or {}) do
    local text = nil

    if inline.t == "Str" then
      text = inline.text == "　" and "" or inline.text
    elseif inline.t == "Space" or inline.t == "SoftBreak" then
      text = ""
    elseif inline.t == "LineBreak" then
      text = "\n"
    elseif inline.t == "Span" then
      local attributes = span_attributes(inline)

      if has_kanbun_attributes(attributes) then
        local base_text = pandoc.utils.stringify(inline)
        local annotated = { base_text }

        if attributes.f and attributes.f ~= "" then
          table.insert(annotated, "(" .. attributes.f .. ")")
        end

        if attributes.o and attributes.o ~= "" then
          table.insert(annotated, "{" .. attributes.o .. "}")
        end

        if attributes.k and attributes.k ~= "" then
          table.insert(annotated, "[" .. attributes.k .. "]")
        end

        text = table.concat(annotated)
      else
        text = serialize_kanbun_inlines(inline.content)
      end
    elseif inline.t == "Emph" or inline.t == "Strong" or inline.t == "Strikeout" or inline.t == "Underline" or inline.t == "SmallCaps" or inline.t == "Superscript" or inline.t == "Subscript" or inline.t == "Quoted" then
      text = serialize_kanbun_inlines(inline.content)
    elseif inline.t == "Code" then
      text = inline.text
    else
      return nil
    end

    if text == nil then
      return nil
    end

    table.insert(parts, text)
  end

  local serialized = table.concat(parts)
  serialized = serialized:gsub("^　+", "")
  serialized = serialized:gsub("^[ \t]+", "")

  return serialized
end

local function render_tate_kanbun_block(inlines)
  local source = serialize_kanbun_inlines(inlines)
  if source == nil or source == "" then
    return nil
  end

  return pandoc.RawBlock(
    "latex",
    table.concat({
      "{",
      "\\Kanbun",
      source,
      "\\EndKanbun",
      "\\printkanbunnopar\\par",
      "}"
    }, "\n")
  )
end

function Meta(meta)
  local mode = meta["jpmd-writing-mode"]
  if mode ~= nil then
    writing_mode = pandoc.utils.stringify(mode)
  end

  return meta
end

function Para(para)
  if writing_mode ~= "tate" or not has_kanbun_span(para.content) then
    return nil
  end

  return render_tate_kanbun_block(para.content)
end

function Plain(plain)
  if writing_mode ~= "tate" or not has_kanbun_span(plain.content) then
    return nil
  end

  return render_tate_kanbun_block(plain.content)
end

function HorizontalRule()
  return {}
end

function SoftBreak()
  return pandoc.LineBreak()
end

local function normalize_spaces(str)
  return tostring(str or "")
    :gsub(string.char(194, 160), " ")
    :gsub("[ \t\r\n\f\v]+", " ")
    :gsub("^[ \t\r\n\f\v]+", "")
    :gsub("[ \t\r\n\f\v]+$", "")
end

local function volume_page_locator(suffix)
  local text = normalize_spaces(pandoc.utils.stringify(suffix or {}))
  text = text:gsub("^,%s*", "")

  local volume, pages = text:match("^[Vv]ol%.%s*([^,%s]+)%s*,?%s*[Pp][Pp]%.?%s*(.+)$")
  if volume == nil then
    volume, pages = text:match("^[Vv]ol%.%s*([^,%s]+)%s*,?%s*[Pp]%.?%s*(.+)$")
  end
  if volume == nil then
    volume, pages = text:match("^([^,%s]+)%s+[Pp][Pp]%.?%s*(.+)$")
  end
  if volume == nil then
    volume, pages = text:match("^([^,%s]+)%s+[Pp]%.?%s*(.+)$")
  end

  if volume == nil or pages == nil then
    return nil
  end

  return {
    volume = normalize_spaces(volume),
    pages = normalize_spaces(pages)
  }
end

local function inlines_from_text(text)
  local inlines = {}
  local first = true

  for word in normalize_spaces(text):gmatch("[^ \t\r\n\f\v]+") do
    if not first then
      table.insert(inlines, pandoc.Space())
    end

    table.insert(inlines, pandoc.Str(word))
    first = false
  end

  if #inlines == 0 then
    return { pandoc.Str("") }
  end

  return inlines
end

local function note_text(note)
  return normalize_spaces(pandoc.utils.stringify(note.content or {}))
end

local function volume_page_note(text, locator)
  local before_publication, publication = normalize_spaces(text):match("^(.*)(（.-）)")
  if before_publication == nil or publication == nil then
    return nil
  end

  return normalize_spaces(before_publication) .. locator.volume .. publication .. locator.pages .. "頁。"
end

function Cite(cite)
  if #(cite.citations or {}) ~= 1 then
    return nil
  end

  local locator = volume_page_locator(cite.citations[1].suffix)
  if locator == nil then
    return nil
  end

  for index, inline in ipairs(cite.content or {}) do
    if inline.t == "Note" then
      local transformed = volume_page_note(note_text(inline), locator)
      if transformed == nil then
        return nil
      end

      inline.content = { pandoc.Para(inlines_from_text(transformed)) }
      cite.content[index] = inline
      return cite
    end
  end

  return nil
end

local function latex_table_output()
  return FORMAT == "latex" or FORMAT == "beamer"
end

local function table_alignment(spec)
  local align = spec[1]

  if align == "AlignLeft" then
    return "l"
  elseif align == "AlignRight" then
    return "r"
  elseif align == "AlignCenter" then
    return "c"
  end

  return "l"
end

local function table_column_spec(colspecs)
  local columns = {}

  for _, spec in ipairs(colspecs or {}) do
    table.insert(columns, table_alignment(spec))
  end

  return string.format("@{}%s@{}", table.concat(columns, "|"))
end

local function transform_table_blocks(blocks)
  local transformed = {}

  for _, block in ipairs(blocks or {}) do
    table.insert(transformed, pandoc.walk_block(block, {
      SoftBreak = SoftBreak,
      Span = Span
    }))
  end

  return transformed
end

local function render_table_blocks(blocks)
  if #blocks == 0 then
    return ""
  end

  local rendered = pandoc.write(
    pandoc.Pandoc(transform_table_blocks(blocks), pandoc.Meta({})),
    "latex"
  )

  rendered = rendered:gsub("%s+$", "")
  rendered = rendered:gsub("\n\n+", " ")
  rendered = rendered:gsub("\n", " ")

  return rendered
end

local function table_rows(tbl)
  local rows = {}

  for _, row in ipairs(tbl.head.rows or {}) do
    table.insert(rows, row)
  end

  for _, body in ipairs(tbl.bodies or {}) do
    for _, row in ipairs(body.head or {}) do
      table.insert(rows, row)
    end

    for _, row in ipairs(body.body or {}) do
      table.insert(rows, row)
    end
  end

  for _, row in ipairs(tbl.foot.rows or {}) do
    table.insert(rows, row)
  end

  return rows
end

local function simple_table(tbl)
  if not latex_table_output() then
    return false
  end

  if #tbl.colspecs == 0 then
    return false
  end

  for _, body in ipairs(tbl.bodies or {}) do
    if body.row_head_columns ~= 0 then
      return false
    end
  end

  for _, row in ipairs(table_rows(tbl)) do
    for _, cell in ipairs(row.cells or {}) do
      if cell.row_span ~= 1 or cell.col_span ~= 1 then
        return false
      end
    end
  end

  return true
end

local function render_table_row(row)
  local cells = {}

  for _, cell in ipairs(row.cells or {}) do
    table.insert(cells, render_table_blocks(cell.contents))
  end

  return table.concat(cells, " & ") .. " \\\\"
end

function Table(tbl)
  if not simple_table(tbl) then
    return nil
  end

  local rows = table_rows(tbl)
  local lines = {
    string.format("\\begin{longtable}[]{%s}", table_column_spec(tbl.colspecs))
  }
  local total_rows = #rows
  local caption = render_table_blocks(tbl.caption.long or {})

  if caption ~= "" then
    local label = ""

    if tbl.attr and tbl.attr.identifier and tbl.attr.identifier ~= "" then
      label = string.format("\\label{%s}", tbl.attr.identifier)
    end

    table.insert(lines, string.format("\\caption{%s}%s\\\\", caption, label))
  end

  local rendered_rows = 0

  for _, row in ipairs(tbl.head.rows or {}) do
    rendered_rows = rendered_rows + 1
    table.insert(lines, render_table_row(row))

    if rendered_rows < total_rows then
      table.insert(lines, string.format("\\cline{1-%d}", #tbl.colspecs))
    end
  end

  if #(tbl.head.rows or {}) > 0 then
    table.insert(lines, "\\endhead")
  end

  for _, body in ipairs(tbl.bodies or {}) do
    for _, row in ipairs(body.head or {}) do
      rendered_rows = rendered_rows + 1
      table.insert(lines, render_table_row(row))

      if rendered_rows < total_rows then
        table.insert(lines, string.format("\\cline{1-%d}", #tbl.colspecs))
      end
    end

    for _, row in ipairs(body.body or {}) do
      rendered_rows = rendered_rows + 1
      table.insert(lines, render_table_row(row))

      if rendered_rows < total_rows then
        table.insert(lines, string.format("\\cline{1-%d}", #tbl.colspecs))
      end
    end
  end

  for _, row in ipairs(tbl.foot.rows or {}) do
    rendered_rows = rendered_rows + 1
    table.insert(lines, render_table_row(row))

    if rendered_rows < total_rows then
      table.insert(lines, string.format("\\cline{1-%d}", #tbl.colspecs))
    end
  end

  table.insert(lines, "\\end{longtable}")

  return pandoc.RawBlock("latex", table.concat(lines, "\n"))
end

function Span(span)
  if writing_mode == "tate" then
    return nil
  end

  local attributes = span_attributes(span)

  if not has_kanbun_attributes(attributes) then
    return nil
  end

  local base_text = pandoc.utils.stringify(span)

  return pandoc.RawInline(
    "latex",
    string.format(
      "\\kanbun{%s}{%s}{%s}{%s}",
      escape_latex(base_text),
      escape_latex(attributes.f or ""),
      escape_latex(attributes.o or ""),
      escape_latex(attributes.k or "")
    )
  )
end

return {
  {
    Meta = Meta
  },
  {
    Para = Para,
    Plain = Plain,
    Table = Table,
    HorizontalRule = HorizontalRule,
    SoftBreak = SoftBreak,
    Cite = Cite,
    Span = Span
  }
}
