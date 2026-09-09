---
title: 文字樣式與段首縮排範例
jpmd:
  preset: academic
  layout:
    paragraph:
      first_line_indent: 1zw
  output:
    tex: ../out/text-styles.tex
---

## 底線與粗體

這個專案把單星號寫法設定為底線，例如：這是*需要加上底線的文字*。

雙星號仍然表示粗體，例如：這是**需要加粗的文字**。

## 段首縮排

這一段使用 `first_line_indent: 1zw` 的設定，因此第一行會自動縮排一個全形字寬。正文不需要手動加入全形空格。

這是另一個使用自動段首縮排的普通段落，用來確認每個新段落都套用相同設定。

\noindent 這一段以 `\noindent` 開頭，因此只有這個段落不會出現段首空白，後面的其他段落仍然使用預設縮排。

這一段再次使用自動段首縮排，用來確認 `\noindent` 不會影響下一個段落。
