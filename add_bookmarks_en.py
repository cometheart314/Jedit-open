#!/usr/bin/env python3
"""
英語版 JeditHelp.rtfd/TXT.rtf に章と節のブックマークアンカーを埋め込む。
HYPERLINK "JEDITANCHOR:UUID" フィールドを使用し、Jedit で開いた時に
restoreBookmarksFromLinkAttributes() で自動的にブックマークとして認識される。
"""

import re
import uuid as uuid_mod

filepath = '/Users/satoshi/claude-code/Jedit-open/HelpManual/en/JeditHelp.rtfd/TXT.rtf'

with open(filepath, 'r', encoding='latin-1') as f:
    lines = [l.rstrip('\n') for l in f.readlines()]


def make_field(fmt_prefix, title):
    """HYPERLINK フィールドを生成する"""
    anchor_uuid = f"JEDITANCHOR:{uuid_mod.uuid4()}"
    return (
        '{\\field{\\*\\fldinst{HYPERLINK "' + anchor_uuid + '"}}'
        '{\\fldrslt ' + fmt_prefix + title + '}}'
    )


output = []
i = 0
chapters = 0
sections = 0

while i < len(lines):
    line = lines[i]

    # パターン A: 章見出し（テキスト同一行）
    # \f1\b\fs32 \cf0 1. Welcome to Jedit
    m = re.match(r'^(\\f1\\b\\fs32 \\cf0 )(.+)$', line)
    if m and not m.group(2).endswith('\\'):
        fmt = m.group(1)
        title = m.group(2)
        output.append(make_field(fmt, title))
        chapters += 1
        i += 1
        continue

    # パターン B: 章見出し（テキスト次行）
    # \f1\b\fs32 \cf0 \
    # TITLE TEXT
    if line == '\\f1\\b\\fs32 \\cf0 \\':
        if i + 1 < len(lines) and not lines[i + 1].startswith('\\'):
            title = lines[i + 1]
            output.append(make_field('\\f1\\b\\fs32 \\cf0 ', title))
            chapters += 1
            i += 2  # 2行消費
            continue

    # 節見出し（テキスト同一行）
    # \f1\b\fs28 \cf0 Key Features
    m = re.match(r'^(\\f1\\b\\fs28 \\cf0 )(.+)$', line)
    if m:
        fmt = m.group(1)
        title = m.group(2)
        output.append(make_field(fmt, title))
        sections += 1
        i += 1
        continue

    output.append(line)
    i += 1

with open(filepath, 'w', encoding='latin-1') as f:
    f.write('\n'.join(output))

print(f"Done. Chapters: {chapters}, Sections: {sections}")
print(f"Total lines: {len(lines)} -> {len(output)}")
