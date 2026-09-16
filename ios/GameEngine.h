#import <Foundation/Foundation.h>

@interface GameEngine : NSObject
+ (NSString *)startEngine;
+ (NSData *)loadAssetNamed:(NSString *)name;
@end
