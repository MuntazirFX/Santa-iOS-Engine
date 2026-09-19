#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include "TextureLoader.h"
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

+ (NSData *)loadAssetNamed:(NSString *)name {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return nil;
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return nil;
    std::vector<uint8_t> d = am.getAssetData([name UTF8String]);
    if (d.empty()) return nil;
    return [NSData dataWithBytes:d.data() length:d.size()];
}

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

+ (NSString *)listTextureFiles {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return @"No XPK";
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return @"XPK load failed";
    std::vector<std::string> all = am.getAllFilenames();
    NSMutableString *out = [NSMutableString string];
    for (const auto& n : all) {
        if (n.find("maps\\") != std::string::npos || n.find("maps/") != std::string::npos) {
            [out appendFormat:@"%s\n", n.c_str()];
        }
    }
    return out;
}

+ (MeshData *)extractMeshFromAsset:(NSString *)assetName {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!p) return nil;
    
    AssetManager am;
    if (!am.loadXPK([p UTF8String])) return nil;
    
    std::string name = [assetName UTF8String];
    std::vector<uint8_t> fileData = am.getAssetData(name);
    if (fileData.empty()) return nil;
    
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(fileData.data(), fileData.size());
    if (decompressed.size() < 16) return nil;
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 500000);
    NSLog(@"[Santa] Tokens: %lu", (unsigned long)tokens.size());
    
    // PASS 1: Frame hierarchy (not used if skinning skipped, but kept for later)
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
            if (tok.type == 1 && tok.name == "Frame") { pendingFrame = true; continue; }
            if (pendingFrame && tok.type == 1) { pendingFrameName = tok.name; pendingFrame = false; continue; }
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
    
    NSLog(@"[Santa] Bones (from Frames): %lu", (unsigned long)boneWorldTransforms.size());
    
    // PASS 2: Extract Mesh (skinning skipped)
    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIdx;
    
    int meshCount = 0;
    int uvFoundCount = 0;
    int uvMissingCount = 0;
    int totalSkinBlocks = 0;
    std::string firstTextureFileName;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        const auto& tok = tokens[i];
        if (tok.type != 1 || tok.name != "Mesh") continue;
        
        int depth = 0;
        bool entered = false;
        int meshEndIdx = (int)tokens.size();
        const std::vector<float>* meshVerts = nullptr;
        const std::vector<int>* meshFaces = nullptr;
        const std::vector<float>* meshUVs = nullptr;
        std::string textureFileName;
        
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
            
            if (t.type == 1 && t.name == "TextureFilename" && textureFileName.empty()) {
                for (size_t k = j + 1; k < tokens.size() && k < j + 5; k++) {
                    if (tokens[k].type == 2 || tokens[k].type == 1 || tokens[k].type == 50) {
                        textureFileName = tokens[k].name;
                        break;
                    }
                }
                continue;
            }
            
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
            
            if (t.type == 1 && t.name == "SkinWeights") {
                totalSkinBlocks++;
                continue;
            }
        }
        
        if (meshVerts && meshVerts->size() >= 3) {
            int vc = (int)(meshVerts->size() / 3);
            int baseVertex = (int)(allVerts.size() / 3);
            
            // ✅ SKINNING SKIPPED: Vertices as-is (T-pose)
            for (int v = 0; v < vc; v++) {
                allVerts.push_back((*meshVerts)[v*3]);
                allVerts.push_back((*meshVerts)[v*3+1]);
                allVerts.push_back((*meshVerts)[v*3+2]);
                allColors.push_back(1.0f);
                allColors.push_back(1.0f);
                allColors.push_back(1.0f);
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
                uvFoundCount++;
            } else {
                uvMissingCount++;
                for (int u = 0; u < vc; u++) {
                    allUVs.push_back(0.5f);
                    allUVs.push_back(0.5f);
                }
            }
            
            if (firstTextureFileName.empty() && !textureFileName.empty()) {
                firstTextureFileName = textureFileName;
            }
            meshCount++;
        }
        i = meshEndIdx;
    }
    
    if (firstTextureFileName.empty() && [assetName containsString:@"weihnachtsman"]) {
        firstTextureFileName = "Nicolaus.bmp";
    }
    
    if (allVerts.empty() || allIdx.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVerts.size() / 3);
    mesh.faceCount = (int)(allIdx.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVerts.data() length:allVerts.size() * 4];
    mesh.indices = [NSMutableData dataWithBytes:allIdx.data() length:allIdx.size() * sizeof(uint32_t)];
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    mesh.colors = [NSMutableData dataWithBytes:allColors.data() length:allColors.size() * 4];
    mesh.offset = 0;
    
    NSString *textureInfo = @"no texture";
    if (!firstTextureFileName.empty()) {
        std::string xpkPath = TextureLoader::resolveTextureXPKPath(firstTextureFileName);
        mesh.textureName = [NSString stringWithUTF8String:xpkPath.c_str()];
        textureInfo = mesh.textureName;
    }
    
    NSString *uvStatus = [NSString stringWithFormat:@"UVs: %d OK, %d MISS", uvFoundCount, uvMissingCount];
    mesh.debugInfo = [NSString stringWithFormat:
                      @"%@\n%dM %dSK(skip) %dMiss\n%d v, %d f\n%@\ntex: %@",
                      assetName, meshCount, totalSkinBlocks, 0,
                      mesh.vertexCount, mesh.faceCount, uvStatus, textureInfo];
    return mesh;
}

+ (NSData *)loadTextureRGBA8Named:(NSString *)xpkPath width:(int *)outWidth height:(int *)outHeight {
    if (!xpkPath) return nil;
    NSData *fileData = [self loadAssetNamed:xpkPath];
    if (!fileData || fileData.length == 0) return nil;
    std::vector<uint8_t> raw((const uint8_t *)fileData.bytes, (const uint8_t *)fileData.bytes + fileData.length);
    std::vector<uint8_t> rgba;
    int w = 0, h = 0;
    if (!TextureLoader::decodeDDS(raw, rgba, w, h)) return nil;
    if (outWidth) *outWidth = w;
    if (outHeight) *outHeight = h;
    return [NSData dataWithBytes:rgba.data() length:rgba.size()];
}

+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath {
    NSData *data = [self loadAssetNamed:levelPath];
    if (!data) return @[];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger totalSize = data.length;
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
                i += nameData.length;
                break;
            }
        }
    }
    return objects;
}

@end
