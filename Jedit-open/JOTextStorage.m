//
//  JOTextStorage.m
//  Jedit-open
//
//  Based on JOTextStorage from JeditOmega
//  Modified for ARC
//

//
//  This file is part of Jedit-open.
//  Copyright (C) 2025 Satoshi Matsumoto
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

#import "JOTextStorage.h"

#define LatinMax 0x600

// UserDefaults keys (matching UserDefaults+Keys.swift)
static NSString * const JOCantBeTopChars = @"CantBeTopChars";
static NSString * const JOCantBeEndChars = @"CantBeEndChars";
static NSString * const JOBurasagariChars = @"BurasagariChars";
static NSString * const JOCantSeparateChars = @"CantSeparateChars";

@implementation JOTextStorage

- (id)init
{
    if ((self = [super init]))
    {
        mutableAttributedString = [[NSMutableAttributedString alloc] init];
        [self setKinsokuParamsFromDefaults];
    }
    return self;
}

- (void)setLineBreakingType:(NSInteger)newType
{
    lineBreakingType = newType;
}

- (void)setKinsokuParamsFromDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString *string;

    string = [defaults objectForKey:JOCantBeTopChars];
    if (!string) string = @"";
    topKinsokuChars = [NSCharacterSet characterSetWithCharactersInString:string];

    string = [defaults objectForKey:JOCantBeEndChars];
    if (!string) string = @"";
    endKinsokuChars = [NSCharacterSet characterSetWithCharactersInString:string];

    string = [defaults objectForKey:JOBurasagariChars];
    if (!string) string = @"";
    burasagariChars = [NSCharacterSet characterSetWithCharactersInString:string];

    string = [defaults objectForKey:JOCantSeparateChars];
    if (!string) string = @"";
    bunriKinshiChars = [NSCharacterSet characterSetWithCharactersInString:string];
}

- (nonnull NSString *)string
{
    return [mutableAttributedString string];
}

- (nonnull NSDictionary *)attributesAtIndex:(NSUInteger)location effectiveRange:(nullable NSRangePointer)range
{
    if (location > 0 && location >= [[self string] length])
    {
        if (location > [[self string] length])
        {
            NSLog(@"JOTextStorage: index exceeds text length!! location %lu len = %lu", (unsigned long)location, (unsigned long)[[self string] length]);
        }
        location = [[self string] length] - 1;
    }
    if ([[self string] length] == 0) return @{};
    return [mutableAttributedString attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(nonnull NSString *)str
{
    NSInteger delta;

    if (NSMaxRange(range) > [[self string] length])
    {
        NSLog(@"JOTextStorage: range exceeds text length!!");
        if (range.location >= [[self string] length]) {
            range = NSMakeRange([[self string] length], 0);
        } else {
            range.length = [[self string] length] - range.location;
        }
    }

    [mutableAttributedString replaceCharactersInRange:range withString:str];

    delta = [str length] - range.length;
    textStorageEdited = YES;
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:delta];
    textStorageEdited = NO;
}

- (void)setAttributes:(nullable NSDictionary *)attrs range:(NSRange)range
{
    if (NSMaxRange(range) > [[self string] length])
    {
        NSLog(@"JOTextStorage: range exceeds text length!!");
        if (range.location >= [[self string] length]) {
            range = NSMakeRange([[self string] length], 0);
        } else {
            range.length = [[self string] length] - range.location;
        }
    }

    // Note: NSTextView (allowsUndo=YES) が文字と属性の両方の変更を Undo 管理するため、
    // textStorage レベルでの手動 Undo 登録は不要。手動登録すると NSTextView の
    // 自動 Undo グルーピングが壊れ、連続入力が1文字ずつ Undo される問題が発生する。

    [mutableAttributedString setAttributes:attrs range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

/// layoutManagers 経由で最初の NSTextView を取得する
- (nullable NSTextView *)firstTextView
{
    for (NSLayoutManager *lm in [self layoutManagers]) {
        NSTextView *tv = [lm firstTextView];
        if (tv) return tv;
    }
    return nil;
}

- (NSUInteger)lineBreakBeforeIndex:(NSUInteger)location withinRange:(NSRange)aRange
{
    NSUInteger ret, defaultBreak;
    NSInteger delta, maxIndex;
    unichar char_B, char_C, char_D;

    if (lineBreakingType == 1) // Burasagari Kinsoku
    {
        defaultBreak = [super lineBreakBeforeIndex:location withinRange:aRange];
        delta = NSMaxRange(aRange) - defaultBreak;

        maxIndex = NSMaxRange(aRange);
        maxIndex--;
        if (maxIndex < (NSInteger)defaultBreak) maxIndex = defaultBreak;

        // 範囲チェック
        if (defaultBreak >= [[self string] length] || maxIndex < 1 || maxIndex - 1 >= (NSInteger)[[self string] length]) {
            return defaultBreak;
        }

        char_D = [[self string] characterAtIndex:defaultBreak];
        if (char_D < LatinMax && delta > 0) {
            ret = defaultBreak;
        }
        else
        {
            char_C = [[self string] characterAtIndex:maxIndex - 1];
            if ([burasagariChars characterIsMember:char_C]) {
                ret = maxIndex;
            }
            else if (char_C == 0x3000 || char_C == ' ')
            {
                ret = maxIndex;
            }
            else if (char_C < LatinMax)
            {
                ret = maxIndex;
                while (char_C == '_' || isalnum(char_C))
                {
                    ret--;
                    if (ret < 1) break;
                    char_C = [[self string] characterAtIndex:ret - 1];
                }
            }
            else if ([topKinsokuChars characterIsMember:char_C]) {
                ret = maxIndex - 2;
            }
            else
            {
                if (maxIndex < 2 || maxIndex - 2 >= (NSInteger)[[self string] length]) {
                    return maxIndex - 1;
                }
                char_B = [[self string] characterAtIndex:maxIndex - 2];
                if ([endKinsokuChars characterIsMember:char_B])
                {
                    ret = maxIndex - 2;
                }
                else if ([bunriKinshiChars characterIsMember:char_B] && [bunriKinshiChars characterIsMember:char_C])
                {
                    ret = maxIndex - 2;
                }
                else {
                    ret = maxIndex - 1;
                }
            }
        }
    }
    else if (lineBreakingType == 2)
    { // No wordwrapping
        ret = NSMaxRange(aRange) - 1;
    }
    else
    {
        // System Defaults
        ret = [super lineBreakBeforeIndex:location withinRange:aRange];
    }

    return ret;
}

- (void)beginEditing
{
    editingCount++;
    if (editingCount == 1) [super beginEditing];
}

- (void)endEditing
{
    if (editingCount < 0)
    {
        NSLog(@"*** JOTextStorage: too many endEditing ****");
        editingCount = 0;
    }
    else
    {
        if (editingCount == 1) [super endEditing];
        editingCount--;
    }
}

- (BOOL)isEditing
{
    return editingCount > 0;
}

- (NSInteger)editingCount
{
    return editingCount;
}

- (BOOL)textStorageEdited
{
    return textStorageEdited;
}

@end
