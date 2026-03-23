//
//  JOTextStorage.h
//  JeditOmega
//
//  Created by 松本慧 on 2016/03/14.
//  Copyright © 2016年 松本慧. All rights reserved.
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

#import <Cocoa/Cocoa.h>

@interface JOTextStorage : NSTextStorage
{
    NSMutableAttributedString *mutableAttributedString;
    
    NSInteger lineBreakingType;
    NSInteger editingCount;

    NSCharacterSet *topKinsokuChars;
    NSCharacterSet *endKinsokuChars;
    NSCharacterSet *burasagariChars;
    NSCharacterSet *bunriKinshiChars;
    BOOL textStorageEdited;

}

- (void)setLineBreakingType:(NSInteger)newType;
- (void)setKinsokuParamsFromDefaults;
- (nonnull NSString *)string;
- (nonnull NSDictionary *)attributesAtIndex:(NSUInteger)location effectiveRange:(nullable NSRangePointer)range;
- (void)replaceCharactersInRange:(NSRange)range withString:(nonnull NSString *)str;
- (void)setAttributes:(nullable NSDictionary *)attrs range:(NSRange)range;

- (void)beginEditing;
- (void)endEditing;
- (BOOL)isEditing;
- (BOOL)textStorageEdited;
- (NSInteger)editingCount;
@end
