#import <Foundation/Foundation.h>

@interface MeshData : NSObject
@property (nonatomic) int vertexCount;
@property (nonatomic) int faceCount;
@property (strong, nonatomic) NSMutableData *vertices;  // float3 array
@property (strong, nonatomic) NSMutableData *uvs;       // float2 array
@end

@interface GameEngine : NSObject
+ (NSString *)startEngine;
+ (NSData *)loadAssetNamed:(NSString *)name;
+ (NSString *)parseXFileAtOffset:(NSUInteger)offset maxTokens:(int)maxTokens;
+ (MeshData *)extractFirstMeshAtOffset:(NSUInteger)offset;
@end
