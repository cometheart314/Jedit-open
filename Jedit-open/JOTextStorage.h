//
//  JOTextStorage.h
//  JeditOmega
//
//  Created by 松本慧 on 2016/03/14.
//  Copyright © 2016年 松本慧. All rights reserved.
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
