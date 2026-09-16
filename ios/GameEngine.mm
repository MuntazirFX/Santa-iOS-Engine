#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include <string>
#include <vector>
#include <algorithm>

@implementation MeshData
@end

@implementation GameEngine

+ (NSData *)loadAssetNamed:(NSString *)name {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return nil;
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return nil;
    std::vector<uint8_t> d = am.getAssetData([name UTF8String]);
    if (d.empty()) return nil;
    return [NSData dataWithBytes:d.data() length:d.size()];
}

+ (NSString *)listAssetsByKeyword:(NSString *)keyword {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return @"No XPK";
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return @"fail";
    std::vector<std::string> all = am.getAllFilenames();
    std::string kw = [keyword UTF8String];
    std::transform(kw.begin(), kw.end(), kw.begin(), ::tolower);
    NSMutableString *out = [NSMutableString string];
    int c = 0;
    for (const auto& n : all) {
        std::string l = n;
        std::transform(l.begin(), l.end(), l.begin(), ::tolower);
        if (l.find(kw) != std::string::npos) {
            [out appendFormat:@"%s\n", n.c_str()];
            if (++c >= 40) break;
        }
    }
    return out;
}

+ (NSString *)findAllMeshes {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData) return @"No XPK";
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    size_t totalSize = xpkData.length;
    NSMutableString *out = [NSMutableString string];
    
    // FULL XPK scan for xof signatures
    std::vector<size_t> offsets;
    for (size_t i = 0; i < totalSize - 12; i++) {
        if (bytes[i] == 'x' && bytes[i+1] == 'o' && bytes[i+2] == 'f' && bytes[i+3] == ' ' &&
            bytes[i+4] == '0' && bytes[i+5] == '3' && bytes[i+6] == '0') {
            offsets.push_back(i);
            i += 500;
        }
    }
    
    [out appendFormat:@"Total X-Files: %zu\n\n", offsets.size()];
    
    int bigCount = 0;
    for (size_t off : offsets) {
        @autoreleasepool {
            MeshData *mesh = [self extractMeshAtOffset:off];
            if (mesh && mesh.vertexCount > 200) {
                NSString *tex = mesh.textureName ? [mesh.textureName lastPathComponent] : @"(none)";
                [out appendFormat:@"@%zu: %d v, %d f, %@\n",
                 off, mesh.vertexCount, mesh.faceCount, tex];
                bigCount++;
            }
        }
    }
    
    [out appendFormat:@"\nBig meshes (>200v): %d\n", bigCount];
    return out;
}

+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData || offset >= xpkData.length) return nil;
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    if (decompressed.size() < 16) return nil;
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 3000);
    
    for (size_t i = 0; i < tokens.size(); i++) {
        if (tokens[i].type == 1 && tokens[i].name == "Mesh") {
            size_t j = i + 1;
            if (j < tokens.size() && tokens[j].type == 10) j++;
            if (j < tokens.size() && tokens[j].type == 6) j++;
            
            if (j >= tokens.size() || tokens[j].type != 7) continue;
            const auto& verts = tokens[j].floatList;
            if (verts.size() < 9) continue;
            
            MeshData *mesh = [[MeshData alloc] init];
            mesh.vertexCount = (int)(verts.size() / 3);
            mesh.vertices = [NSMutableData dataWithBytes:verts.data() length:verts.size() * 4];
            mesh.offset = offset;
            
            j++;
            
            if (j < tokens.size() && tokens[j].type == 6) {
                const auto& raw = tokens[j].intList;
                std::vector<uint32_t> tri;
                size_t p = 0;
                
                if (!raw.empty() && (raw[0] == 3 || raw[0] == 4)) {
                    while (p < raw.size()) {
                        uint32_t cnt = raw[p++];
                        if (cnt < 3 || cnt > 16 || p + cnt > raw.size()) break;
                        for (uint32_t k = 1; k + 1 < cnt; k++) {
                            tri.push_back((uint32_t)raw[p]);
                            tri.push_back((uint32_t)raw[p + k]);
                            tri.push_back((uint32_t)raw[p + k + 1]);
                        }
                        p += cnt;
                    }
                } else {
                    for (size_t k = 0; k + 2 < raw.size(); k += 3) {
                        tri.push_back((uint32_t)raw[k]);
                        tri.push_back((uint32_t)raw[k+1]);
                        tri.push_back((uint32_t)raw[k+2]);
                    }
                }
                
                size_t valid = 0;
                for (size_t k = 0; k < tri.size(); k++) {
                    if (tri[k] < (uint32_t)mesh.vertexCount) valid++;
                    else break;
                }
                valid = (valid / 3) * 3;
                tri.resize(valid);
                
                mesh.faceCount = (int)(tri.size() / 3);
                mesh.indices = [NSMutableData dataWithBytes:tri.data() length:tri.size() * sizeof(uint32_t)];
            }
            
            for (size_t k = i + 5; k < tokens.size() && k < i + 40; k++) {
                if (tokens[k].type == 1 && tokens[k].name == "MeshTextureCoords") {
                    size_t m = k + 1;
                    if (m < tokens.size() && tokens[m].type == 10) m++;
                    if (m < tokens.size() && tokens[m].type == 6) m++;
                    if (m < tokens.size() && tokens[m].type == 7) {
                        const auto& uvs = tokens[m].floatList;
                        if (uvs.size() >= (size_t)mesh.vertexCount * 2) {
                            mesh.uvs = [NSMutableData dataWithBytes:uvs.data() length:mesh.vertexCount * 2 * 4];
                        }
                    }
                    break;
                }
            }
            
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
    return nil;
}

@end
