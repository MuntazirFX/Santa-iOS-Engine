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

// ============ Skin Data Structures ============
struct SkinWeightsData {
    std::string boneName;
    std::vector<int> vertexIndices;
    std::vector<float> weights;
    Mat4 offsetMatrix;
};

struct MeshSkinData {
    int maxSkinWeightsPerVertex = 0;
    int maxSkinWeightsPerFace = 0;
    int nBones = 0;
    std::vector<SkinWeightsData> skins;
};

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

+ (MeshData *)extractSantaWithTransforms:(NSUInteger)offset {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData || offset >= xpkData.length) return nil;
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    if (decompressed.size() < 16) return nil;
    
    // ============ FIX 1: BOHOT ZYADA TOKENS ============
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 500000);
    NSLog(@"[Santa] Tokens: %lu", (unsigned long)tokens.size());
    
    // ============================================================
    // PASS 1: Frame hierarchy → boneWorldTransforms
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
        
        NSLog(@"[Santa] Bone transforms: %lu", (unsigned long)boneWorldTransforms.size());
    }
    
    // ============================================================
    // PASS 2: Extract meshes + parse skins + apply skinning
    // ============================================================
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIdx;
    
    int meshCount = 0;
    int skinnedMeshCount = 0;
    int totalSkinBlocks = 0;
    int missingBoneCount = 0;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        
        if (tok.type != 1 || tok.name != "Mesh") continue;
        
        // ============ Parse ONE Mesh block ============
        int depth = 0;
        bool entered = false;
        int meshEndIdx = (int)tokens.size();
        const std::vector<float>* meshVerts = nullptr;
        const std::vector<int>* meshFaces = nullptr;
        const std::vector<float>* meshUVs = nullptr;
        MeshSkinData skinData;
        
        for (size_t j = i + 1; j < tokens.size(); j++) {
            const auto& t = tokens[j];
            
            if (t.type == 10) { depth++; entered = true; continue; }
            if (t.type == 11) {
                depth--;
                if (entered && depth == 0) { meshEndIdx = (int)j; break; }
                continue;
            }
            
            // Vertices — first FLIST
            if (t.type == 7 && !meshVerts) { meshVerts = &t.floatList; continue; }
            
            // Faces — first ILIST after vertices
            if (t.type == 6 && meshVerts && !meshFaces) { meshFaces = &t.intList; continue; }
            
            // MeshTextureCoords
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
            
            // XSkinMeshHeader — read 3 values
            if (t.type == 1 && t.name == "XSkinMeshHeader") {
                int vals[3] = {0,0,0};
                int found = 0;
                for (size_t k = j + 1; k < tokens.size() && k < j + 12; k++) {
                    if (tokens[k].type == 11) { j = k; break; }
                    int v = -1;
                    if (tokens[k].type == 40) v = tokens[k].wordValue;
                    else if (tokens[k].type == 41) v = tokens[k].dwordValue;
                    else if (tokens[k].type == 3) v = tokens[k].intValue;
                    if (v >= 0 && found < 3) { vals[found++] = v; }
                    if (found == 3) {
                        // skip to closing brace
                        int d2 = 1;
                        for (size_t m = k + 1; m < tokens.size(); m++) {
                            if (tokens[m].type == 10) d2++;
                            else if (tokens[m].type == 11) { d2--; if (d2 == 0) { j = m; break; } }
                        }
                        break;
                    }
                }
                skinData.maxSkinWeightsPerVertex = vals[0];
                skinData.maxSkinWeightsPerFace = vals[1];
                skinData.nBones = vals[2];
                continue;
            }
            
            // SkinWeights — MULTIPLE blocks possible
            if (t.type == 1 && t.name == "SkinWeights") {
                SkinWeightsData sw;
                int d2 = 0; bool e2 = false;
                int state = 0;
                int weightCount = 0;
                int readCount = 0;
                std::vector<int> tempIndices;
                
                for (size_t k = j + 1; k < tokens.size(); k++) {
                    const auto& tt = tokens[k];
                    
                    if (tt.type == 10) { d2++; e2 = true; continue; }
                    if (tt.type == 11) {
                        d2--;
                        if (e2 && d2 == 0) { j = k; break; }
                        continue;
                    }
                    
                    if (state == 0) {
                        // Bone name STRING (type 2) — our parser stores in .name
                        if (tt.type == 2) { sw.boneName = tt.name; state = 1; }
                    } else if (state == 1) {
                        // nWeights — DWORD (41) or INT (3)
                        if (tt.type == 41) { weightCount = tt.dwordValue; state = 2; }
                        else if (tt.type == 3) { weightCount = tt.intValue; state = 2; }
                        else if (tt.type == 6) { // ILIST
                            for (int v : tt.intList) tempIndices.push_back(v);
                            weightCount = (int)tempIndices.size();
                            sw.vertexIndices = tempIndices;
                            state = 3;
                        }
                    } else if (state == 2) {
                        // Indices ILIST (6)
                        if (tt.type == 6) {
                            for (int v : tt.intList) sw.vertexIndices.push_back(v);
                            weightCount = (int)sw.vertexIndices.size();
                            state = 3;
                        }
                    } else if (state == 3) {
                        // Weights FLOAT_LIST (7)
                        if (tt.type == 7) {
                            sw.weights = tt.floatList;
                            state = 4;
                        }
                    } else if (state == 4) {
                        // Offset matrix FLIST (16 floats)
                        if (tt.type == 7 && tt.floatList.size() >= 16) {
                            sw.offsetMatrix = Mat4::fromFloats16(tt.floatList);
                            state = 5;
                            j = k;  // Skip to end of this FLIST
                            break;
                        }
                    }
                }
                
                if (!sw.boneName.empty() && !sw.vertexIndices.empty() && !sw.weights.empty()) {
                    skinData.skins.push_back(sw);
                    totalSkinBlocks++;
                }
                continue;
            }
        }
        
        // ============ Process this mesh ============
        if (meshVerts && meshVerts->size() >= 3) {
            int vc = (int)(meshVerts->size() / 3);
            int baseVertex = (int)(allVerts.size() / 3);
            
            std::vector<Vec3> localVerts(vc);
            for (int v = 0; v < vc; v++) {
                localVerts[v] = { (*meshVerts)[v*3], (*meshVerts)[v*3+1], (*meshVerts)[v*3+2] };
            }
            
            std::vector<Vec3> skinned(vc, {0,0,0});
            std::vector<float> weightSum(vc, 0.0f);
            bool anySkinApplied = false;
            
            if (!skinData.skins.empty()) {
                for (const auto& skin : skinData.skins) {
                    auto it = boneWorldTransforms.find(skin.boneName);
                    if (it == boneWorldTransforms.end()) {
                        missingBoneCount++;
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
                        anySkinApplied = true;
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
                
                if (anySkinApplied) skinnedMeshCount++;
            } else {
                skinned = localVerts;
            }
            
            // Add vertices
            for (int v = 0; v < vc; v++) {
                allVerts.push_back(skinned[v].x);
                allVerts.push_back(skinned[v].y);
                allVerts.push_back(skinned[v].z);
                
                if (!skinData.skins.empty() && anySkinApplied) {
                    allColors.push_back(1.0f);   // RED — skinned
                    allColors.push_back(0.2f);
                    allColors.push_back(0.2f);
                } else {
                    allColors.push_back(0.6f);   // GREY — not skinned
                    allColors.push_back(0.6f);
                    allColors.push_back(0.6f);
                }
            }
            
            // Faces
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
            NSLog(@"[Santa] Mesh %d: %d v, %lu skins, bones=%d",
                  meshCount, vc, (unsigned long)skinData.skins.size(), skinData.nBones);
        }
        
        // Skip to end of this Mesh block
        i = meshEndIdx;
    }
    
    NSLog(@"[Santa] === SUMMARY ===");
    NSLog(@"[Santa] Meshes: %d | Skinned: %d | Skin blocks: %d | Missing bones: %d",
          meshCount, skinnedMeshCount, totalSkinBlocks, missingBoneCount);
    NSLog(@"[Santa] Verts: %d | Faces: %d", (int)(allVerts.size() / 3), (int)(allIdx.size() / 3));
    
    if (allVerts.empty() || allIdx.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVerts.size() / 3);
    mesh.faceCount = (int)(allIdx.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVerts.data() length:allVerts.size() * 4];
    mesh.indices = [NSMutableData dataWithBytes:allIdx.data() length:allIdx.size() * sizeof(uint32_t)];
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    mesh.colors = [NSMutableData dataWithBytes:allColors.data() length:allColors.size() * 4];
    mesh.offset = offset;
    mesh.debugInfo = [NSString stringWithFormat:
                      @"%dM %dS %dSK %dMiss\n%d v, %d f | tokens=%lu",
                      meshCount, skinnedMeshCount, totalSkinBlocks, missingBoneCount,
                      mesh.vertexCount, mesh.faceCount, (unsigned long)tokens.size()];
    
    return mesh;
}

+ (NSString *)scanForSantaModel { return @"Disabled"; }
+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset {
    return [self extractSantaWithTransforms:offset];
}

@end
