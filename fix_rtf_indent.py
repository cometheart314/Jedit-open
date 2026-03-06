#!/usr/bin/env python3
"""
JeditHelp.rtfd/TXT.rtf のルーラー設定を修正する。
- 章（\f1\b\fs32）→ センタリング（\qc）
- 節見出し（\f1\b\fs28）→ 5ポイント字下げ（\li100）
- 本文（\f2）→ 10ポイント字下げ（\li200）
- 箇条書き（\li360\fi-360）→ 10ポイント字下げを加算（\li560\fi-360）
- 既存のインデント付き段落（\li360）→ 10ポイント字下げを加算（\li560）
- 注意ブロック（\li360\ri...）→ 10ポイント字下げを加算（\li560\ri...）
- タブ付き本文（\tx0\pardeftab640）→ 10ポイント字下げ（\li200）
- スペーサー（\fs2）→ 変更なし
- センタリング済み（\qc）→ 変更なし
"""

import re
import sys

filepath = '/Users/satoshi/claude-code/Jedit-open/HelpManual/jp/JeditHelp.rtfd/TXT.rtf'

with open(filepath, 'r', encoding='latin-1') as f:
    lines = f.readlines()

# Paragraph definitions to match
PARD_PLAIN = r'\pard\pardeftab640\slleading200\partightenfactor0'
PARD_TAB = r'\pard\tx0\pardeftab640\slleading200\partightenfactor0'
PARD_BULLET = r'\pard\pardeftab640\li360\fi-360\slleading200\partightenfactor0'
PARD_INDENT = r'\pard\pardeftab640\li360\slleading200\partightenfactor0'

# Replacements
PARD_CENTER = r'\pard\pardeftab640\slleading200\qc\partightenfactor0'
PARD_5PT = r'\pard\pardeftab640\li100\slleading200\partightenfactor0'
PARD_10PT = r'\pard\pardeftab640\li200\slleading200\partightenfactor0'
PARD_TAB_10PT = r'\pard\tx0\pardeftab640\li200\slleading200\partightenfactor0'
PARD_BULLET_10PT = r'\pard\pardeftab640\li560\fi-360\slleading200\partightenfactor0'
PARD_INDENT_10PT = r'\pard\pardeftab640\li560\slleading200\partightenfactor0'

output = []
i = 0
stats = {'chapter': 0, 'subsection': 0, 'body': 0, 'bullet': 0, 'indent': 0, 'tab': 0, 'note': 0, 'skip': 0}

while i < len(lines):
    line = lines[i].rstrip('\n')

    # 既にセンタリングされている行はスキップ
    if '\\qc\\' in line or line.endswith('\\qc'):
        output.append(line)
        i += 1
        continue

    # 注意ブロック: \pard\pardeftab640\li360\riXXXX\slleading200\partightenfactor0
    m = re.match(r'^\\pard\\pardeftab640\\li360(\\ri\d+)\\slleading200\\partightenfactor0$', line)
    if m:
        ri = m.group(1)
        output.append(f'\\pard\\pardeftab640\\li560{ri}\\slleading200\\partightenfactor0')
        stats['note'] += 1
        i += 1
        continue

    # 箇条書き: \pard\pardeftab640\li360\fi-360\slleading200\partightenfactor0
    if line == PARD_BULLET:
        output.append(PARD_BULLET_10PT)
        stats['bullet'] += 1
        i += 1
        continue

    # インデント付き段落: \pard\pardeftab640\li360\slleading200\partightenfactor0
    if line == PARD_INDENT:
        output.append(PARD_INDENT_10PT)
        stats['indent'] += 1
        i += 1
        continue

    # タブ付き段落: \pard\tx0\pardeftab640\slleading200\partightenfactor0
    if line == PARD_TAB:
        output.append(PARD_TAB_10PT)
        stats['tab'] += 1
        i += 1
        continue

    # メインの \pard: 次の非空行を見て判定
    if line == PARD_PLAIN:
        # 次の非空行を探す
        j = i + 1
        while j < len(lines) and lines[j].strip() == '':
            j += 1

        if j < len(lines):
            next_line = lines[j].rstrip('\n')
            if next_line.startswith('\\f1\\b\\fs32 '):
                # 章見出し → センタリング
                output.append(PARD_CENTER)
                stats['chapter'] += 1
            elif next_line.startswith('\\f1\\b\\fs28 '):
                # 節見出し → 5ポイント字下げ
                output.append(PARD_5PT)
                stats['subsection'] += 1
            elif next_line.startswith('\\f2'):
                # 本文 → 10ポイント字下げ
                output.append(PARD_10PT)
                stats['body'] += 1
            elif next_line.startswith('\\fs2 '):
                # スペーサー → 変更なし
                output.append(line)
                stats['skip'] += 1
            elif next_line.startswith('\\fs20 ') or next_line.startswith('\\fs24 '):
                # フッター/フォーマットリセット → 変更なし
                output.append(line)
                stats['skip'] += 1
            else:
                # その他 → 変更なし
                output.append(line)
                stats['skip'] += 1
        else:
            output.append(line)
        i += 1
        continue

    output.append(line)
    i += 1

# 書き出し
with open(filepath, 'w', encoding='latin-1') as f:
    f.write('\n'.join(output))

print(f"Done. Stats: {stats}")
print(f"Total lines: {len(lines)} -> {len(output)}")
