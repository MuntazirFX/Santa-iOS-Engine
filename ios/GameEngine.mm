#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include "TextureLoader.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include <unordered_map>

// ... (Math Helpers, Vec3, Mat4, mulMat, transformPoint, SkinWeightsData same as before) ...

// ... (extractMeshFromAsset same as before, but with FIX 3) ...

// ✅ FIX 3: Skinned vertices ko White color do, Red nahi
if (anySkin) {
    allColors.push_back(1.0f);
    allColors.push_back(1.0f);
    allColors.push_back(1.0f);
} else {
    allColors.push_back(0.6f);
    allColors.push_back(0.6f);
    allColors.push_back(0.6f);
}

// ... (loadTextureRGBA8Named, parseLevelData same as before) ...
