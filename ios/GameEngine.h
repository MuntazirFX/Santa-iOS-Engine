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

@interface LevelObject : NSObject
@property (strong, nonatomic) NSString *objectName;
@property (nonatomic) float x, y, z;
@end

@interface GameEngine : NSObject
+ (NSData *)loadAssetNamed:(NSString *)name;
+ (MeshData *)extractMeshFromAsset:(NSString *)assetName;
+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath;
+ (NSString *)listLevelFiles;
+ (NSString *)listTextureFiles;

// Decodes a DDS texture from the XPK archive (by its XPK-internal path,
// e.g. "maps\\nicolaus.dds") into tightly-packed RGBA8 pixels.
+ (NSData *)loadTextureRGBA8Named:(NSString *)xpkPath
                             width:(int *)outWidth
                            height:(int *)outHeight;
@end
