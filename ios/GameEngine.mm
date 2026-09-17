#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>

// ============ C++ Helpers (OUTSIDE @implementation!) ============
struct Vec3 { float x, y, z; };

struct Mat4 {
    float m[4][4];
    static Mat4 identity() {
        Mat4 r{};
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                r.m[i][j] = (i == j) ? 1.0f : 0.0f;
        return r;
    }
    // Row-major read (matches 3:11 working state)
    static Mat4 fromFloats16(const std::vector<float>& f) {
        Mat4 r{};
        for (int i = 0; i < 16; i++) r.m[i / 4][i % 4] = f[i];
        return r;
    }
};

static Mat4 mulMat(const Mat4& a, const Mat4& b) {
    Mat4 r{};
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            float s = 0;
            for (int k = 0; k < 4; k++) s += a.m[i][k] * b.m[k][j];
            r.m[i][j] = s;
        }
    return r;
}

static Vec3 transformPoint(const Vec3& v, const Mat4& M) {
    float x = v.x*M.m[0][0] + v.y*M.m[1][0] + v.z*M.m[2][0] + M.m[3][0];
    float y = v.x*M.m[0][1] + v.y*M.m[1][1] + v.z*M.m[2][1] + M.m[3][1];
    float z = v.x*M.m[0][2] + v.y*M.m[1][2] + v.z*M.m[2][2] + M.m[3][2];
    float w = v.x*M.m[0][3] + v.y*M.m[1][3] + v.z*M.m[2][3] + M.m[3][3];
    if (std::fabs(w) > 1e-6f && std::fabs(w - 1.0f) > 1e-6f) {
        x /= w; y /= w; z /= w;
    }
    return { x, y, z };
}

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
    NSLog(@"[Santa] Tokens: %lu", (unsigned long)tokens.size());
    
    std::vector<Mat4> worldStack;
    worldStack.push_back(Mat4::identity());
    
    std::vector<char> braceKind;
    bool pendingFrame = false;
    
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<uint32_t> allIdx;
    std::string foundTexture;
    int meshCount = 0;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        
        // Frame start
        if (tok.type == 1 && tok.name == "Frame") {
            pendingFrame = true;
            continue;
        }
        
        // Open brace
        if (tok.type == 10) {
            if (pendingFrame) {
                worldStack.push_back(worldStack.back());
                braceKind.push_back('F');
                pendingFrame = false;
            } else {
                braceKind.push_back('O');
            }
            continue;
        }
        
        // Close brace
        if (tok.type == 11) {
            if (!braceKind.empty()) {
                char kind = braceKind.back();
                braceKind.pop_back();
                if (kind == 'F') worldStack.pop_back();
            }
            continue;
        }
        
        // FrameTransformMatrix — read 16 floats, swap multiply order
        if (tok.type == 1 && tok.name == "FrameTransformMatrix") {
            for (size_t j = i + 1; j < std::min(tokens.size(), i + 6); j++) {
                if (tokens[j].type == 7 && tokens[j].floatList.size() >= 16) {
                    Mat4 local = Mat4::fromFloats16(tokens[j].floatList);
                    Mat4 parentWorld = worldStack.back();
                    worldStack.back() = mulMat(parentWorld, local);
                    break;
                }
            }
            continue;
        }
        
        // Texture filename (first one wins)
        if (tok.type == 1 && tok.name == "TextureFilename" && foundTexture.empty()) {
            for (size_t j = i + 1; j < std::min(tokens.size(), i + 5); j++) {
                if (tokens[j].type == 2 && !tokens[j].name.empty()) {
                    foundTexture = tokens[j].name;
                    break;
                }
            }
            continue;
        }
        
        // Mesh
        if (tok.type == 1 && tok.name == "Mesh") {
            Mat4 world = worldStack.back();
            
            int depth = 0;
            bool entered = false;
            const std::vector<float>* meshVerts = nullptr;
            const std::vector<int>* meshFaces = nullptr;
            const std::vector<float>* meshUVs = nullptr;
            
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
            }
            
            if (meshVerts && meshVerts->size() >= 3) {
                int baseVertex = (int)(allVerts.size() / 3);
                int vc = (int)(meshVerts->size() / 3);
                
                for (int v = 0; v < vc; v++) {
                    Vec3 local{ (*meshVerts)[v*3], (*meshVerts)[v*3+1], (*meshVerts)[v*3+2] };
                    Vec3 worldPos = transformPoint(local, world);
                    allVerts.push_back(worldPos.x);
                    allVerts.push_back(worldPos.y);
                    allVerts.push_back(worldPos.z);
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
                
                meshCount++;
                NSLog(@"[Santa] Mesh %d: %d v (total %d v, %d idx)",
                      meshCount, vc, (int)(allVerts.size()/3), (int)allIdx.size());
            }
        }
    }
    
    if (allVerts.empty() || allIdx.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVerts.size() / 3);
    mesh.faceCount = (int)(allIdx.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVerts.data() length:allVerts.size() * 4];
    mesh.indices = [NSMutableData dataWithBytes:allIdx.data() length:allIdx.size() * sizeof(uint32_t)];
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    mesh.offset = offset;
    if (!foundTexture.empty()) {
        mesh.textureName = [NSString stringWithUTF8String:foundTexture.c_str()];
    }
    
    NSLog(@"[Santa] Final: %d meshes, %d v, %d f, tex=%@",
          meshCount, mesh.vertexCount, mesh.faceCount, mesh.textureName ?: @"(none)");
    
    return mesh;
}

+ (NSString *)scanForSantaModel {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData) return @"No XPK data";
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    size_t totalSize = xpkData.length;
    
    std::vector<size_t> offsets;
    for (size_t i = 0; i + 4 < totalSize; i++) {
        if (bytes[i]=='x' && bytes[i+1]=='o' && bytes[i+2]=='f' && bytes[i+3]==' ') {
            offsets.push_back(i);
            i += 200;
        }
    }
    return [NSString stringWithFormat:@"Found %zu xof files", offsets.size()];
}

+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset {
    return [self extractSantaWithTransforms:offset];
}

@end
