#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"

#include <Foundation/Foundation.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

// ============================================================
// Math
// ============================================================

struct Vec3 {
    float x, y, z;
};

struct Mat4 {
    float m[4][4];

    static Mat4 identity() {
        Mat4 r{};

        for (int i = 0; i < 4; ++i) {
            for (int j = 0; j < 4; ++j) {
                r.m[i][j] = (i == j) ? 1.0f : 0.0f;
            }
        }

        return r;
    }

    static Mat4 fromFloats16(const std::vector<float>& f) {
        Mat4 r = identity();

        if (f.size() < 16)
            return r;

        for (int i = 0; i < 16; ++i) {
            r.m[i / 4][i % 4] = f[i];
        }

        return r;
    }
};

static Mat4 mulMat(const Mat4& a, const Mat4& b) {
    Mat4 r{};

    for (int row = 0; row < 4; ++row) {
        for (int col = 0; col < 4; ++col) {
            float value = 0.0f;

            for (int k = 0; k < 4; ++k) {
                value += a.m[row][k] * b.m[k][col];
            }

            r.m[row][col] = value;
        }
    }

    return r;
}

// DirectX .X files convention used by the original data:
// position is treated as a row vector:
//
//     p' = p * M
//
static Vec3 transformPoint(const Vec3& v, const Mat4& M) {
    float x =
        v.x * M.m[0][0] +
        v.y * M.m[1][0] +
        v.z * M.m[2][0] +
        M.m[3][0];

    float y =
        v.x * M.m[0][1] +
        v.y * M.m[1][1] +
        v.z * M.m[2][1] +
        M.m[3][1];

    float z =
        v.x * M.m[0][2] +
        v.y * M.m[1][2] +
        v.z * M.m[2][2] +
        M.m[3][2];

    float w =
        v.x * M.m[0][3] +
        v.y * M.m[1][3] +
        v.z * M.m[2][3] +
        M.m[3][3];

    if (std::fabs(w) > 0.000001f &&
        std::fabs(w - 1.0f) > 0.000001f) {
        x /= w;
        y /= w;
        z /= w;
    }

    return { x, y, z };
}

static bool matrixLooksValid(const Mat4& m) {
    for (int r = 0; r < 4; ++r) {
        for (int c = 0; c < 4; ++c) {
            if (!std::isfinite(m.m[r][c]))
                return false;
        }
    }

    return true;
}

// ============================================================
// Skin data
// ============================================================

struct SkinWeightsData {
    std::string boneName;
    std::vector<int> vertexIndices;
    std::vector<float> weights;
    Mat4 offsetMatrix = Mat4::identity();
};

// ============================================================
// Internal mesh parser
// ============================================================

struct ParsedMesh {
    std::vector<float> vertices;
    std::vector<int> faces;
    std::vector<float> uvs;
    std::vector<SkinWeightsData> skins;
};

// ============================================================
// Frame hierarchy
// ============================================================

struct FrameNode {
    std::string name;
    Mat4 local = Mat4::identity();
    Mat4 world = Mat4::identity();

    int parent = -1;
    std::vector<int> children;
};

static std::string normalizeBoneName(const std::string& name) {
    std::string result = name;

    while (!result.empty() &&
           (result.front() == '"' || result.front() == ' ')) {
        result.erase(result.begin());
    }

    while (!result.empty() &&
           (result.back() == '"' || result.back() == ' ')) {
        result.pop_back();
    }

    return result;
}

// ============================================================
// Parse Frame hierarchy
//
// Important:
// The old implementation used a generic brace stack and could
// associate transforms with the wrong frame. This implementation
// explicitly builds Frame nodes and then calculates world matrices.
// ============================================================

static void buildFrameHierarchy(
    const std::vector<XToken>& tokens,
    std::vector<FrameNode>& frames,
    std::unordered_map<std::string, Mat4>& boneWorldTransforms
) {
    frames.clear();
    boneWorldTransforms.clear();

    struct StackEntry {
        int frameIndex;
    };

    std::vector<StackEntry> frameStack;

    bool waitingForFrameName = false;
    int pendingFrameIndex = -1;

    for (size_t i = 0; i < tokens.size(); ++i) {
        const XToken& t = tokens[i];

        // ----------------------------------------------------
        // Frame keyword
        // ----------------------------------------------------
        if (t.type == 1 && t.name == "Frame") {
            waitingForFrameName = true;
            pendingFrameIndex = -1;
            continue;
        }

        // ----------------------------------------------------
        // Frame name
        // ----------------------------------------------------
        if (waitingForFrameName && t.type == 1) {
            FrameNode node;
            node.name = normalizeBoneName(t.name);

            if (!frameStack.empty()) {
                node.parent = frameStack.back().frameIndex;
            }

            frames.push_back(node);

            int index = (int)frames.size() - 1;

            if (node.parent >= 0 &&
                node.parent < (int)frames.size()) {
                frames[node.parent].children.push_back(index);
            }

            pendingFrameIndex = index;
            waitingForFrameName = false;
            continue;
        }

        // ----------------------------------------------------
        // Opening brace
        // ----------------------------------------------------
        if (t.type == 10) {
            if (pendingFrameIndex >= 0) {
                frameStack.push_back({ pendingFrameIndex });
                pendingFrameIndex = -1;
            }

            continue;
        }

        // ----------------------------------------------------
        // FrameTransformMatrix
        // ----------------------------------------------------
        if (t.type == 1 &&
            t.name == "FrameTransformMatrix") {

            if (frameStack.empty())
                continue;

            int currentFrame =
                frameStack.back().frameIndex;

            for (size_t j = i + 1;
                 j < tokens.size() && j < i + 8;
                 ++j) {

                if (tokens[j].type == 7 &&
                    tokens[j].floatList.size() >= 16) {

                    frames[currentFrame].local =
                        Mat4::fromFloats16(tokens[j].floatList);

                    break;
                }
            }

            continue;
        }

        // ----------------------------------------------------
        // Closing brace
        // ----------------------------------------------------
        if (t.type == 11) {
            if (!frameStack.empty()) {
                frameStack.pop_back();
            }

            continue;
        }
    }

    // --------------------------------------------------------
    // Calculate world transforms recursively.
    // --------------------------------------------------------

    std::function<void(int, const Mat4&)> calculateWorld;

    calculateWorld =
        [&](int index, const Mat4& parentWorld) {

        if (index < 0 ||
            index >= (int)frames.size()) {
            return;
        }

        FrameNode& node = frames[index];

        node.world = mulMat(node.local, parentWorld);

        if (!node.name.empty()) {
            boneWorldTransforms[node.name] = node.world;
        }

        for (int child : node.children) {
            calculateWorld(child, node.world);
        }
    };

    Mat4 identity = Mat4::identity();

    for (int i = 0; i < (int)frames.size(); ++i) {
        if (frames[i].parent < 0) {
            calculateWorld(i, identity);
        }
    }
}

// ============================================================
// Find matching bone
// ============================================================

static const Mat4* findBoneTransform(
    const std::unordered_map<std::string, Mat4>& bones,
    const std::string& name
) {
    std::string clean = normalizeBoneName(name);

    auto it = bones.find(clean);

    if (it != bones.end()) {
        return &it->second;
    }

    // Case-insensitive fallback.
    for (const auto& pair : bones) {
        if (pair.first.size() != clean.size())
            continue;

        bool same = true;

        for (size_t i = 0; i < clean.size(); ++i) {
            char a = pair.first[i];
            char b = clean[i];

            if (a >= 'A' && a <= 'Z')
                a = (char)(a - 'A' + 'a');

            if (b >= 'A' && b <= 'Z')
                b = (char)(b - 'A' + 'a');

            if (a != b) {
                same = false;
                break;
            }
        }

        if (same)
            return &pair.second;
    }

    return nullptr;
}

// ============================================================
// Parse one Mesh block
// ============================================================

static ParsedMesh parseMeshBlock(
    const std::vector<XToken>& tokens,
    size_t meshTokenIndex
) {
    ParsedMesh result;

    int depth = 0;
    bool entered = false;
    size_t endIndex = tokens.size();

    const std::vector<float>* vertexList = nullptr;
    const std::vector<int>* faceList = nullptr;
    const std::vector<float>* uvList = nullptr;

    // --------------------------------------------------------
    // Find mesh closing brace first.
    // --------------------------------------------------------

    for (size_t j = meshTokenIndex + 1;
         j < tokens.size();
         ++j) {

        const XToken& t = tokens[j];

        if (t.type == 10) {
            ++depth;
            entered = true;
            continue;
        }

        if (t.type == 11) {
            --depth;

            if (entered && depth == 0) {
                endIndex = j;
                break;
            }

            continue;
        }
    }

    // --------------------------------------------------------
    // Parse content strictly inside Mesh.
    // --------------------------------------------------------

    for (size_t j = meshTokenIndex + 1;
         j < endIndex;
         ++j) {

        const XToken& t = tokens[j];

        // First FLIST = Mesh vertices.
        if (t.type == 7 &&
            vertexList == nullptr) {

            vertexList = &t.floatList;
            continue;
        }

        // First ILIST after vertices = faces.
        if (t.type == 6 &&
            vertexList != nullptr &&
            faceList == nullptr) {

            faceList = &t.intList;
            continue;
        }

        // ----------------------------------------------------
        // MeshTextureCoords
        // ----------------------------------------------------

        if (t.type == 1 &&
            t.name == "MeshTextureCoords") {

            int d = 0;
            bool started = false;

            for (size_t k = j + 1;
                 k < endIndex;
                 ++k) {

                const XToken& u = tokens[k];

                if (u.type == 10) {
                    ++d;
                    started = true;
                    continue;
                }

                if (u.type == 11) {
                    --d;

                    if (started && d == 0) {
                        j = k;
                        break;
                    }

                    continue;
                }

                if (u.type == 7) {
                    uvList = &u.floatList;
                    j = k;
                    break;
                }
            }

            continue;
        }

        // ----------------------------------------------------
        // SkinWeights
        // ----------------------------------------------------

        if (t.type == 1 &&
            t.name == "SkinWeights") {

            SkinWeightsData sw;

            int d = 0;
            bool started = false;

            int state = 0;

            for (size_t k = j + 1;
                 k < endIndex;
                 ++k) {

                const XToken& s = tokens[k];

                if (s.type == 10) {
                    ++d;
                    started = true;
                    continue;
                }

                if (s.type == 11) {
                    --d;

                    if (started && d == 0) {
                        j = k;
                        break;
                    }

                    continue;
                }

                // Bone name
                if (state == 0) {
                    if (s.type == 2) {
                        sw.boneName =
                            normalizeBoneName(s.name);
                        state = 1;
                    }

                    continue;
                }

                // Number of vertices
                if (state == 1) {
                    if (s.type == 41 ||
                        s.type == 3) {
                        state = 2;
                    }

                    continue;
                }

                // Vertex indices
                if (state == 2) {
                    if (s.type == 6) {
                        sw.vertexIndices =
                            s.intList;
                        state = 3;
                    }

                    continue;
                }

                // Weights
                if (state == 3) {
                    if (s.type == 7) {
                        sw.weights =
                            s.floatList;
                        state = 4;
                    }

                    continue;
                }

                // Offset matrix
                if (state == 4) {
                    if (s.type == 7 &&
                        s.floatList.size() >= 16) {

                        sw.offsetMatrix =
                            Mat4::fromFloats16(
                                s.floatList
                            );

                        state = 5;
                        j = k;
                        break;
                    }
                }
            }

            if (!sw.boneName.empty() &&
                !sw.vertexIndices.empty() &&
                !sw.weights.empty()) {

                result.skins.push_back(sw);
            }

            continue;
        }
    }

    if (vertexList != nullptr) {
        result.vertices = *vertexList;
    }

    if (faceList != nullptr) {
        result.faces = *faceList;
    }

    if (uvList != nullptr) {
        result.uvs = *uvList;
    }

    return result;
}

// ============================================================
// Build indices from X-file face list
// ============================================================

static void appendFaces(
    const std::vector<int>& raw,
    uint32_t baseVertex,
    std::vector<uint32_t>& output
) {
    if (raw.empty())
        return;

    size_t p = 0;

    while (p < raw.size()) {
        int count = raw[p++];

        if (count < 3 ||
            count > 64 ||
            p + (size_t)count > raw.size()) {
            break;
        }

        // Fan triangulation.
        for (int k = 1; k + 1 < count; ++k) {
            int a = raw[p];
            int b = raw[p + k];
            int c = raw[p + k + 1];

            if (a >= 0 &&
                b >= 0 &&
                c >= 0) {

                output.push_back(
                    (uint32_t)a + baseVertex
                );

                output.push_back(
                    (uint32_t)b + baseVertex
                );

                output.push_back(
                    (uint32_t)c + baseVertex
                );
            }
        }

        p += (size_t)count;
    }
}

// ============================================================
// ASSET LOADING
// ============================================================

@implementation MeshData
@end

@implementation LevelObject
@end

@implementation GameEngine

+ (NSData *)loadAssetNamed:(NSString *)name {

    NSString *path =
        [[NSBundle mainBundle]
        pathForResource:@"xmas"
        ofType:@"xpk"];

    if (!path)
        return nil;

    AssetManager am;

    if (!am.loadXPK([path UTF8String])) {
        return nil;
    }

    std::string requested =
        name ? [name UTF8String] : "";

    std::vector<uint8_t> data =
        am.getAssetData(requested);

    if (data.empty())
        return nil;

    return [NSData
            dataWithBytes:data.data()
            length:data.size()];
}

// ============================================================
// LEVEL FILE LIST
// ============================================================

+ (NSString *)listLevelFiles {

    NSString *path =
        [[NSBundle mainBundle]
        pathForResource:@"xmas"
        ofType:@"xpk"];

    if (!path)
        return @"No xmas.xpk";

    AssetManager am;

    if (!am.loadXPK([path UTF8String]))
        return @"XPK load failed";

    std::vector<std::string> files =
        am.getAllFilenames();

    NSMutableString *output =
        [NSMutableString string];

    for (const std::string& filename : files) {

        bool level =
            filename.find("levels\\") != std::string::npos ||
            filename.find("levels/") != std::string::npos;

        if (level) {
            [output appendFormat:@"%s\n",
             filename.c_str()];
        }
    }

    return output;
}

// ============================================================
// MAIN MESH EXTRACTION
// ============================================================

+ (MeshData *)extractMeshFromAsset:(NSString *)assetName {

    if (!assetName)
        return nil;

    NSString *path =
        [[NSBundle mainBundle]
        pathForResource:@"xmas"
        ofType:@"xpk"];

    if (!path) {
        NSLog(@"[Santa] xmas.xpk not found");
        return nil;
    }

    AssetManager am;

    if (!am.loadXPK([path UTF8String])) {
        NSLog(@"[Santa] XPK load failed");
        return nil;
    }

    std::string filename =
        [assetName UTF8String];

    std::vector<uint8_t> compressed =
        am.getAssetData(filename);

    if (compressed.empty()) {
        NSLog(@"[Santa] Asset not found: %@",
              assetName);
        return nil;
    }

    NSLog(@"[Santa] Asset: %@ (%lu bytes)",
          assetName,
          (unsigned long)compressed.size());

    // --------------------------------------------------------
    // Decompress
    // --------------------------------------------------------

    std::vector<uint8_t> data =
        XFileParser::decompressMSZip(
            compressed.data(),
            compressed.size()
        );

    if (data.empty()) {
        NSLog(@"[Santa] Decompression failed");
        return nil;
    }

    NSLog(@"[Santa] Decompressed: %lu bytes",
          (unsigned long)data.size());

    // --------------------------------------------------------
    // Parse tokens
    // --------------------------------------------------------

    std::vector<XToken> tokens =
        XFileParser::parseTokens(
            data.data(),
            data.size(),
            1000000
        );

    if (tokens.empty()) {
        NSLog(@"[Santa] No X-file tokens");
        return nil;
    }

    NSLog(@"[Santa] Tokens: %lu",
          (unsigned long)tokens.size());

    // --------------------------------------------------------
    // Frame hierarchy
    // --------------------------------------------------------

    std::vector<FrameNode> frames;

    std::unordered_map<std::string, Mat4>
        boneWorldTransforms;

    buildFrameHierarchy(
        tokens,
        frames,
        boneWorldTransforms
    );

    NSLog(@"[Santa] Frames: %lu | Bone transforms: %lu",
          (unsigned long)frames.size(),
          (unsigned long)boneWorldTransforms.size());

    // --------------------------------------------------------
    // Output buffers
    // --------------------------------------------------------

    std::vector<float> allVertices;
    std::vector<float> allUVs;
    std::vector<float> allColors;
    std::vector<uint32_t> allIndices;

    int meshCount = 0;
    int skinnedMeshCount = 0;
    int skinBlockCount = 0;
    int missingBones = 0;
    int totalVertices = 0;

    // --------------------------------------------------------
    // Find every Mesh
    // --------------------------------------------------------

    for (size_t i = 0;
         i < tokens.size();
         ++i) {

        const XToken& token = tokens[i];

        if (token.type != 1 ||
            token.name != "Mesh") {
            continue;
        }

        ParsedMesh mesh =
            parseMeshBlock(tokens, i);

        if (mesh.vertices.size() < 3)
            continue;

        int vertexCount =
            (int)(mesh.vertices.size() / 3);

        uint32_t baseVertex =
            (uint32_t)(allVertices.size() / 3);

        totalVertices += vertexCount;

        bool hasSkin =
            !mesh.skins.empty();

        if (hasSkin) {
            ++skinnedMeshCount;
        }

        skinBlockCount +=
            (int)mesh.skins.size();

        // ----------------------------------------------------
        // Local vertices
        // ----------------------------------------------------

        std::vector<Vec3> local(vertexCount);

        for (int v = 0;
             v < vertexCount;
             ++v) {

            local[v] = {
                mesh.vertices[v * 3 + 0],
                mesh.vertices[v * 3 + 1],
                mesh.vertices[v * 3 + 2]
            };
        }

        // ----------------------------------------------------
        // Skinning
        // ----------------------------------------------------

        std::vector<Vec3> finalVertices(
            vertexCount,
            { 0.0f, 0.0f, 0.0f }
        );

        std::vector<float> weightSum(
            vertexCount,
            0.0f
        );

        bool anyValidSkin = false;

        for (const SkinWeightsData& skin :
             mesh.skins) {

            const Mat4* boneWorld =
                findBoneTransform(
                    boneWorldTransforms,
                    skin.boneName
                );

            if (!boneWorld) {

                ++missingBones;

                NSLog(
                    @"[Santa] Missing bone: %s",
                    skin.boneName.c_str()
                );

                continue;
            }

            if (!matrixLooksValid(
                    skin.offsetMatrix) ||
                !matrixLooksValid(*boneWorld)) {
                continue;
            }

            // DirectX row-vector convention:
            //
            // vertex * offsetMatrix * boneWorld
            //
            Mat4 skinMatrix =
                mulMat(
                    skin.offsetMatrix,
                    *boneWorld
                );

            size_t count =
                std::min(
                    skin.vertexIndices.size(),
                    skin.weights.size()
                );

            for (size_t k = 0;
                 k < count;
                 ++k) {

                int vertexIndex =
                    skin.vertexIndices[k];

                float weight =
                    skin.weights[k];

                if (vertexIndex < 0 ||
                    vertexIndex >= vertexCount) {
                    continue;
                }

                if (!std::isfinite(weight) ||
                    weight <= 0.0f) {
                    continue;
                }

                Vec3 transformed =
                    transformPoint(
                        local[vertexIndex],
                        skinMatrix
                    );

                finalVertices[vertexIndex].x +=
                    transformed.x * weight;

                finalVertices[vertexIndex].y +=
                    transformed.y * weight;

                finalVertices[vertexIndex].z +=
                    transformed.z * weight;

                weightSum[vertexIndex] += weight;

                anyValidSkin = true;
            }
        }

        // ----------------------------------------------------
        // Vertices without weights stay local.
        // Weighted vertices are normalized.
        // ----------------------------------------------------

        for (int v = 0;
             v < vertexCount;
             ++v) {

            if (weightSum[v] <= 0.000001f) {

                finalVertices[v] =
                    local[v];

            } else {

                float inv =
                    1.0f / weightSum[v];

                finalVertices[v].x *= inv;
                finalVertices[v].y *= inv;
                finalVertices[v].z *= inv;
            }
        }

        // ----------------------------------------------------
        // Append vertices
        // ----------------------------------------------------

        for (int v = 0;
             v < vertexCount;
             ++v) {

            const Vec3& p =
                finalVertices[v];

            allVertices.push_back(p.x);
            allVertices.push_back(p.y);
            allVertices.push_back(p.z);

            // Keep debug colors for now.
            if (anyValidSkin) {

                allColors.push_back(1.0f);
                allColors.push_back(0.2f);
                allColors.push_back(0.2f);

            } else {

                allColors.push_back(0.65f);
                allColors.push_back(0.65f);
                allColors.push_back(0.65f);
            }
        }

        // ----------------------------------------------------
        // Faces
        // ----------------------------------------------------

        if (!mesh.faces.empty()) {

            appendFaces(
                mesh.faces,
                baseVertex,
                allIndices
            );
        }

        // ----------------------------------------------------
        // UVs
        // ----------------------------------------------------

        if (mesh.uvs.size() >=
            (size_t)vertexCount * 2) {

            for (int v = 0;
                 v < vertexCount;
                 ++v) {

                allUVs.push_back(
                    mesh.uvs[v * 2 + 0]
                );

                // Metal texture coordinates normally have
                // opposite vertical orientation.
                allUVs.push_back(
                    1.0f -
                    mesh.uvs[v * 2 + 1]
                );
            }

        } else {

            for (int v = 0;
                 v < vertexCount;
                 ++v) {

                allUVs.push_back(0.5f);
                allUVs.push_back(0.5f);
            }
        }

        ++meshCount;

        NSLog(
            @"[Santa] Mesh %d: vertices=%d faces=%lu skins=%lu",
            meshCount,
            vertexCount,
            (unsigned long)(mesh.faces.size()),
            (unsigned long)(mesh.skins.size())
        );
    }

    // --------------------------------------------------------
    // Final validation
    // --------------------------------------------------------

    NSLog(
        @"[Santa] RESULT meshes=%d skinned=%d skins=%d missingBones=%d vertices=%d triangles=%lu",
        meshCount,
        skinnedMeshCount,
        skinBlockCount,
        missingBones,
        totalVertices,
        (unsigned long)(allIndices.size() / 3)
    );

    if (allVertices.empty()) {
        NSLog(@"[Santa] No vertices extracted");
        return nil;
    }

    if (allIndices.empty()) {
        NSLog(@"[Santa] No triangles extracted");
        return nil;
    }

    // --------------------------------------------------------
    // Create Objective-C MeshData
    // --------------------------------------------------------

    MeshData *result =
        [[MeshData alloc] init];

    result.vertexCount =
        (int)(allVertices.size() / 3);

    result.faceCount =
        (int)(allIndices.size() / 3);

    result.vertices =
        [NSMutableData
         dataWithBytes:allVertices.data()
         length:allVertices.size() *
                sizeof(float)];

    result.indices =
        [NSMutableData
         dataWithBytes:allIndices.data()
         length:allIndices.size() *
                sizeof(uint32_t)];

    result.uvs =
        [NSMutableData
         dataWithBytes:allUVs.data()
         length:allUVs.size() *
                sizeof(float)];

    result.colors =
        [NSMutableData
         dataWithBytes:allColors.data()
         length:allColors.size() *
                sizeof(float)];

    result.offset = 0;

    result.textureName = nil;

    result.debugInfo =
        [NSString stringWithFormat:
         @"%@\n"
          "Frames: %lu\n"
          "Meshes: %d\n"
          "Skinned: %d\n"
          "Skin blocks: %d\n"
          "Missing bones: %d\n"
          "Vertices: %d\n"
          "Triangles: %d",
         assetName,
         (unsigned long)frames.size(),
         meshCount,
         skinnedMeshCount,
         skinBlockCount,
         missingBones,
         result.vertexCount,
         result.faceCount];

    return result;
}

// ============================================================
// LEVEL DATA
// ============================================================

+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath {

    NSData *data =
        [self loadAssetNamed:levelPath];

    if (!data)
        return @[];

    const uint8_t *bytes =
        (const uint8_t *)data.bytes;

    NSUInteger size =
        data.length;

    NSLog(
        @"[Level] %@: %lu bytes",
        levelPath,
        (unsigned long)size
    );

    NSArray<NSString *> *knownNames = @[
        @"EXTRA LIFE",
        @"JUMPER",
        @"PRESENT A",
        @"EXIT",
        @"TROLL",
        @"HAUS",
        @"TREE",
        @"KAMIN",
        @"PRESENT",
        @"TURM",
        @"HILL"
    ];

    NSMutableArray<LevelObject *> *objects =
        [NSMutableArray array];

    for (NSUInteger i = 0;
         i < size;
         ++i) {

        for (NSString *name in knownNames) {

            NSData *nameData =
                [name dataUsingEncoding:
                 NSASCIIStringEncoding];

            NSUInteger len =
                nameData.length;

            if (i + len > size)
                continue;

            if (memcmp(
                    bytes + i,
                    nameData.bytes,
                    len) == 0) {

                LevelObject *object =
                    [[LevelObject alloc] init];

                object.objectName = name;

                // Position extraction is intentionally not
                // guessed here. The supplied level parser
                // does not yet define the binary object layout.
                object.x = 0.0f;
                object.y = 0.0f;
                object.z = 0.0f;

                [objects addObject:object];

                NSLog(
                    @"[Level] Found %@ at %lu",
                    name,
                    (unsigned long)i
                );

                i += len - 1;
                break;
            }
        }
    }

    NSLog(
        @"[Level] Total objects: %lu",
        (unsigned long)objects.count
    );

    return objects;
}

@end
