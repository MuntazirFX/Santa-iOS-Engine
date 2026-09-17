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

@property (nonatomic) float x;
@property (nonatomic) float y;
@property (nonatomic) float z;

@end


@interface GameEngine : NSObject

+ (NSData *)loadAssetNamed:(NSString *)name;

+ (MeshData *)extractMeshFromAsset:(NSString *)assetName;

+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath;

+ (NSString *)listLevelFiles;

@end
