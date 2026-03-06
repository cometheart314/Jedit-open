#!/usr/bin/env python3
"""
英語版 JeditHelp.rtfd/TXT.rtf のルーラー設定を修正する。
- 章（fs32）→ センタリング、前後に空行
- 節見出し（fs28）→ 5pt字下げ、前に空行
- 本文 → 10pt字下げ
- 箇条書き → 10pt字下げ加算
"""

import re

filepath = '/Users/satoshi/claude-code/Jedit-open/HelpManual/en/JeditHelp.rtfd/TXT.rtf'

with open(filepath, 'r', encoding='latin-1') as f:
    lines = [l.rstrip('\n') for l in f.readlines()]

PARD_PLAIN = '\\pard\\pardeftab640\\slleading200\\partightenfactor0'
PARD_CENTER = '\\pard\\pardeftab640\\slleading200\\qc\\partightenfactor0'
PARD_5PT = '\\pard\\pardeftab640\\li100\\slleading200\\partightenfactor0'
PARD_10PT = '\\pard\\pardeftab640\\li200\\slleading200\\partightenfactor0'
PARD_BULLET = '\\pard\\pardeftab640\\li360\\fi-360\\slleading200\\partightenfactor0'
PARD_BULLET_10PT = '\\pard\\pardeftab640\\li560\\fi-360\\slleading200\\partightenfactor0'
PARD_INDENT = '\\pard\\pardeftab640\\li360\\slleading200\\partightenfactor0'
PARD_INDENT_10PT = '\\pard\\pardeftab640\\li560\\slleading200\\partightenfactor0'

SPACER = [PARD_PLAIN, '', '\\fs2 \\cf0 \\']

stats = {'chapter': 0, 'subsection': 0, 'body': 0, 'body_split': 0,
         'bullet': 0, 'indent': 0, 'note': 0, 'spacer_added': 0, 'skip': 0}


def last_is_spacer(out):
    """直前がスペーサーかどうか"""
    if len(out) < 1:
        return False
    return out[-1] == '\\fs2 \\cf0 \\'


def add_spacer(out):
    """スペーサー行を追加（既にある場合はスキップ）"""
    if not last_is_spacer(out):
        out.extend(SPACER)
        stats['spacer_added'] += 1


def find_next_content(lines, start):
    """start 以降で最初の非空行のインデックスを返す"""
    j = start
    while j < len(lines) and lines[j].strip() == '':
        j += 1
    return j


def has_body_after_reset(lines, idx):
    """フォーマットリセット行の後に本文があるか（次の \\pard の前）"""
    if idx >= len(lines):
        return False
    line = lines[idx]
    # 空行、\\pard で始まる行、空文字はスキップ
    if line.strip() == '' or line.startswith('\\pard'):
        return False
    return True


output = []
i = 0

while i < len(lines):
    line = lines[i]

    # 既にセンタリングされている行はスキップ
    if '\\qc\\' in line or line.endswith('\\qc'):
        output.append(line)
        i += 1
        continue

    # 注意ブロック: \li360\riXXXX
    m = re.match(r'^\\pard\\pardeftab640\\li360(\\ri\d+)\\slleading200\\partightenfactor0$', line)
    if m:
        ri = m.group(1)
        output.append(f'\\pard\\pardeftab640\\li560{ri}\\slleading200\\partightenfactor0')
        stats['note'] += 1
        i += 1
        continue

    # 箇条書き
    if line == PARD_BULLET:
        output.append(PARD_BULLET_10PT)
        stats['bullet'] += 1
        i += 1
        continue

    # インデント付き段落
    if line == PARD_INDENT:
        output.append(PARD_INDENT_10PT)
        stats['indent'] += 1
        i += 1
        continue

    # メインの \pard
    if line == PARD_PLAIN:
        j = find_next_content(lines, i + 1)

        if j >= len(lines):
            output.append(line)
            i += 1
            continue

        next_line = lines[j]

        # --- 章見出し（\f1\b\fs32）---
        if next_line.startswith('\\f1\\b\\fs32 '):
            # 前に空行を挿入
            add_spacer(output)
            # センタリングの pard を出力
            output.append(PARD_CENTER)
            # pard と見出しの間の空行を出力
            for k in range(i + 1, j):
                output.append(lines[k])
            # 見出し行を出力
            output.append(lines[j])
            i = j + 1
            stats['chapter'] += 1

            # フォーマットリセット行を処理
            if i < len(lines) and lines[i].startswith('\\f0\\b0'):
                reset_line = lines[i]
                i += 1

                # リセット後に本文があるか？
                if has_body_after_reset(lines, i):
                    # 見出しのリセットを出力（センタリング pard の中）
                    output.append(reset_line)
                    # 後に空行を挿入
                    add_spacer(output)
                    # 本文用の pard を開始
                    output.append(PARD_10PT)
                    # 本文行を出力（次の \pard まで）
                    while i < len(lines) and not lines[i].startswith('\\pard'):
                        output.append(lines[i])
                        i += 1
                    stats['body_split'] += 1
                else:
                    output.append(reset_line)
                    # 後に空行を挿入
                    add_spacer(output)
            else:
                # 後に空行を挿入
                add_spacer(output)
            continue

        # --- 節見出し（\f1\b\fs28）---
        elif next_line.startswith('\\f1\\b\\fs28 '):
            # 前に空行を挿入
            add_spacer(output)
            # 5pt字下げの pard を出力
            output.append(PARD_5PT)
            for k in range(i + 1, j):
                output.append(lines[k])
            output.append(lines[j])
            i = j + 1
            stats['subsection'] += 1

            # フォーマットリセット行を処理
            if i < len(lines) and lines[i].startswith('\\f0\\b0'):
                reset_line = lines[i]
                i += 1

                if has_body_after_reset(lines, i):
                    output.append(reset_line)
                    # 本文用の pard を開始
                    output.append(PARD_10PT)
                    while i < len(lines) and not lines[i].startswith('\\pard'):
                        output.append(lines[i])
                        i += 1
                    stats['body_split'] += 1
                else:
                    output.append(reset_line)
            continue

        # --- スペーサー ---
        elif next_line.startswith('\\fs2 '):
            output.append(line)
            stats['skip'] += 1
            i += 1
            continue

        # --- フッター・フォーマットリセット ---
        elif next_line.startswith('\\fs20 ') or next_line.startswith('\\fs24 '):
            output.append(line)
            stats['skip'] += 1
            i += 1
            continue

        # --- 本文（\cf0 で始まる、または \f1\b \cf0 の h3 見出し等） ---
        else:
            output.append(PARD_10PT)
            stats['body'] += 1
            i += 1
            continue

    output.append(line)
    i += 1

with open(filepath, 'w', encoding='latin-1') as f:
    f.write('\n'.join(output))

print(f"Done. Stats: {stats}")
print(f"Total lines: {len(lines)} -> {len(output)}")
