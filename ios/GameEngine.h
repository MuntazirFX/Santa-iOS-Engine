#import <Foundation/Foundation.h>

@interface MeshData : NSObject
@property (nonatomic) int vertexCount;
@property (nonatomic) int faceCount;
@property (strong, nonatomic) NSMutableData *vertices;
@property (strong, nonatomic) NSMutableData *indices;
@property (strong, nonatomic) NSMutableData *uvs;
@property (strong, nonatomic) NSString *textureName;
@end

@interface GameEngine : NSObject
+ (NSString *)startEngine;
+ (NSData *)loadAssetNamed:(NSString *)name;
+ (NSString *)parseXFileAtOffset:(NSUInteger)offset maxTokens:(int)maxTokens;
+ (MeshData *)extractFirstMeshAtOffset:(NSUInteger)offset;
+ (NSString *)listAssetsByKeyword:(NSString *)keyword;
@end
