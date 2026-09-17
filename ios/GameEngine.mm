#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>

struct Vec3 { float x, y, z; };

// ============ MeshData Implementation ============
@implementation MeshData
@end

// ============ GameEngine Implementation ============
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

+ (MeshData *)extractSantaWithTransforms:(NSUInteger)offset {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData || offset >= xpkData.length) return nil;
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    if (decompressed.size() < 16) return nil;
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 20000);
    NSLog(@"[Diag] Tokens: %lu", (unsigned long)tokens.size());
    
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIdx;
    
    int meshCount = 0;
    int skinCount = 0;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        
        if (tok.type == 1 && tok.name == "Mesh") {
            int depth = 0;
            bool entered = false;
            const std::vector<float>* meshVerts = nullptr;
            const std::vector<int>* meshFaces = nullptr;
            const std::vector<float>* meshUVs = nullptr;
            int skinBlocksInThisMesh = 0;
            
            for (size_t j = i + 1; j < tokens.size(); j++) {
                if (tokens[j].type == 10) { depth++; entered = true; continue; }
                if (tokens[j].type == 11) {
                    depth--;
                    if (entered && depth == 0) break;
                    continue;
                }
                if (tokens[j].type == 7 && !meshVerts) { meshVerts = &tokens[j].floatList; continue; }
                if (tokens[j].type == 6 && meshVerts && !meshFaces) { meshFaces = &tokens[j].intList; continue; }
                if (tokens[j].type == 1 && tokens[j].name == "MeshTextureCoords") {
                    int d2 = 0; bool e2 = false;
                    for (size_t k = j + 1; k < tokens.size(); k++) {
                        if (tokens[k].type == 10) { d2++; e2 = true; continue; }
                        if (tokens[k].type == 11) {
                            d2--;
                            if (e2 && d2 == 0) break;
                            continue;
                        }
                        if (tokens[k].type == 7) { meshUVs = &tokens[k].floatList; break; }
                    }
                }
                if (tokens[j].type == 1 && tokens[j].name == "SkinWeights") {
                    skinBlocksInThisMesh++;
                }
            }
            
            if (meshVerts && meshVerts->size() >= 3) {
                int vc = (int)(meshVerts->size() / 3);
                
                // ============ DIAGNOSTIC: Bounding box ============
                float minX = 1e9, maxX = -1e9;
                float minY = 1e9, maxY = -1e9;
                float minZ = 1e9, maxZ = -1e9;
                for (int v = 0; v < vc; v++) {
                    float x = (*meshVerts)[v*3];
                    float y = (*meshVerts)[v*3+1];
                    float z = (*meshVerts)[v*3+2];
                    if (x < minX) minX = x; if (x > maxX) maxX = x;
                    if (y < minY) minY = y; if (y > maxY) maxY = y;
                    if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
                }
                
                meshCount++;
                NSLog(@"[Diag] Mesh %d: %d v, skin blocks=%d", meshCount, vc, skinBlocksInThisMesh);
                NSLog(@"[Diag]   BBox X: %.3f to %.3f (size %.3f)", minX, maxX, maxX - minX);
                NSLog(@"[Diag]   BBox Y: %.3f to %.3f (size %.3f)", minY, maxY, maxY - minY);
                NSLog(@"[Diag]   BBox Z: %.3f to %.3f (size %.3f)", minZ, maxZ, maxZ - minZ);
                
                // ============ Render RAW (no transform) ============
                int baseVertex = (int)(allVerts.size() / 3);
                
                for (int v = 0; v < vc; v++) {
                    allVerts.push_back((*meshVerts)[v*3]);
                    allVerts.push_back((*meshVerts)[v*3+1]);
                    allVerts.push_back((*meshVerts)[v*3+2]);
                    
                    // Color per mesh
                    float colors[8][3] = {
                        {1.0, 0.3, 0.3}, {0.3, 1.0, 0.3}, {0.3, 0.3, 1.0}, {1.0, 1.0, 0.3},
                        {1.0, 0.3, 1.0}, {0.3, 1.0, 1.0}, {1.0, 0.6, 0.2}, {0.6, 0.3, 1.0}
                    };
                    float *c = colors[(meshCount - 1) % 8];
                    allColors.push_back(c[0]);
                    allColors.push_back(c[1]);
                    allColors.push_back(c[2]);
                }
                
                if (meshFaces) {
                    const auto& raw = *meshFaces;
                    size_t p = 0;
                    if (!raw.empty() && (raw[0] == 3 || raw[0] == 4)) {
                        while (p < raw.size()) {
                            uint32_t cnt = raw[p++];
                            if (cnt < 3 || cnt > 16 || p + cnt > raw.size()) break;
                            for (uint32_t k = 1; k + 1 < cnt; k++) {
                                allIdx.push_back((uint32_t)raw[p] + baseVertex);
                                allIdx.push_back((uint32_t)raw[p + k] + baseVertex);
                                allIdx.push_back((uint32_t)raw[p + k + 1] + baseVertex);
                            }
                            p += cnt;
                        }
                    } else {
                        for (size_t k = 0; k + 2 < raw.size(); k += 3) {
                            allIdx.push_back((uint32_t)raw[k] + baseVertex);
                            allIdx.push_back((uint32_t)raw[k+1] + baseVertex);
                            allIdx.push_back((uint32_t)raw[k+2] + baseVertex);
                        }
                    }
                }
                
                if (meshUVs && meshUVs->size() >= (size_t)vc * 2) {
                    allUVs.insert(allUVs.end(), meshUVs->begin(), meshUVs->begin() + vc * 2);
                } else {
                    for (int u = 0; u < vc; u++) {
                        allUVs.push_back(0.5f);
                        allUVs.push_back(0.5f);
                    }
                }
                
                skinCount += skinBlocksInThisMesh;
            }
        }
    }
    
    NSLog(@"[Diag] === SUMMARY ===");
    NSLog(@"[Diag] Total meshes: %d", meshCount);
    NSLog(@"[Diag] Total skin blocks: %d", skinCount);
    NSLog(@"[Diag] Total vertices: %d", (int)(allVerts.size() / 3));
    
    if (allVerts.empty() || allIdx.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVerts.size() / 3);
    mesh.faceCount = (int)(allIdx.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVerts.data() length:allVerts.size() * 4];
    mesh.indices = [NSMutableData dataWithBytes:allIdx.data() length:allIdx.size() * sizeof(uint32_t)];
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    mesh.colors = [NSMutableData dataWithBytes:allColors.data() length:allColors.size() * 4];
    mesh.offset = offset;
    
    return mesh;
}

+ (NSString *)scanForSantaModel { return @"Disabled"; }
+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset {
    return [self extractSantaWithTransforms:offset];
}

@end
