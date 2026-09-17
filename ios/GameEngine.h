#import <Foundation/Foundation.h>

@interface MeshData : NSObject
@property (nonatomic) int vertexCount;
@property (nonatomic) int faceCount;
@property (strong, nonatomic) NSMutableData *vertices;
@property (strong, nonatomic) NSMutableData *indices;
@property (strong, nonatomic) NSMutableData *uvs;
@property (strong, nonatomic) NSMutableData *colors;
@property (nonatomic) NSUInteger offset;
@property (strong, nonatomic) NSString *textureName;
@property (strong, nonatomic) NSString *debugInfo;
@end

@interface GameEngine : NSObject
+ (NSData *)loadAssetNamed:(NSString *)name;
+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset;
+ (MeshData *)extractSantaWithTransforms:(NSUInteger)offset;
+ (NSString *)scanForSantaModel;
@end
