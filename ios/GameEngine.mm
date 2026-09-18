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

@implementation MeshData
@end

@implementation LevelObject
@end

@implementation GameEngine

// ============ ASSET LOADING ============
+ (NSData *)loadAssetNamed:(NSString *)name {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return nil;
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return nil;
    std::vector<uint8_t> d = am.getAssetData([name UTF8String]);
    if (d.empty()) return nil;
    return [NSData dataWithBytes:d.data() length:d.size()];
}

// ============ List all levels/*.dat files ============
+ (NSString *)listLevelFiles {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return @"No XPK";
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return @"XPK load failed";
    std::vector<std::string> all = am.getAllFilenames();
    NSMutableString *out = [NSMutableString string];
    for (const auto& n : all) {
        if (n.find("levels\\") != std::string::npos || n.find("levels/") != std::string::npos) {
            [out appendFormat:@"%s\n", n.c_str()];
        }
    }
    return out;
}

// ============ LOAD SANTA MESH (from named asset) ============
+ (MeshData *)extractMeshFromAsset:(NSString *)assetName {
    // Load the file by name from XPK
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return nil;
    
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return nil;
    
    std::string name = [assetName UTF8String];
    std::vector<uint8_t> fileData = am.getAssetData(name);
    if (fileData.empty()) {
        NSLog(@"[Santa] Asset not found: %@", assetName);
        return nil;
    }
    
    NSLog(@"[Santa] File loaded: %lu bytes", (unsigned long)fileData.size());
    
    // Decompress .x file
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(fileData.data(), fileData.size());
    if (decompressed.size() < 16) return nil;
    
    NSLog(@"[Santa] Decompressed: %lu bytes", (unsigned long)decompressed.size());
    
    // Parse tokens
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 500000);
    NSLog(@"[Santa] Tokens: %lu", (unsigned long)tokens.size());
    
    // ============================================================
    // PASS 1: Frame hierarchy → boneWorldTransforms map
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
    
    NSLog(@"[Santa] Bones: %lu", (unsigned long)boneWorldTransforms.size());
    
    // ============================================================
    // PASS 2: Extract Mesh + apply skinning
    // ============================================================
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIdx;
    
    int meshCount = 0;
    int totalSkinBlocks = 0;
    int missingBoneCount = 0;
    int totalVertices = 0;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        if (tok.type != 1 || tok.name != "Mesh") continue;
        
        // ===== Parse Mesh template =====
        int depth = 0;
        bool entered = false;
        int meshEndIdx = (int)tokens.size();
        const std::vector<float>* meshVerts = nullptr;
        const std::vector<int>* meshFaces = nullptr;
        const std::vector<float>* meshUVs = nullptr;
        std::vector<SkinWeightsData> skins;
        
        // === FIX: Declared counts for vertices and faces ===
        int declaredVertices = 0;
        int declaredFaces = 0;
        
        for (size_t j = i + 1; j < tokens.size(); j++) {
            const auto& t = tokens[j];
            
            if (t.type == 10) { depth++; entered = true; continue; }
            if (t.type == 11) {
                depth--;
                if (entered && depth == 0) { meshEndIdx = (int)j; break; }
                continue;
            }
            
            // === FIX: Lookahead to correctly capture nVertices and nFaces ===
            // We only capture these if the VERY NEXT token is the actual array.
            // This prevents grabbing random integers (like material indices).
            if ((t.type == 3 || t.type == 41) && j + 1 < tokens.size()) {
                const auto& nextTok = tokens[j + 1];
                
                // nVertices -> followed by FLIST (Type 7)
                if (nextTok.type == 7 && meshVerts == nullptr) {
                    declaredVertices = (t.type == 3) ? t.intValue : t.dwordValue;
                    continue;
                }
                
                // nFaces -> followed by ILIST (Type 6)
                if (nextTok.type == 6 && meshVerts != nullptr && meshFaces == nullptr) {
                    declaredFaces = (t.type == 3) ? t.intValue : t.dwordValue;
                    continue;
                }
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
            
            // SkinWeights — one block per bone.
            if (t.type == 1 && t.name == "SkinWeights") {
                SkinWeightsData sw;
                std::vector<float> rawWeights;
                int d2 = 0; bool e2 = false;
                int state = 0; // 0=need name, 1=need vertex indices, 2=need weights+matrix blob
                
                for (size_t k = j + 1; k < tokens.size(); k++) {
                    const auto& tt = tokens[k];
                    
                    if (tt.type == 10) { d2++; e2 = true; continue; }
                    if (tt.type == 11) {
                        d2--;
                        if (e2 && d2 == 0) { j = k; break; }
                        continue;
                    }
                    
                    if (state == 0) {
                        if (tt.type == 2) { sw.boneName = tt.name; state = 1; }
                    } else if (state == 1) {
                        if (tt.type == 6) {
                            for (int v : tt.intList) sw.vertexIndices.push_back(v);
                            state = 2;
                        }
                    } else if (state == 2) {
                        if (tt.type == 7) {
                            rawWeights = tt.floatList;
                            state = 3;
                        }
                    }
                }
                
                if (!rawWeights.empty() && rawWeights.size() >= sw.vertexIndices.size()) {
                    size_t nW = sw.vertexIndices.size();
                    sw.weights.assign(rawWeights.begin(), rawWeights.begin() + nW);
                    std::vector<float> tail(rawWeights.begin() + nW, rawWeights.end());
                    if (tail.size() >= 16) {
                        sw.offsetMatrix = Mat4::fromFloats16(std::vector<float>(tail.end() - 16, tail.end()));
                    } else if (!tail.empty()) {
                        std::vector<float> padded(16, 0.0f);
                        std::copy(tail.begin(), tail.end(), padded.begin() + (16 - tail.size()));
                        sw.offsetMatrix = Mat4::fromFloats16(padded);
                    } else {
                        sw.offsetMatrix = Mat4::identity();
                    }
                }
                
                if (!sw.boneName.empty() && !sw.vertexIndices.empty() && !sw.weights.empty()) {
                    skins.push_back(sw);
                    totalSkinBlocks++;
                }
                continue;
            }
        }
        
        // ===== Extract vertices + apply skinning =====
        if (meshVerts && meshVerts->size() >= 3) {
            // === FIX: STRIDE HANDLING ===
            // Use declaredVertices to figure out stride (3 floats or 4 floats per vertex)
            int stride = 3;
            if (declaredVertices > 0) {
                if (meshVerts->size() == (size_t)declaredVertices * 4) stride = 4;
                else if (meshVerts->size() == (size_t)declaredVertices * 3) stride = 3;
            }
            int vc = declaredVertices > 0 ? declaredVertices : (int)(meshVerts->size() / stride);
            
            int baseVertex = (int)(allVerts.size() / 3);
            totalVertices += vc;
            
            std::vector<Vec3> localVerts(vc);
            for (int v = 0; v < vc; v++) {
                // Use correct stride so vertices don't stretch/shift
                localVerts[v] = { (*meshVerts)[v*stride], (*meshVerts)[v*stride+1], (*meshVerts)[v*stride+2] };
            }
            
            std::vector<Vec3> skinned(vc, {0,0,0});
            std::vector<float> weightSum(vc, 0.0f);
            bool anySkin = false;
            
            for (const auto& skin : skins) {
                auto it = boneWorldTransforms.find(skin.boneName);
                if (it == boneWorldTransforms.end()) {
                    missingBoneCount++;
                    NSLog(@"[Santa] Missing bone: %s", skin.boneName.c_str());
                    continue;
                }
                
                Mat4 boneMatrix = mulMat(skin.offsetMatrix, it->second);
                
                for (size_t k = 0; k < skin.vertexIndices.size() && k < skin.weights.size(); k++) {
                    int vi = skin.vertexIndices[k];
                    float w = skin.weights[k];
                    if (vi < 0 || vi >= vc) continue;
                    
                    Vec3 t = transformPoint(localVerts[vi], boneMatrix);
                    skinned[vi].x += w * t.x;
                    skinned[vi].y += w * t.y;
                    skinned[vi].z += w * t.z;
                    weightSum[vi] += w;
                    anySkin = true;
                }
            }
            
            for (int v = 0; v < vc; v++) {
                if (weightSum[v] < 1e-6f) {
                    skinned[v] = localVerts[v];
                } else if (std::fabs(weightSum[v] - 1.0f) > 1e-3f) {
                    float inv = 1.0f / weightSum[v];
                    skinned[v].x *= inv;
                    skinned[v].y *= inv;
                    skinned[v].z *= inv;
                }
            }
            
            // Vertices — red if skinned
            for (int v = 0; v < vc; v++) {
                allVerts.push_back(skinned[v].x);
                allVerts.push_back(skinned[v].y);
                allVerts.push_back(skinned[v].z);
                
                if (anySkin) {
                    allColors.push_back(1.0f);
                    allColors.push_back(0.2f);
                    allColors.push_back(0.2f);
                } else {
                    allColors.push_back(0.6f);
                    allColors.push_back(0.6f);
                    allColors.push_back(0.6f);
                }
            }
            
            // === FIX: FACE FORMAT HANDLING ===
            if (meshFaces) {
                const auto& raw = *meshFaces;
                
                // If declaredFaces is known and matches exactly, it's a Triangle List
                bool isTriangleList = (declaredFaces > 0 && raw.size() == (size_t)declaredFaces * 3);
                
                if (isTriangleList) {
                    // Simple Triangle List
                    for (size_t k = 0; k + 2 < raw.size(); k += 3) {
                        allIdx.push_back((uint32_t)raw[k] + baseVertex);
                        allIdx.push_back((uint32_t)raw[k+1] + baseVertex);
                        allIdx.push_back((uint32_t)raw[k+2] + baseVertex);
                    }
                } else {
                    // Standard .x Polygon List (first integer is vertex count)
                    size_t p = 0;
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
                }
            }
            
            // UVs
            if (meshUVs && meshUVs->size() >= (size_t)vc * 2) {
                allUVs.insert(allUVs.end(), meshUVs->begin(), meshUVs->begin() + vc * 2);
            } else {
                for (int u = 0; u < vc; u++) {
                    allUVs.push_back(0.5f);
                    allUVs.push_back(0.5f);
                }
            }
            
            meshCount++;
        }
        
        i = meshEndIdx;
    }
    
    NSLog(@"[Santa] Meshes: %d | SkinBlocks: %d | MissingBones: %d | Verts: %d",
          meshCount, totalSkinBlocks, missingBoneCount, totalVertices);
    
    if (allVerts.empty() || allIdx.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVerts.size() / 3);
    mesh.faceCount = (int)(allIdx.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVerts.data() length:allVerts.size() * 4];
    mesh.indices = [NSMutableData dataWithBytes:allIdx.data() length:allIdx.size() * sizeof(uint32_t)];
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    mesh.colors = [NSMutableData dataWithBytes:allColors.data() length:allColors.size() * 4];
    mesh.offset = 0;
    mesh.debugInfo = [NSString stringWithFormat:
                      @"%@\n%dM %dSK %dMiss\n%d v, %d f",
                      assetName, meshCount, totalSkinBlocks, missingBoneCount,
                      mesh.vertexCount, mesh.faceCount];
    
    return mesh;
}

// ============ LEVEL DATA PARSER (Skeleton) ============
+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath {
    NSData *data = [self loadAssetNamed:levelPath];
    if (!data) return @[];
    
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger totalSize = data.length;
    
    NSLog(@"[Level] %@: %lu bytes", levelPath, (unsigned long)totalSize);
    
    // Known object names from level data
    NSArray *knownNames = @[@"EXTRA LIFE", @"JUMPER", @"PRESENT A",
                             @"EXIT", @"TROLL", @"HAUS", @"TREE",
                             @"KAMIN", @"PRESENT", @"TURM", @"HILL"];
    
    NSMutableArray<LevelObject *> *objects = [NSMutableArray array];
    
    for (NSUInteger i = 0; i + 8 < totalSize; i++) {
        for (NSString *name in knownNames) {
            NSData *nameData = [name dataUsingEncoding:NSASCIIStringEncoding];
            if (i + nameData.length > totalSize) continue;
            if (memcmp(bytes + i, nameData.bytes, nameData.length) == 0) {
                LevelObject *obj = [[LevelObject alloc] init];
                obj.objectName = name;
                obj.x = 0; obj.y = 0; obj.z = 0;
                [objects addObject:obj];
                NSLog(@"[Level] Found '%@' at offset %lu", name, (unsigned long)i);
                i += nameData.length;
                break;
            }
        }
    }
    
    NSLog(@"[Level] Total objects found: %lu", (unsigned long)objects.count);
    return objects;
}

@end
