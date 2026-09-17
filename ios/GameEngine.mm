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
    // Row-major read (D3DMATRIX spec)
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
    
    // ============================================================
    // PASS 1: Walk frame hierarchy, populate boneWorldTransforms
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
            
            // "Frame" keyword
            if (tok.type == 1 && tok.name == "Frame") {
                pendingFrame = true;
                continue;
            }
            
            // Next NAME after "Frame" is the frame name
            if (pendingFrame && tok.type == 1) {
                pendingFrameName = tok.name;
                pendingFrame = false;
                continue;
            }
            
            // Open brace
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
            
            // Close brace
            if (tok.type == 11) {
                if (!braceKind.empty()) {
                    char kind = braceKind.back();
                    braceKind.pop_back();
                    
                    // Register bone transform on frame close
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
            
            // FrameTransformMatrix
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
        
        NSLog(@"[Santa] Bone world transforms: %lu", (unsigned long)boneWorldTransforms.size());
    }
    
    // ============================================================
    // PASS 2: Extract meshes, parse SkinWeights, apply skinning
    // ============================================================
    
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIdx;
    
    int meshCount = 0;
    int skinnedMeshCount = 0;
    int missingBoneCount = 0;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        
        if (tok.type == 1 && tok.name == "Mesh") {
            // ===== Parse Mesh template =====
            int depth = 0;
            bool entered = false;
            const std::vector<float>* meshVerts = nullptr;
            const std::vector<int>* meshFaces = nullptr;
            const std::vector<float>* meshUVs = nullptr;
            
            // Skin data collection
            MeshSkinData skinData;
            bool parsingSkinHeader = false;
            bool parsingSkinWeights = false;
            
            int meshEndIdx = (int)tokens.size();
            
            for (size_t j = i + 1; j < tokens.size(); j++) {
                if (tokens[j].type == 10) { depth++; entered = true; continue; }
                if (tokens[j].type == 11) {
                    depth--;
                    if (entered && depth == 0) { meshEndIdx = (int)j; break; }
                    continue;
                }
                
                // First FLOAT_LIST = vertices
                if (tokens[j].type == 7 && !meshVerts) {
                    meshVerts = &tokens[j].floatList;
                    continue;
                }
                // First INTEGER_LIST after vertices = face indices
                if (tokens[j].type == 6 && meshVerts && !meshFaces) {
                    meshFaces = &tokens[j].intList;
                    continue;
                }
                // MeshTextureCoords
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
                    continue;
                }
                
                // ===== XSkinMeshHeader =====
                if (tokens[j].type == 1 && tokens[j].name == "XSkinMeshHeader") {
                    parsingSkinHeader = true;
                    // Look for next 3 WORD/DWORD values
                    // Our parser stores wordValue (40), dwordValue (41), intValue (3)
                    int found = 0;
                    for (size_t k = j + 1; k < tokens.size() && k < j + 10; k++) {
                        int v = -1;
                        if (tokens[k].type == 40) v = tokens[k].wordValue;
                        else if (tokens[k].type == 41) v = tokens[k].dwordValue;
                        else if (tokens[k].type == 3) v = tokens[k].intValue;
                        
                        if (v >= 0) {
                            if (found == 0) skinData.maxSkinWeightsPerVertex = v;
                            else if (found == 1) skinData.maxSkinWeightsPerFace = v;
                            else if (found == 2) { skinData.nBones = v; break; }
                            found++;
                        }
                    }
                    parsingSkinHeader = false;
                    continue;
                }
                
                // ===== SkinWeights =====
                if (tokens[j].type == 1 && tokens[j].name == "SkinWeights") {
                    parsingSkinWeights = true;
                    
                    SkinWeightsData sw;
                    
                    // Walk inside SkinWeights block
                    int d3 = 0; bool e3 = false;
                    int state = 0; // 0=name, 1=count, 2=indices, 3=weights, 4=matrix
                    int count = 0;
                    int readIdx = 0;
                    
                    for (size_t k = j + 1; k < tokens.size(); k++) {
                        if (tokens[k].type == 10) { d3++; e3 = true; continue; }
                        if (tokens[k].type == 11) {
                            d3--;
                            if (e3 && d3 == 0) break;
                            continue;
                        }
                        
                        if (state == 0) {
                            // Bone name: STRING (type 2) or NAME (type 1)
                            if (tokens[k].type == 2 || tokens[k].type == 1) {
                                sw.boneName = tokens[k].name;
                                state = 1;
                            }
                        } else if (state == 1) {
                            // Count: DWORD (41) or INT (3) or ILIST (6)
                            if (tokens[k].type == 41) { count = tokens[k].dwordValue; state = 2; }
                            else if (tokens[k].type == 3) { count = tokens[k].intValue; state = 2; }
                            else if (tokens[k].type == 6) { count = (int)tokens[k].intList.size(); state = 3; }
                        } else if (state == 2) {
                            // Indices: ILIST (6)
                            if (tokens[k].type == 6) {
                                for (int iv : tokens[k].intList) sw.vertexIndices.push_back(iv);
                                state = 3;
                            }
                        } else if (state == 3) {
                            // Weights: FLIST (7)
                            if (tokens[k].type == 7) {
                                sw.weights = tokens[k].floatList;
                                state = 4;
                            }
                        } else if (state == 4) {
                            // Offset matrix: FLIST (7) with 16 floats
                            if (tokens[k].type == 7 && tokens[k].floatList.size() >= 16) {
                                sw.offsetMatrix = Mat4::fromFloats16(tokens[k].floatList);
                                state = 5;
                                break;
                            }
                        }
                    }
                    
                    if (state >= 4 && !sw.boneName.empty()) {
                        skinData.skins.push_back(sw);
                    }
                    parsingSkinWeights = false;
                    continue;
                }
            }
            
            // ===== Apply skinning to this mesh's vertices =====
            if (meshVerts && meshVerts->size() >= 3) {
                int vc = (int)(meshVerts->size() / 3);
                int baseVertex = (int)(allVerts.size() / 3);
                
                // Build local vertex array
                std::vector<Vec3> localVerts(vc);
                for (int v = 0; v < vc; v++) {
                    localVerts[v] = { (*meshVerts)[v*3], (*meshVerts)[v*3+1], (*meshVerts)[v*3+2] };
                }
                
                // Skinned output
                std::vector<Vec3> skinned(vc, {0,0,0});
                std::vector<float> weightSum(vc, 0.0f);
                
                if (!skinData.skins.empty()) {
                    // Apply skinning
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
                        }
                    }
                    
                    // Normalize
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
                    
                    skinnedMeshCount++;
                } else {
                    // No skin data - use raw vertices
                    skinned = localVerts;
                }
                
                // Add to global mesh
                for (int v = 0; v < vc; v++) {
                    allVerts.push_back(skinned[v].x);
                    allVerts.push_back(skinned[v].y);
                    allVerts.push_back(skinned[v].z);
                    
                    // Colors: skinned = red, non-skinned = grey
                    if (!skinData.skins.empty()) {
                        allColors.push_back(1.0f);
                        allColors.push_back(0.3f);
                        allColors.push_back(0.3f);
                    } else {
                        allColors.push_back(0.6f);
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
                NSLog(@"[Santa] Mesh %d: %d v, skins=%lu, bones=%d",
                      meshCount, vc, (unsigned long)skinData.skins.size(), skinData.nBones);
            }
            
            // Skip to end of this Mesh block
            i = meshEndIdx;
        }
    }
    
    NSLog(@"[Santa] === SUMMARY ===");
    NSLog(@"[Santa] Meshes: %d, Skinned: %d, Missing bones: %d",
          meshCount, skinnedMeshCount, missingBoneCount);
    NSLog(@"[Santa] Total verts: %d", (int)(allVerts.size() / 3));
    
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
                      @"%dM %dS %dMiss\n%d v, %d f",
                      meshCount, skinnedMeshCount, missingBoneCount,
                      mesh.vertexCount, mesh.faceCount];
    
    return mesh;
}

+ (NSString *)scanForSantaModel { return @"Disabled"; }
+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset {
    return [self extractSantaWithTransforms:offset];
}

@end
