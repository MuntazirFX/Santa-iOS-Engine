#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include <unordered_map>

// ============ Math Helpers ============
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

struct SkinWeightsData {
    std::string boneName;
    std::vector<int> vertexIndices;
    std::vector<float> weights;
    Mat4 offsetMatrix;
};

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
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 500000);
    NSLog(@"[Santa] Tokens: %lu", (unsigned long)tokens.size());
    
    // ============================================================
    // DEBUG: Pehle 2 Mesh ke andar ke block names
    // ============================================================
    NSMutableString *dbg = [NSMutableString string];
    [dbg appendFormat:@"Tok=%lu\n", (unsigned long)tokens.size()];
    
    int meshFound = 0;
    for (size_t i = 0; i < tokens.size() && meshFound < 2; i++) {
        const auto& tok = tokens[i];
        if (tok.type != 1 || tok.name != "Mesh") continue;
        
        meshFound++;
        [dbg appendFormat:@"M%d: ", meshFound];
        
        int depth = 0;
        bool entered = false;
        int blockCount = 0;
        int swCount = 0;
        int shCount = 0;
        
        for (size_t j = i + 1; j < tokens.size() && blockCount < 15; j++) {
            const auto& t = tokens[j];
            if (t.type == 10) { depth++; entered = true; continue; }
            if (t.type == 11) {
                depth--;
                if (entered && depth == 0) break;
                continue;
            }
            if (depth == 1 && t.type == 1) {
                [dbg appendFormat:@"%s,", t.name.c_str()];
                blockCount++;
                if (t.name == "SkinWeights") swCount++;
                if (t.name == "XSkinMeshHeader") shCount++;
            }
        }
        [dbg appendFormat:@" [SW=%d SH=%d]\n", swCount, shCount];
    }
    
    // ============================================================
    // PASS 1: Frame hierarchy → boneWorldTransforms (for later use)
    // ============================================================
    std::unordered_map<std::string, Mat4> boneWorldTransforms;
    
    {
        std::vector<Mat4> worldStack;
        worldStack.push_back(Mat4::identity());
        std::vector<char> braceKind;
        std::vector<std::string> frameNameStack;
        std::string pendingFrameName = "";
        bool pendingFrame = false;
        
        for (size_t i = 0; i < tokens.size(); i++) {
            const auto& tok = tokens[i];
            
            if (tok.type == 1 && tok.name == "Frame") {
                pendingFrame = true;
                continue;
            }
            if (pendingFrame && tok.type == 1) {
                pendingFrameName = tok.name;
                pendingFrame = false;
                continue;
            }
            if (tok.type == 10) {
                if (!pendingFrameName.empty()) {
                    worldStack.push_back(worldStack.back());
                    braceKind.push_back('F');
                    frameNameStack.push_back(pendingFrameName);
                    pendingFrameName = "";
                } else {
                    braceKind.push_back('O');
                    frameNameStack.push_back("");
                }
                continue;
            }
            if (tok.type == 11) {
                if (!braceKind.empty()) {
                    char kind = braceKind.back();
                    braceKind.pop_back();
                    if (kind == 'F') {
                        if (!frameNameStack.empty() && !frameNameStack.back().empty()) {
                            boneWorldTransforms[frameNameStack.back()] = worldStack.back();
                        }
                        worldStack.pop_back();
                    }
                    if (!frameNameStack.empty()) frameNameStack.pop_back();
                }
                continue;
            }
            if (tok.type == 1 && tok.name == "FrameTransformMatrix") {
                for (size_t j = i + 1; j < std::min(tokens.size(), i + 6); j++) {
                    if (tokens[j].type == 7 && tokens[j].floatList.size() >= 16) {
                        Mat4 local = Mat4::fromFloats16(tokens[j].floatList);
                        Mat4 parentWorld = worldStack.back();
                        worldStack.back() = mulMat(local, parentWorld);
                        break;
                    }
                }
                continue;
            }
        }
    }
    
    [dbg appendFormat:@"Bones: %lu\n", (unsigned long)boneWorldTransforms.size()];
    
    // ============================================================
    // PASS 2: Render Mesh 1 raw (no skin, for now)
    // ============================================================
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIdx;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        if (tok.type != 1 || tok.name != "Mesh") continue;
        
        int depth = 0;
        bool entered = false;
        int meshEndIdx = (int)tokens.size();
        const std::vector<float>* meshVerts = nullptr;
        const std::vector<int>* meshFaces = nullptr;
        const std::vector<float>* meshUVs = nullptr;
        
        for (size_t j = i + 1; j < tokens.size(); j++) {
            const auto& t = tokens[j];
            if (t.type == 10) { depth++; entered = true; continue; }
            if (t.type == 11) {
                depth--;
                if (entered && depth == 0) { meshEndIdx = (int)j; break; }
                continue;
            }
            if (t.type == 7 && !meshVerts) { meshVerts = &t.floatList; continue; }
            if (t.type == 6 && meshVerts && !meshFaces) { meshFaces = &t.intList; continue; }
            if (t.type == 1 && t.name == "MeshTextureCoords") {
                int d2 = 0; bool e2 = false;
                for (size_t k = j + 1; k < tokens.size(); k++) {
                    if (tokens[k].type == 10) { d2++; e2 = true; continue; }
                    if (tokens[k].type == 11) {
                        d2--;
                        if (e2 && d2 == 0) { j = k; break; }
                        continue;
                    }
                    if (tokens[k].type == 7) { meshUVs = &tokens[k].floatList; j = k; break; }
                }
                continue;
            }
        }
        
        if (meshVerts && meshVerts->size() >= 3) {
            int vc = (int)(meshVerts->size() / 3);
            int baseVertex = (int)(allVerts.size() / 3);
            
            for (int v = 0; v < vc; v++) {
                allVerts.push_back((*meshVerts)[v*3]);
                allVerts.push_back((*meshVerts)[v*3+1]);
                allVerts.push_back((*meshVerts)[v*3+2]);
                allColors.push_back(0.7f);
                allColors.push_back(0.7f);
                allColors.push_back(0.7f);
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
            
            break;  // Sirf Mesh 1
        }
        
        i = meshEndIdx;
    }
    
    if (allVerts.empty() || allIdx.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVerts.size() / 3);
    mesh.faceCount = (int)(allIdx.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVerts.data() length:allVerts.size() * 4];
    mesh.indices = [NSMutableData dataWithBytes:allIdx.data() length:allIdx.size() * sizeof(uint32_t)];
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    mesh.colors = [NSMutableData dataWithBytes:allColors.data() length:allColors.size() * 4];
    mesh.offset = offset;
    mesh.debugInfo = dbg;
    
    return mesh;
}

+ (NSString *)scanForSantaModel { return @"Disabled"; }
+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset {
    return [self extractSantaWithTransforms:offset];
}

@end
