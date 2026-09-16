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

+ (NSString *)parseXFileAtOffset:(NSUInteger)offset maxTokens:(int)maxTokens {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData) return @"No XPK data";
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    
    if (decompressed.size() < 16) return @"Decompression failed";
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), maxTokens);
    
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"Tokens (%lu):\n", (unsigned long)tokens.size()];
    for (const auto& token : tokens) {
        std::string desc = XFileParser::describeToken(token);
        [output appendFormat:@"%s\n", desc.c_str()];
    }
    return output;
}

+ (MeshData *)extractFirstMeshAtOffset:(NSUInteger)offset {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData) return nil;
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> data = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    
    if (data.size() < 16) return nil;
    
    // Simple scan: find "Mesh\0" pattern
    size_t meshPos = 0;
    for (size_t i = 0; i < data.size() - 4; i++) {
        if (data[i] == 'M' && data[i+1] == 'e' && data[i+2] == 's' && data[i+3] == 'h' && data[i+4] == 0) {
            meshPos = i;
            break;
        }
    }
    
    if (meshPos == 0) return nil;
    
    // Skip past "Mesh" name, opening brace, material ILIST, then find FLIST
    // This is a simplified parser — assumes first FLIST after "Mesh" is vertices
    size_t scanPos = meshPos + 5;
    size_t flistPos = 0;
    size_t ilistPos = 0;
    
    // Find first ILIST (material index) then FLIST (vertices)
    int listCount = 0;
    for (size_t i = scanPos; i < data.size() - 2; i++) {
        uint16_t t = data[i] | (data[i+1] << 8);
        if (t == 6 && listCount == 0) { // First ILIST
            listCount = 1;
        } else if (t == 7 && listCount == 1) { // FLIST (vertices)
            flistPos = i + 2;
            break;
        }
    }
    
    if (flistPos == 0) return nil;
    
    // Read vertex count and data
    uint32_t vCount = data[flistPos] | (data[flistPos+1] << 8) | (data[flistPos+2] << 16) | (data[flistPos+3] << 24);
    size_t vStart = flistPos + 4;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = vCount / 3;
    mesh.vertices = [NSMutableData dataWithBytes:(data.data() + vStart) length:vCount * 4];
    
    return mesh;
}

@end
