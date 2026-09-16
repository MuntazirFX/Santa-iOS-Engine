#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include <string>
#include <vector>
#include <fstream>

@implementation MeshData
@end

@implementation GameEngine

+ (NSString *)startEngine {
    NSMutableString *status = [NSMutableString string];
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (resourcePath == nil) return @"ERROR: xmas.xpk not found!";
    
    std::string xpkPath = [resourcePath UTF8String];
    AssetManager assetMgr;
    if (assetMgr.loadXPK(xpkPath)) {
        [status appendString:@"XPK Loaded!"];
    }
    return status;
}

+ (NSData *)loadAssetNamed:(NSString *)name {
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!resourcePath) return nil;
    
    std::string xpkPath = [resourcePath UTF8String];
    AssetManager assetMgr;
    if (!assetMgr.loadXPK(xpkPath)) return nil;
    
    std::string assetName = [name UTF8String];
    std::vector<uint8_t> data = assetMgr.getAssetData(assetName);
    
    if (data.empty()) return nil;
    return [NSData dataWithBytes:data.data() length:data.size()];
}

+ (MeshData *)extractFirstMeshAtOffset:(NSUInteger)offset {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData) return nil;
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> data = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    if (data.size() < 16) return nil;
    
    std::vector<XToken> tokens = XFileParser::parseTokens(data.data(), data.size(), 2000);
    
    for (size_t i = 0; i < tokens.size(); i++) {
        if (tokens[i].type == 1 && tokens[i].name == "Mesh") {
            size_t j = i + 1;
            if (j < tokens.size() && tokens[j].type == 10) j++;
            if (j < tokens.size() && tokens[j].type == 6) j++;
            
            if (j < tokens.size() && tokens[j].type == 7) {
                const auto& verts = tokens[j].floatList;
                if (verts.size() < 3) continue;
                
                MeshData *mesh = [[MeshData alloc] init];
                mesh.vertexCount = (int)(verts.size() / 3);
                mesh.vertices = [NSMutableData dataWithBytes:verts.data() length:verts.size() * 4];
                
                j++;
                if (j < tokens.size() && tokens[j].type == 6) {
                    const auto& faces = tokens[j].intList;
                    mesh.faceCount = (int)(faces.size() / 3);
                    mesh.indices = [NSMutableData dataWithBytes:faces.data() length:faces.size() * 4];
                }
                
                // Look for MeshTextureCoords in next 40 tokens
                for (size_t k = i + 5; k < tokens.size() && k < i + 40; k++) {
                    if (tokens[k].type == 1 && tokens[k].name == "MeshTextureCoords") {
                        size_t m = k + 1;
                        if (m < tokens.size() && tokens[m].type == 10) m++;
                        if (m < tokens.size() && tokens[m].type == 6) m++;
                        if (m < tokens.size() && tokens[m].type == 7) {
                            const auto& uvs = tokens[m].floatList;
                            mesh.uvs = [NSMutableData dataWithBytes:uvs.data() length:uvs.size() * 4];
                        }
                        break;
                    }
                }
                
                // Look for TextureFilename
                for (size_t k = i + 5; k < tokens.size() && k < i + 100; k++) {
                    if (tokens[k].type == 1 && tokens[k].name == "TextureFilename") {
                        if (k + 2 < tokens.size() && tokens[k+2].type == 2) {
                            mesh.textureName = [NSString stringWithUTF8String:tokens[k+2].name.c_str()];
                        }
                        break;
                    }
                }
                
                return mesh;
            }
        }
    }
    return nil;
}

@end
