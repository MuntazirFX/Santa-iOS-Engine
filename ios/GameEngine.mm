#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include <string>
#include <vector>
#include <algorithm>
#include <sstream>

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

// ============= Helper: lowercase =============
static std::string toLowerStr(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c){ return std::tolower(c); });
    return s;
}

// ============= Candidate scoring =============
struct SantaCandidate {
    size_t offset;
    size_t decompressedSize;
    int vertexCount;
    int frameCount;
    bool hasSkinWeights;
    bool hasSkinMeshHeader;
    bool hasAnimationSet;
    std::vector<std::string> textureNames;
    double score;
};

static bool containsHint(const std::string& lowerStr) {
    static const std::vector<std::string> hints = {
        "weihnacht", "santa", "nikolaus", "kopf", "koerper", "körper",
        "hand", "bein", "haar", "bart", "mantel", "gesicht", "body",
        "head", "beard", "coat", "man"
    };
    for (const auto& h : hints) {
        if (lowerStr.find(h) != std::string::npos) return true;
    }
    return false;
}

// ============= Santa Model Scanner =============
+ (NSString *)scanForSantaModel {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData) return @"No XPK data";
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    size_t totalSize = xpkData.length;
    
    // Step 1: Collect xof offsets
    std::vector<size_t> offsets;
    for (size_t i = 0; i + 4 < totalSize; i++) {
        if (bytes[i]=='x' && bytes[i+1]=='o' && bytes[i+2]=='f' && bytes[i+3]==' ') {
            offsets.push_back(i);
            i += 200;
        }
    }
    
    NSLog(@"[Scan] Total xof: %zu", offsets.size());
    
    // Step 2: Analyze each candidate
    std::vector<SantaCandidate> candidates;
    candidates.reserve(offsets.size());
    
    for (size_t off : offsets) {
        @autoreleasepool {
            std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + off, totalSize - off);
            if (decompressed.size() < 100) continue;
            
            std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 8000);
            
            SantaCandidate c;
            c.offset = off;
            c.decompressedSize = decompressed.size();
            c.vertexCount = 0;
            c.frameCount = 0;
            c.hasSkinWeights = false;
            c.hasSkinMeshHeader = false;
            c.hasAnimationSet = false;
            c.score = 0;
            
            for (size_t i = 0; i < tokens.size(); i++) {
                const auto& tok = tokens[i];
                if (tok.type != 1) continue;
                
                const std::string& name = tok.name;
                std::string lower = toLowerStr(name);
                
                if (name == "SkinWeights") c.hasSkinWeights = true;
                else if (name == "XSkinMeshHeader") c.hasSkinMeshHeader = true;
                else if (name == "AnimationSet") c.hasAnimationSet = true;
                else if (name == "Frame") c.frameCount++;
                else if (name == "Mesh") {
                    // Next INTEGER token is often vertex count
                    for (size_t j = i + 1; j < std::min(tokens.size(), i + 10); j++) {
                        if (tokens[j].type == 6 && !tokens[j].intList.empty()) {
                            // ILIST - material index list (small)
                            continue;
                        }
                        if (tokens[j].type == 7 && !tokens[j].floatList.empty()) {
                            // FLIST - vertices (each 3 floats)
                            int vc = (int)(tokens[j].floatList.size() / 3);
                            if (vc > c.vertexCount) c.vertexCount = vc;
                            break;
                        }
                    }
                }
                else if (name == "TextureFilename") {
                    // Filename in next STRING (type 2) token
                    for (size_t j = i + 1; j < std::min(tokens.size(), i + 5); j++) {
                        if (tokens[j].type == 2 && !tokens[j].name.empty()) {
                            c.textureNames.push_back(tokens[j].name);
                            break;
                        }
                    }
                }
                // Catch any string token with weihnacht/santa/nikolaus
                if (containsHint(lower)) {
                    if (std::find(c.textureNames.begin(), c.textureNames.end(), name) == c.textureNames.end()) {
                        c.textureNames.push_back(name);
                    }
                }
            }
            
            // ===== SCORING =====
            if (c.hasSkinWeights)     c.score += 100.0;
            if (c.hasSkinMeshHeader)  c.score += 60.0;
            if (c.hasAnimationSet)    c.score += 30.0;
            
            if (c.frameCount >= 10 && c.frameCount <= 60) c.score += 20.0;
            else c.score += std::min(c.frameCount, 5);
            
            for (const auto& t : c.textureNames) {
                if (containsHint(toLowerStr(t))) c.score += 40.0;
            }
            
            // Vertex count bonus (character range)
            if (c.vertexCount >= 200 && c.vertexCount <= 3000) c.score += 15.0;
            
            candidates.push_back(c);
        }
    }
    
    // Step 3: Sort by score
    std::sort(candidates.begin(), candidates.end(),
              [](const SantaCandidate& a, const SantaCandidate& b) {
                  return a.score > b.score;
              });
    
    // Step 4: Build report string
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Total xof: %zu  |  Scanned: %zu\n\n",
     offsets.size(), candidates.size()];
    
    size_t topN = std::min((size_t)20, candidates.size());
    for (size_t i = 0; i < topN; i++) {
        const auto& c = candidates[i];
        if (c.score < 5.0) break;
        
        [out appendFormat:@"#%zu  @%zu  score=%.0f\n", i + 1, c.offset, c.score];
        [out appendFormat:@"   v=%d  frames=%d  SKIN=%@ SKINHDR=%@ ANIM=%@\n",
         c.vertexCount, c.frameCount,
         c.hasSkinWeights ? @"Y" : @"-",
         c.hasSkinMeshHeader ? @"Y" : @"-",
         c.hasAnimationSet ? @"Y" : @"-"];
        
        if (!c.textureNames.empty()) {
            [out appendString:@"   tex: "];
            for (size_t k = 0; k < c.textureNames.size() && k < 3; k++) {
                std::string fn = c.textureNames[k];
                size_t slash = fn.find_last_of("\\/");
                if (slash != std::string::npos) fn = fn.substr(slash + 1);
                [out appendFormat:@"%s ", fn.c_str()];
            }
            [out appendString:@"\n"];
        }
        [out appendString:@"\n"];
    }
    
    return out;
}

// ============= Extract mesh at offset (unchanged) =============
+ (MeshData *)extractMeshAtOffset:(NSUInteger)offset {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData || offset >= xpkData.length) return nil;
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    if (decompressed.size() < 16) return nil;
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 3000);
    
    for (size_t i = 0; i < tokens.size(); i++) {
        if (tokens[i].type == 1 && tokens[i].name == "Mesh") {
            size_t j = i + 1;
            if (j < tokens.size() && tokens[j].type == 10) j++;
            if (j < tokens.size() && tokens[j].type == 6) j++;
            if (j >= tokens.size() || tokens[j].type != 7) continue;
            const auto& verts = tokens[j].floatList;
            if (verts.size() < 9) continue;
            
            MeshData *mesh = [[MeshData alloc] init];
            mesh.vertexCount = (int)(verts.size() / 3);
            mesh.vertices = [NSMutableData dataWithBytes:verts.data() length:verts.size() * 4];
            mesh.offset = offset;
            
            j++;
            if (j < tokens.size() && tokens[j].type == 6) {
                const auto& raw = tokens[j].intList;
                std::vector<uint32_t> tri;
                size_t p = 0;
                if (!raw.empty() && (raw[0] == 3 || raw[0] == 4)) {
                    while (p < raw.size()) {
                        uint32_t cnt = raw[p++];
                        if (cnt < 3 || cnt > 16 || p + cnt > raw.size()) break;
                        for (uint32_t k = 1; k + 1 < cnt; k++) {
                            tri.push_back((uint32_t)raw[p]);
                            tri.push_back((uint32_t)raw[p + k]);
                            tri.push_back((uint32_t)raw[p + k + 1]);
                        }
                        p += cnt;
                    }
                } else {
                    for (size_t k = 0; k + 2 < raw.size(); k += 3) {
                        tri.push_back((uint32_t)raw[k]);
                        tri.push_back((uint32_t)raw[k+1]);
                        tri.push_back((uint32_t)raw[k+2]);
                    }
                }
                size_t valid = 0;
                for (size_t k = 0; k < tri.size(); k++) {
                    if (tri[k] < (uint32_t)mesh.vertexCount) valid++;
                    else break;
                }
                valid = (valid / 3) * 3;
                tri.resize(valid);
                mesh.faceCount = (int)(tri.size() / 3);
                mesh.indices = [NSMutableData dataWithBytes:tri.data() length:tri.size() * sizeof(uint32_t)];
            }
            return mesh;
        }
    }
    return nil;
}

+ (MeshData *)extractAllMeshesAtOffset:(NSUInteger)offset {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData || offset >= xpkData.length) return nil;
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    if (decompressed.size() < 16) return nil;
    
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), 8000);
    
    // Collect all meshes
    std::vector<float> allVertices;
    std::vector<float> allUVs;
    std::vector<uint32_t> allIndices;
    std::string foundTexture = "";
    int meshCount = 0;
    
    for (size_t i = 0; i < tokens.size(); i++) {
        if (tokens[i].type == 1 && tokens[i].name == "Mesh") {
            size_t j = i + 1;
            if (j < tokens.size() && tokens[j].type == 10) j++;
            if (j < tokens.size() && tokens[j].type == 6) j++;
            
            if (j >= tokens.size() || tokens[j].type != 7) continue;
            const auto& verts = tokens[j].floatList;
            if (verts.size() < 9) continue;
            
            int baseVertex = (int)(allVertices.size() / 3);
            allVertices.insert(allVertices.end(), verts.begin(), verts.end());
            
            j++;
            
            if (j < tokens.size() && tokens[j].type == 6) {
                const auto& raw = tokens[j].intList;
                size_t p = 0;
                
                if (!raw.empty() && (raw[0] == 3 || raw[0] == 4)) {
                    while (p < raw.size()) {
                        uint32_t cnt = raw[p++];
                        if (cnt < 3 || cnt > 16 || p + cnt > raw.size()) break;
                        for (uint32_t k = 1; k + 1 < cnt; k++) {
                            allIndices.push_back((uint32_t)raw[p] + baseVertex);
                            allIndices.push_back((uint32_t)raw[p + k] + baseVertex);
                            allIndices.push_back((uint32_t)raw[p + k + 1] + baseVertex);
                        }
                        p += cnt;
                    }
                } else {
                    for (size_t k = 0; k + 2 < raw.size(); k += 3) {
                        allIndices.push_back((uint32_t)raw[k] + baseVertex);
                        allIndices.push_back((uint32_t)raw[k+1] + baseVertex);
                        allIndices.push_back((uint32_t)raw[k+2] + baseVertex);
                    }
                }
            }
            
            // UVs for this mesh
            const std::vector<float> *uvForThis = nullptr;
            for (size_t k = j; k < tokens.size() && k < j + 30; k++) {
                if (tokens[k].type == 1 && tokens[k].name == "MeshTextureCoords") {
                    size_t m = k + 1;
                    if (m < tokens.size() && tokens[m].type == 10) m++;
                    if (m < tokens.size() && tokens[m].type == 6) m++;
                    if (m < tokens.size() && tokens[m].type == 7) {
                        if (tokens[m].floatList.size() >= verts.size() / 3 * 2) {
                            uvForThis = &tokens[m].floatList;
                        }
                    }
                    break;
                }
                if (tokens[k].type == 1 && tokens[k].name == "Mesh") break;
            }
            
            if (uvForThis) {
                allUVs.insert(allUVs.end(), uvForThis->begin(), uvForThis->end());
            } else {
                // Pad with zeros
                for (size_t v = 0; v < verts.size() / 3; v++) {
                    allUVs.push_back(0.5f);
                    allUVs.push_back(0.5f);
                }
            }
            
            meshCount++;
            NSLog(@"[Santa] Mesh %d: %d v (total: %d v, %d idx)",
                  meshCount, (int)(verts.size()/3), (int)(allVertices.size()/3), (int)allIndices.size());
        }
        
        // Find any TextureFilename in whole file
        if (tokens[i].type == 1 && tokens[i].name == "TextureFilename" && foundTexture.empty()) {
            for (size_t k = i + 1; k < tokens.size() && k < i + 5; k++) {
                if (tokens[k].type == 2 && !tokens[k].name.empty()) {
                    foundTexture = tokens[k].name;
                    break;
                }
            }
        }
    }
    
    if (allVertices.empty()) return nil;
    
    MeshData *mesh = [[MeshData alloc] init];
    mesh.vertexCount = (int)(allVertices.size() / 3);
    mesh.vertices = [NSMutableData dataWithBytes:allVertices.data() length:allVertices.size() * 4];
    
    mesh.faceCount = (int)(allIndices.size() / 3);
    mesh.indices = [NSMutableData dataWithBytes:allIndices.data() length:allIndices.size() * sizeof(uint32_t)];
    
    mesh.uvs = [NSMutableData dataWithBytes:allUVs.data() length:allUVs.size() * 4];
    
    if (!foundTexture.empty()) {
        mesh.textureName = [NSString stringWithUTF8String:foundTexture.c_str()];
    }
    
    NSLog(@"[Santa] Total: %d meshes, %d v, %d f, tex=%@",
          meshCount, mesh.vertexCount, mesh.faceCount, mesh.textureName ?: @"(none)");
    
    return mesh;
}

@end
