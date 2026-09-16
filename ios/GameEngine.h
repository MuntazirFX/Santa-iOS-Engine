#import <Foundation/Foundation.h>

@interface MeshData : NSObject
@property (nonatomic) int vertexCount;
@property (nonatomic) int faceCount;
@property (strong, nonatomic) NSMutableData *vertices;
@property (strong, nonatomic) NSMutableData *indices;
@property (strong, nonatomic) NSMutableData *uvs;
@property (nonatomic) NSUInteger offset;
@property (strong, nonatomic) NSString *textureName;
@end

@interface GameEngine : NSObject
+ (NSData *)loadAssetNamed:(NSString *)name;
+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset;
+ (NSString *)listAssetsByKeyword:(NSString *)keyword;
+ (NSString *)findAllMeshes;
+ (NSString *)findSantaModel;
@end
