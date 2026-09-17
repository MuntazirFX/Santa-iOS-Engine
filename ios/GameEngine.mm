#import "GameEngine.h"

#include "AssetManager.h"
#include "XFileParser.h"

#include <Foundation/Foundation.h>

#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <cstring>
#include <cctype>
#include <cstdio>


// ============================================================
// Math
// ============================================================

struct Vec3
{
    float x;
    float y;
    float z;
};


struct Mat4
{
    float m[4][4];

    static Mat4 identity()
    {
        Mat4 r{};

        for (int i = 0; i < 4; ++i)
        {
            for (int j = 0; j < 4; ++j)
            {
                r.m[i][j] = (i == j) ? 1.0f : 0.0f;
            }
        }

        return r;
    }

    static Mat4 fromFloats16(const std::vector<float>& f)
    {
        Mat4 r = Mat4::identity();

        if (f.size() < 16)
            return r;

        for (int i = 0; i < 16; ++i)
        {
            r.m[i / 4][i % 4] = f[i];
        }

        return r;
    }
};


static Mat4 mulMat(const Mat4& a, const Mat4& b)
{
    Mat4 r{};

    for (int i = 0; i < 4; ++i)
    {
        for (int j = 0; j < 4; ++j)
        {
            float s = 0.0f;

            for (int k = 0; k < 4; ++k)
            {
                s += a.m[i][k] * b.m[k][j];
            }

            r.m[i][j] = s;
        }
    }

    return r;
}


static Vec3 transformPoint(const Vec3& v, const Mat4& M)
{
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
        std::fabs(w - 1.0f) > 0.000001f)
    {
        x /= w;
        y /= w;
        z /= w;
    }

    return {x, y, z};
}


// ============================================================
// SkinWeights
// ============================================================

struct SkinWeightsData
{
    std::string boneName;

    std::vector<int> vertexIndices;
    std::vector<float> weights;

    Mat4 offsetMatrix;
};


// ============================================================
// Objective-C classes
// ============================================================

@implementation MeshData
@end

@implementation LevelObject
@end


@implementation GameEngine


// ============================================================
// Find XPK
//
// The build workflow places xmas.xpk directly inside the
// application bundle.
//
// We deliberately verify the file using Foundation and C
// fopen() before handing the path to the C++ AssetManager.
// ============================================================

+ (NSString *)xpkPath
{
    NSBundle *bundle = [NSBundle mainBundle];

    if (!bundle)
    {
        NSLog(@"[XPK] ERROR: mainBundle is nil");
        return nil;
    }

    NSString *resourcePath = [bundle resourcePath];

    NSLog(@"[XPK] Bundle resource path: %@",
          resourcePath);


    // --------------------------------------------------------
    // Primary lookup
    // --------------------------------------------------------

    NSString *path =
        [bundle pathForResource:@"xmas"
                         ofType:@"xpk"];

    if (path)
    {
        NSLog(@"[XPK] Foundation found: %@",
              path);
    }
    else
    {
        NSLog(@"[XPK] Foundation lookup failed");
    }


    // --------------------------------------------------------
    // Direct bundle path fallback
    // --------------------------------------------------------

    if (!path && resourcePath)
    {
        NSString *candidate =
            [resourcePath stringByAppendingPathComponent:@"xmas.xpk"];

        if ([[NSFileManager defaultManager]
             fileExistsAtPath:candidate])
        {
            path = candidate;

            NSLog(@"[XPK] Direct bundle path found: %@",
                  path);
        }
    }


    // --------------------------------------------------------
    // Recursive fallback
    // --------------------------------------------------------

    if (!path && resourcePath)
    {
        NSDirectoryEnumerator *enumerator =
            [[NSFileManager defaultManager]
             enumeratorAtPath:resourcePath];

        NSString *file = nil;

        while ((file = [enumerator nextObject]))
        {
            if ([[file.pathExtension lowercaseString]
                 isEqualToString:@"xpk"])
            {
                NSString *candidate =
                    [resourcePath
                     stringByAppendingPathComponent:file];

                path = candidate;

                NSLog(@"[XPK] Recursive match: %@",
                      path);

                break;
            }
        }
    }


    if (!path)
    {
        NSLog(@"[XPK] ERROR: xmas.xpk NOT FOUND");

        return nil;
    }


    // --------------------------------------------------------
    // Foundation verification
    // --------------------------------------------------------

    BOOL exists =
        [[NSFileManager defaultManager]
         fileExistsAtPath:path];

    NSLog(@"[XPK] fileExistsAtPath = %@",
          exists ? @"YES" : @"NO");

    if (!exists)
    {
        NSLog(@"[XPK] ERROR: path returned but file does not exist");

        return nil;
    }


    NSDictionary *attrs =
        [[NSFileManager defaultManager]
         attributesOfItemAtPath:path
         error:nil];

    NSNumber *size =
        attrs[NSFileSize];

    NSLog(@"[XPK] File size = %@ bytes",
          size);


    if (!size ||
        size.unsignedLongLongValue == 0)
    {
        NSLog(@"[XPK] ERROR: XPK is empty");

        return nil;
    }


    // --------------------------------------------------------
    // C fopen verification
    //
    // This is important because AssetManager ultimately uses
    // standard C++ file I/O.
    // --------------------------------------------------------

    const char *utf8Path =
        [path fileSystemRepresentation];

    if (!utf8Path)
    {
        NSLog(@"[XPK] ERROR: could not obtain filesystem path");

        return nil;
    }


    FILE *testFile =
        std::fopen(
            utf8Path,
            "rb"
        );

    if (!testFile)
    {
        NSLog(@"[XPK] ERROR: fopen() failed for:");
        NSLog(@"[XPK] %s", utf8Path);

        return nil;
    }


    std::fseek(
        testFile,
        0,
        SEEK_END
    );

    long long cSize =
        std::ftell(testFile);

    std::fclose(testFile);


    NSLog(@"[XPK] fopen() OK, size = %lld bytes",
          cSize);


    if (cSize <= 0)
    {
        NSLog(@"[XPK] ERROR: fopen reported empty file");

        return nil;
    }


    return path;
}


// ============================================================
// Load Asset
// ============================================================

+ (NSData *)loadAssetNamed:(NSString *)name
{
    NSString *path =
        [self xpkPath];

    if (!path)
    {
        NSLog(@"[XPK] Cannot load %@ because XPK was not found",
              name);

        return nil;
    }


    const char *filesystemPath =
        [path fileSystemRepresentation];

    NSLog(@"[XPK] Opening XPK with AssetManager:");
    NSLog(@"[XPK] %s",
          filesystemPath);


    AssetManager am;


    if (!am.loadXPK(
            std::string(filesystemPath)
        ))
    {
        NSLog(@"[XPK] AssetManager failed to open XPK");

        return nil;
    }


    std::vector<std::string> filenames =
        am.getAllFilenames();

    NSLog(@"[XPK] Files in archive: %lu",
          (unsigned long)filenames.size());


    std::string requested =
        [name UTF8String];


    std::vector<uint8_t> data =
        am.getAssetData(requested);


    // --------------------------------------------------------
    // Exact match
    // --------------------------------------------------------

    if (!data.empty())
    {
        NSLog(@"[XPK] Loaded '%@' (%lu bytes)",
              name,
              (unsigned long)data.size());

        return
            [NSData dataWithBytes:data.data()
                           length:data.size()];
    }


    // --------------------------------------------------------
    // Case-insensitive / slash-normalized match
    // --------------------------------------------------------

    std::string normalizedRequested =
        requested;

    std::replace(
        normalizedRequested.begin(),
        normalizedRequested.end(),
        '/',
        '\\'
    );


    for (const auto& filename : filenames)
    {
        std::string normalized =
            filename;

        std::replace(
            normalized.begin(),
            normalized.end(),
            '/',
            '\\'
        );


        std::string a =
            normalized;

        std::string b =
            normalizedRequested;


        std::transform(
            a.begin(),
            a.end(),
            a.begin(),
            [](unsigned char c)
            {
                return (char)std::tolower(c);
            }
        );


        std::transform(
            b.begin(),
            b.end(),
            b.begin(),
            [](unsigned char c)
            {
                return (char)std::tolower(c);
            }
        );


        if (a == b)
        {
            std::vector<uint8_t> matched =
                am.getAssetData(filename);

            if (!matched.empty())
            {
                NSLog(@"[XPK] Matched '%@' -> '%s' (%lu bytes)",
                      name,
                      filename.c_str(),
                      (unsigned long)matched.size());

                return
                    [NSData dataWithBytes:matched.data()
                                   length:matched.size()];
            }
        }
    }


    NSLog(@"[XPK] Asset NOT FOUND: %@",
          name);


    NSLog(@"[XPK] First archive files:");

    int printed = 0;

    for (const auto& filename : filenames)
    {
        NSLog(@"[XPK]   %s",
              filename.c_str());

        printed++;

        if (printed >= 30)
            break;
    }


    return nil;
}


// ============================================================
// List Levels
// ============================================================

+ (NSString *)listLevelFiles
{
    NSString *path =
        [self xpkPath];

    if (!path)
    {
        return @"XPK load failed: xmas.xpk not found";
    }


    const char *filesystemPath =
        [path fileSystemRepresentation];


    AssetManager am;


    if (!am.loadXPK(
            std::string(filesystemPath)
        ))
    {
        return @"XPK load failed: AssetManager could not open file";
    }


    std::vector<std::string> all =
        am.getAllFilenames();


    NSMutableString *out =
        [NSMutableString string];


    int count = 0;


    for (const auto& filename : all)
    {
        std::string lower =
            filename;


        std::transform(
            lower.begin(),
            lower.end(),
            lower.begin(),
            [](unsigned char c)
            {
                return (char)std::tolower(c);
            }
        );


        if (lower.find("levels\\") != std::string::npos ||
            lower.find("levels/") != std::string::npos)
        {
            [out appendFormat:@"%s\n",
             filename.c_str()];

            count++;
        }
    }


    if (count == 0)
    {
        [out appendString:@"No levels/*.dat files found"];
    }


    NSLog(@"[Level] Level files found: %d",
          count);


    return out;
}


// ============================================================
// Extract Mesh From Asset
// ============================================================

+ (MeshData *)extractMeshFromAsset:(NSString *)assetName
{
    NSLog(@"================================================");
    NSLog(@"[Santa] Loading asset: %@", assetName);
    NSLog(@"================================================");


    NSString *path =
        [self xpkPath];


    if (!path)
    {
        NSLog(@"[Santa] FAILED: XPK missing");
        return nil;
    }


    const char *filesystemPath =
        [path fileSystemRepresentation];


    AssetManager am;


    if (!am.loadXPK(
            std::string(filesystemPath)
        ))
    {
        NSLog(@"[Santa] FAILED: AssetManager could not load XPK");
        return nil;
    }


    std::string requested =
        [assetName UTF8String];


    std::vector<uint8_t> fileData =
        am.getAssetData(requested);


    // --------------------------------------------------------
    // Case-insensitive fallback
    // --------------------------------------------------------

    if (fileData.empty())
    {
        std::vector<std::string> filenames =
            am.getAllFilenames();


        std::string wanted =
            requested;


        std::replace(
            wanted.begin(),
            wanted.end(),
            '/',
            '\\'
        );


        std::transform(
            wanted.begin(),
            wanted.end(),
            wanted.begin(),
            [](unsigned char c)
            {
                return (char)std::tolower(c);
            }
        );


        for (const auto& filename : filenames)
        {
            std::string candidate =
                filename;


            std::replace(
                candidate.begin(),
                candidate.end(),
                '/',
                '\\'
            );


            std::transform(
                candidate.begin(),
                candidate.end(),
                candidate.begin(),
                [](unsigned char c)
                {
                    return (char)std::tolower(c);
                }
            );


            if (candidate == wanted)
            {
                fileData =
                    am.getAssetData(filename);


                NSLog(@"[Santa] Case-insensitive asset match: %s",
                      filename.c_str());

                break;
            }
        }
    }


    if (fileData.empty())
    {
        NSLog(@"[Santa] FAILED: asset not found: %@",
              assetName);

        return nil;
    }


    NSLog(@"[Santa] Compressed file: %lu bytes",
          (unsigned long)fileData.size());


    // ========================================================
    // Decompress
    // ========================================================

    std::vector<uint8_t> decompressed =
        XFileParser::decompressMSZip(
            fileData.data(),
            fileData.size()
        );


    if (decompressed.size() < 16)
    {
        NSLog(@"[Santa] FAILED: decompression returned %lu bytes",
              (unsigned long)decompressed.size());

        return nil;
    }


    NSLog(@"[Santa] Decompressed: %lu bytes",
          (unsigned long)decompressed.size());


    // ========================================================
    // Parse tokens
    // ========================================================

    std::vector<XToken> tokens =
        XFileParser::parseTokens(
            decompressed.data(),
            decompressed.size(),
            500000
        );


    NSLog(@"[Santa] Tokens: %lu",
          (unsigned long)tokens.size());


    if (tokens.empty())
    {
        NSLog(@"[Santa] FAILED: zero X-file tokens");
        return nil;
    }


    // ========================================================
    // PASS 1
    // Frame hierarchy
    // ========================================================

    std::unordered_map<std::string, Mat4>
        boneWorldTransforms;


    {
        std::vector<Mat4> worldStack;

        worldStack.push_back(
            Mat4::identity()
        );


        std::vector<char> braceKind;

        std::vector<std::string>
            frameNameStack;


        std::string pendingFrameName;

        bool pendingFrame = false;


        for (size_t i = 0;
             i < tokens.size();
             ++i)
        {
            const XToken& tok =
                tokens[i];


            if (tok.type == 1 &&
                tok.name == "Frame")
            {
                pendingFrame = true;
                continue;
            }


            if (pendingFrame &&
                tok.type == 1)
            {
                pendingFrameName =
                    tok.name;

                pendingFrame = false;

                continue;
            }


            if (tok.type == 10)
            {
                if (!pendingFrameName.empty())
                {
                    worldStack.push_back(
                        worldStack.back()
                    );

                    braceKind.push_back('F');

                    frameNameStack.push_back(
                        pendingFrameName
                    );

                    pendingFrameName.clear();
                }
                else
                {
                    braceKind.push_back('O');

                    frameNameStack.push_back("");
                }

                continue;
            }


            if (tok.type == 11)
            {
                if (!braceKind.empty())
                {
                    char kind =
                        braceKind.back();

                    braceKind.pop_back();


                    if (kind == 'F')
                    {
                        if (!frameNameStack.empty() &&
                            !frameNameStack.back().empty())
                        {
                            boneWorldTransforms[
                                frameNameStack.back()
                            ] =
                                worldStack.back();
                        }


                        if (worldStack.size() > 1)
                        {
                            worldStack.pop_back();
                        }
                    }


                    if (!frameNameStack.empty())
                    {
                        frameNameStack.pop_back();
                    }
                }

                continue;
            }


            if (tok.type == 1 &&
                tok.name == "FrameTransformMatrix")
            {
                for (size_t j = i + 1;
                     j < std::min(tokens.size(), i + 8);
                     ++j)
                {
                    if (tokens[j].type == 7 &&
                        tokens[j].floatList.size() >= 16)
                    {
                        Mat4 local =
                            Mat4::fromFloats16(
                                tokens[j].floatList
                            );


                        Mat4 parentWorld =
                            worldStack.back();


                        worldStack.back() =
                            mulMat(
                                local,
                                parentWorld
                            );


                        break;
                    }
                }

                continue;
            }
        }
    }


    NSLog(@"[Santa] Frames/Bones: %lu",
          (unsigned long)boneWorldTransforms.size());


    // ========================================================
    // PASS 2
    // Mesh extraction
    // ========================================================

    std::vector<float> allVerts;
    std::vector<float> allUVs;
    std::vector<float> allColors;

    std::vector<uint32_t> allIdx;


    int meshCount = 0;
    int totalSkinBlocks = 0;
    int missingBoneCount = 0;
    int totalVertices = 0;


    // --------------------------------------------------------
    // Every Mesh
    // --------------------------------------------------------

    for (size_t i = 0;
         i < tokens.size();
         ++i)
    {
        const XToken& tok =
            tokens[i];


        if (tok.type != 1 ||
            tok.name != "Mesh")
        {
            continue;
        }


        int depth = 0;

        bool entered = false;

        int meshEndIdx =
            (int)tokens.size();


        const std::vector<float>* meshVerts = nullptr;

        const std::vector<int>* meshFaces = nullptr;

        const std::vector<float>* meshUVs = nullptr;


        std::vector<SkinWeightsData> skins;


        // ====================================================
        // Parse Mesh
        // ====================================================

        for (size_t j = i + 1;
             j < tokens.size();
             ++j)
        {
            const XToken& t =
                tokens[j];


            if (t.type == 10)
            {
                depth++;
                entered = true;
                continue;
            }


            if (t.type == 11)
            {
                depth--;

                if (entered &&
                    depth == 0)
                {
                    meshEndIdx =
                        (int)j;

                    break;
                }

                continue;
            }


            if (t.type == 7 &&
                !meshVerts)
            {
                meshVerts =
                    &t.floatList;

                continue;
            }


            if (t.type == 6 &&
                meshVerts &&
                !meshFaces)
            {
                meshFaces =
                    &t.intList;

                continue;
            }


            // =================================================
            // UVs
            // =================================================

            if (t.type == 1 &&
                t.name == "MeshTextureCoords")
            {
                int d2 = 0;

                bool e2 = false;


                for (size_t k = j + 1;
                     k < tokens.size();
                     ++k)
                {
                    if (tokens[k].type == 10)
                    {
                        d2++;
                        e2 = true;
                        continue;
                    }


                    if (tokens[k].type == 11)
                    {
                        d2--;

                        if (e2 &&
                            d2 == 0)
                        {
                            j = k;
                            break;
                        }

                        continue;
                    }


                    if (tokens[k].type == 7)
                    {
                        meshUVs =
                            &tokens[k].floatList;

                        j = k;

                        break;
                    }
                }

                continue;
            }


            // =================================================
            // SkinWeights
            // =================================================

            if (t.type == 1 &&
                t.name == "SkinWeights")
            {
                SkinWeightsData sw;

                int d2 = 0;

                bool e2 = false;

                int state = 0;


                for (size_t k = j + 1;
                     k < tokens.size();
                     ++k)
                {
                    const XToken& tt =
                        tokens[k];


                    if (tt.type == 10)
                    {
                        d2++;
                        e2 = true;
                        continue;
                    }


                    if (tt.type == 11)
                    {
                        d2--;

                        if (e2 &&
                            d2 == 0)
                        {
                            j = k;
                            break;
                        }

                        continue;
                    }


                    if (state == 0)
                    {
                        if (tt.type == 2)
                        {
                            sw.boneName =
                                tt.name;

                            state = 1;
                        }
                    }
                    else if (state == 1)
                    {
                        if (tt.type == 41 ||
                            tt.type == 3)
                        {
                            state = 2;
                        }
                    }
                    else if (state == 2)
                    {
                        if (tt.type == 6)
                        {
                            sw.vertexIndices =
                                tt.intList;

                            state = 3;
                        }
                    }
                    else if (state == 3)
                    {
                        if (tt.type == 7)
                        {
                            sw.weights =
                                tt.floatList;

                            state = 4;
                        }
                    }
                    else if (state == 4)
                    {
                        if (tt.type == 7 &&
                            tt.floatList.size() >= 16)
                        {
                            sw.offsetMatrix =
                                Mat4::fromFloats16(
                                    tt.floatList
                                );

                            state = 5;

                            j = k;

                            break;
                        }
                    }
                }


                if (!sw.boneName.empty() &&
                    !sw.vertexIndices.empty() &&
                    !sw.weights.empty())
                {
                    skins.push_back(sw);

                    totalSkinBlocks++;
                }


                continue;
            }
        }


        // ====================================================
        // Vertices
        // ====================================================

        if (!meshVerts ||
            meshVerts->size() < 3)
        {
            i = meshEndIdx;
            continue;
        }


        int vc =
            (int)(meshVerts->size() / 3);


        int baseVertex =
            (int)(allVerts.size() / 3);


        totalVertices += vc;


        std::vector<Vec3> localVerts(vc);


        for (int v = 0;
             v < vc;
             ++v)
        {
            localVerts[v] =
            {
                (*meshVerts)[v * 3 + 0],
                (*meshVerts)[v * 3 + 1],
                (*meshVerts)[v * 3 + 2]
            };
        }


        // ====================================================
        // Skin
        // ====================================================

        std::vector<Vec3> skinned(
            vc,
            {0, 0, 0}
        );


        std::vector<float> weightSum(
            vc,
            0.0f
        );


        bool anySkin = false;


        for (const auto& skin : skins)
        {
            auto it =
                boneWorldTransforms.find(
                    skin.boneName
                );


            if (it ==
                boneWorldTransforms.end())
            {
                missingBoneCount++;

                NSLog(@"[Santa] Missing bone: %s",
                      skin.boneName.c_str());

                continue;
            }


            Mat4 boneMatrix =
                mulMat(
                    skin.offsetMatrix,
                    it->second
                );


            size_t count =
                std::min(
                    skin.vertexIndices.size(),
                    skin.weights.size()
                );


            for (size_t k = 0;
                 k < count;
                 ++k)
            {
                int vi =
                    skin.vertexIndices[k];


                float w =
                    skin.weights[k];


                if (vi < 0 ||
                    vi >= vc ||
                    w <= 0.0f)
                {
                    continue;
                }


                Vec3 transformed =
                    transformPoint(
                        localVerts[vi],
                        boneMatrix
                    );


                skinned[vi].x +=
                    w * transformed.x;

                skinned[vi].y +=
                    w * transformed.y;

                skinned[vi].z +=
                    w * transformed.z;


                weightSum[vi] += w;

                anySkin = true;
            }
        }


        // ====================================================
        // Normalize
        // ====================================================

        for (int v = 0;
             v < vc;
             ++v)
        {
            if (weightSum[v] < 0.000001f)
            {
                skinned[v] =
                    localVerts[v];
            }
            else
            {
                float inv =
                    1.0f /
                    weightSum[v];


                skinned[v].x *= inv;
                skinned[v].y *= inv;
                skinned[v].z *= inv;
            }
        }


        // ====================================================
        // Store vertices
        // ====================================================

        for (int v = 0;
             v < vc;
             ++v)
        {
            allVerts.push_back(
                skinned[v].x
            );

            allVerts.push_back(
                skinned[v].y
            );

            allVerts.push_back(
                skinned[v].z
            );


            if (anySkin)
            {
                allColors.push_back(1.0f);
                allColors.push_back(0.2f);
                allColors.push_back(0.2f);
            }
            else
            {
                allColors.push_back(0.6f);
                allColors.push_back(0.6f);
                allColors.push_back(0.6f);
            }
        }


        // ====================================================
        // Faces
        // ====================================================

        if (meshFaces)
        {
            const auto& raw =
                *meshFaces;


            size_t p = 0;


            if (!raw.empty() &&
                (raw[0] == 3 ||
                 raw[0] == 4))
            {
                while (p < raw.size())
                {
                    uint32_t cnt =
                        raw[p++];


                    if (cnt < 3 ||
                        cnt > 16 ||
                        p + cnt > raw.size())
                    {
                        break;
                    }


                    for (uint32_t k = 1;
                         k + 1 < cnt;
                         ++k)
                    {
                        allIdx.push_back(
                            (uint32_t)raw[p]
                            + baseVertex
                        );


                        allIdx.push_back(
                            (uint32_t)raw[p + k]
                            + baseVertex
                        );


                        allIdx.push_back(
                            (uint32_t)raw[p + k + 1]
                            + baseVertex
                        );
                    }


                    p += cnt;
                }
            }
            else
            {
                for (size_t k = 0;
                     k + 2 < raw.size();
                     k += 3)
                {
                    allIdx.push_back(
                        (uint32_t)raw[k]
                        + baseVertex
                    );

                    allIdx.push_back(
                        (uint32_t)raw[k + 1]
                        + baseVertex
                    );

                    allIdx.push_back(
                        (uint32_t)raw[k + 2]
                        + baseVertex
                    );
                }
            }
        }


        // ====================================================
        // UV
        // ====================================================

        if (meshUVs &&
            meshUVs->size() >=
                (size_t)vc * 2)
        {
            allUVs.insert(
                allUVs.end(),
                meshUVs->begin(),
                meshUVs->begin() +
                    vc * 2
            );
        }
        else
        {
            for (int v = 0;
                 v < vc;
                 ++v)
            {
                allUVs.push_back(0.5f);
                allUVs.push_back(0.5f);
            }
        }


        meshCount++;


        NSLog(@"[Santa] Mesh %d: vertices=%d skins=%lu",
              meshCount,
              vc,
              (unsigned long)skins.size());


        i = meshEndIdx;
    }


    // ========================================================
    // Summary
    // ========================================================

    NSLog(@"================================================");
    NSLog(@"[Santa] MESH SUMMARY");
    NSLog(@"Meshes: %d", meshCount);
    NSLog(@"SkinBlocks: %d", totalSkinBlocks);
    NSLog(@"MissingBones: %d", missingBoneCount);
    NSLog(@"Vertices: %d", totalVertices);
    NSLog(@"Indices: %lu",
          (unsigned long)allIdx.size());
    NSLog(@"================================================");


    if (allVerts.empty() ||
        allIdx.empty())
    {
        NSLog(@"[Santa] FAILED: no renderable mesh");

        return nil;
    }


    // ========================================================
    // MeshData
    // ========================================================

    MeshData *mesh =
        [[MeshData alloc] init];


    mesh.vertexCount =
        (int)(allVerts.size() / 3);


    mesh.faceCount =
        (int)(allIdx.size() / 3);


    mesh.vertices =
        [NSMutableData
         dataWithBytes:allVerts.data()
         length:allVerts.size() *
                sizeof(float)];


    mesh.indices =
        [NSMutableData
         dataWithBytes:allIdx.data()
         length:allIdx.size() *
                sizeof(uint32_t)];


    mesh.uvs =
        [NSMutableData
         dataWithBytes:allUVs.data()
         length:allUVs.size() *
                sizeof(float)];


    mesh.colors =
        [NSMutableData
         dataWithBytes:allColors.data()
         length:allColors.size() *
                sizeof(float)];


    mesh.offset = 0;

    mesh.textureName = nil;


    mesh.debugInfo =
        [NSString stringWithFormat:
            @"%@\n"
             "Meshes: %d\n"
             "SkinBlocks: %d\n"
             "MissingBones: %d\n"
             "Vertices: %d\n"
             "Faces: %d",
             assetName,
             meshCount,
             totalSkinBlocks,
             missingBoneCount,
             mesh.vertexCount,
             mesh.faceCount];


    return mesh;
}


// ============================================================
// Level Data
// ============================================================

+ (NSArray<LevelObject *> *)parseLevelData:(NSString *)levelPath
{
    NSData *data =
        [self loadAssetNamed:levelPath];


    if (!data)
    {
        NSLog(@"[Level] Could not load: %@",
              levelPath);

        return @[];
    }


    const uint8_t *bytes =
        (const uint8_t *)data.bytes;


    NSUInteger totalSize =
        data.length;


    NSLog(@"[Level] %@: %lu bytes",
          levelPath,
          (unsigned long)totalSize);


    NSArray *knownNames =
    @[
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
         i + 8 < totalSize;
         ++i)
    {
        for (NSString *name in knownNames)
        {
            NSData *nameData =
                [name dataUsingEncoding:
                    NSASCIIStringEncoding];


            if (i + nameData.length >
                totalSize)
            {
                continue;
            }


            if (memcmp(
                    bytes + i,
                    nameData.bytes,
                    nameData.length
                ) == 0)
            {
                LevelObject *obj =
                    [[LevelObject alloc] init];


                obj.objectName =
                    name;


                obj.x = 0.0f;
                obj.y = 0.0f;
                obj.z = 0.0f;


                [objects addObject:obj];


                NSLog(@"[Level] Found '%@' at offset %lu",
                      name,
                      (unsigned long)i);


                i += nameData.length;

                break;
            }
        }
    }


    NSLog(@"[Level] Total objects: %lu",
          (unsigned long)objects.count);


    return objects;
}


@end
