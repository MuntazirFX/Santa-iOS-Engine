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
    [status appendString:@"Engine Started\n"];
    
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (resourcePath == nil) {
        [status appendString:@"ERROR: xmas.xpk not found!"];
        return status;
    }
    
    std::string xpkPath = [resourcePath UTF8String];
    AssetManager assetMgr;
    if (assetMgr.loadXPK(xpkPath)) {
        [status appendString:@"XPK Loaded!\n"];
    } else {
        [status appendString:@"XPK failed!"];
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
    if (offset >= xpkData.length) return @"Offset out of bounds";
    
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"=== .x at offset %lu ===\n\n", (unsigned long)offset];
    
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    
    // Show decompression debug log
    std::string debugStr = xpkDebugLog();
    [output appendString:[NSString stringWithUTF8String:debugStr.c_str()]];
    [output appendString:@"\n"];
    
    [output appendFormat:@"\nDecompressed size: %lu bytes\n\n", (unsigned long)decompressed.size()];
    
    if (decompressed.size() < 16) {
        [output appendString:@"Decompression failed!\n"];
        return output;
    }
    
    // First 32 bytes hex dump
    [output appendString:@"First 32 bytes:\n"];
    for (int i = 0; i < 32 && i < (int)decompressed.size(); i++) {
        [output appendFormat:@"%02x ", decompressed[i]];
        if ((i+1) % 16 == 0) [output appendString:@"\n"];
    }
    
    [output appendString:@"\nASCII: "];
    for (int i = 0; i < 32 && i < (int)decompressed.size(); i++) {
        char c = (char)decompressed[i];
        if (c >= 32 && c < 127) [output appendFormat:@"%c", c];
        else [output appendString:@"."];
    }
    [output appendString:@"\n\n"];
    
    // Parse tokens
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), maxTokens);
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
    
    std::vector<XToken> tokens = XFileParser::parseTokens(data.data(), data.size(), 2000);
    NSLog(@"[Mesh] Total tokens: %lu", (unsigned long)tokens.size());
    
    for (size_t i = 0; i < tokens.size(); i++) {
        if (tokens[i].type == 1 && tokens[i].name == "Mesh") {
            size_t j = i + 1;
            if (j < tokens.size() && tokens[j].type == 10) j++; // {
            if (j < tokens.size() && tokens[j].type == 6) j++; // ILIST (material)
            
            if (j >= tokens.size() || tokens[j].type != 7) continue;
            const auto& verts = tokens[j].floatList;
            if (verts.size() < 9) continue;
            
            MeshData *mesh = [[MeshData alloc] init];
            mesh.vertexCount = (int)(verts.size() / 3);
            mesh.vertices = [NSMutableData dataWithBytes:verts.data() length:verts.size() * 4];
            
            NSLog(@"[Mesh] Vertices: %d", mesh.vertexCount);
            
            j++;
            
            // Read face indices ILIST
            if (j < tokens.size() && tokens[j].type == 6) {
                const auto& raw = tokens[j].intList;
                NSLog(@"[Mesh] Raw face data: %zu ints", raw.size());
                
                std::vector<uint32_t> triangles;
                size_t p = 0;
                
                // Check if count-prefixed format
                if (!raw.empty() && (raw[0] == 3 || raw[0] == 4)) {
                    while (p < raw.size()) {
                        uint32_t cnt = raw[p++];
                        if (cnt < 3 || cnt > 16 || p + cnt > raw.size()) break;
                        
                        // Fan triangulation
                        for (uint32_t k = 1; k + 1 < cnt; k++) {
                            triangles.push_back((uint32_t)raw[p]);
                            triangles.push_back((uint32_t)raw[p + k]);
                            triangles.push_back((uint32_t)raw[p + k + 1]);
                        }
                        p += cnt;
                    }
                    NSLog(@"[Mesh] Count-prefixed triangles: %zu", triangles.size() / 3);
                } else {
                    // Plain triangle list
                    for (size_t k = 0; k + 2 < raw.size(); k += 3) {
                        triangles.push_back((uint32_t)raw[k]);
                        triangles.push_back((uint32_t)raw[k+1]);
                        triangles.push_back((uint32_t)raw[k+2]);
                    }
                    NSLog(@"[Mesh] Plain triangles: %zu", triangles.size() / 3);
                }
                
                // Sanitize indices (avoid GPU crash)
                size_t validCount = 0;
                for (size_t k = 0; k < triangles.size(); k++) {
                    if (triangles[k] < (uint32_t)mesh.vertexCount) {
                        validCount++;
                    } else {
                        break;
                    }
                }
                validCount = (validCount / 3) * 3;
                triangles.resize(validCount);
                
                mesh.faceCount = (int)(triangles.size() / 3);
                mesh.indices = [NSMutableData dataWithBytes:triangles.data() length:triangles.size() * sizeof(uint32_t)];
                NSLog(@"[Mesh] Valid triangles: %d", mesh.faceCount);
            }
            
            // UVs (optional)
            for (size_t k = i + 5; k < tokens.size() && k < i + 40; k++) {
                if (tokens[k].type == 1 && tokens[k].name == "MeshTextureCoords") {
                    size_t m = k + 1;
                    if (m < tokens.size() && tokens[m].type == 10) m++;
                    if (m < tokens.size() && tokens[m].type == 6) m++;
                    if (m < tokens.size() && tokens[m].type == 7) {
                        const auto& uvs = tokens[m].floatList;
                        if (uvs.size() >= (size_t)mesh.vertexCount * 2) {
                            mesh.uvs = [NSMutableData dataWithBytes:uvs.data() length:mesh.vertexCount * 2 * 4];
                            NSLog(@"[Mesh] UVs extracted: %d pairs", mesh.vertexCount);
                        }
                    }
                    break;
                }
            }
            
            // Texture name (optional)
            for (size_t k = i + 5; k < tokens.size() && k < i + 100; k++) {
                if (tokens[k].type == 1 && tokens[k].name == "TextureFilename") {
                    if (k + 2 < tokens.size() && tokens[k+2].type == 2) {
                        mesh.textureName = [NSString stringWithUTF8String:tokens[k+2].name.c_str()];
                        NSLog(@"[Mesh] Texture: %@", mesh.textureName);
                    }
                    break;
                }
            }
            
            return mesh;
        }
    }
    
    NSLog(@"[Mesh] No Mesh template found");
    return nil;
}

@end
