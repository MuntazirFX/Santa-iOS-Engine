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
    
    // Parse all tokens
    std::vector<XToken> tokens = XFileParser::parseTokens(data.data(), data.size(), 2000);
    NSLog(@"[Mesh] Total tokens: %lu", (unsigned long)tokens.size());
    
    // Walk through tokens to find "Mesh" NAME
    for (size_t i = 0; i < tokens.size(); i++) {
        if (tokens[i].type == 1 && tokens[i].name == "Mesh") {
            NSLog(@"[Mesh] Found 'Mesh' at token %zu", i);
            
            size_t j = i + 1;
            if (j < tokens.size() && tokens[j].type == 10) j++; // skip {
            
            if (j < tokens.size() && tokens[j].type == 6) j++; // skip ILIST
            
            if (j < tokens.size() && tokens[j].type == 7) {
                const auto& verts = tokens[j].floatList;
                NSLog(@"[Mesh] Vertices: %zu floats", verts.size());
                
                if (verts.size() >= 3) {
                    MeshData *mesh = [[MeshData alloc] init];
                    mesh.vertexCount = (int)(verts.size() / 3);
                    mesh.vertices = [NSMutableData dataWithBytes:verts.data() length:verts.size() * 4];
                    
                    j++;
                    if (j < tokens.size() && tokens[j].type == 6) {
                        mesh.faceCount = (int)(tokens[j].intList.size() / 3);
                    }
                    return mesh;
                }
            }
        }
    }
    
    NSLog(@"[Mesh] Not found");
    return nil;
}

@end
