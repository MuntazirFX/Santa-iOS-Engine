#import <Foundation/Foundation.h>

@interface GameEngine : NSObject
+ (NSString *)startEngine;
+ (NSData *)loadAssetNamed:(NSString *)name;
+ (NSString *)parseXFileAtOffset:(NSUInteger)offset maxTokens:(int)maxTokens;
@end
