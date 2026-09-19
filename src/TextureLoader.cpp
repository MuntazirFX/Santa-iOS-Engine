#include "TextureLoader.h"
#include <cstring>
#include <algorithm>
#include <cctype>

namespace TextureLoader {

namespace {

uint32_t readU32(const uint8_t* d) {
    return (uint32_t)d[0] | ((uint32_t)d[1] << 8) | ((uint32_t)d[2] << 16) | ((uint32_t)d[3] << 24);
}

// Counts trailing zero bits — used to find a mask's shift amount.
int shiftForMask(uint32_t mask) {
    if (mask == 0) return 0;
    int shift = 0;
    while ((mask & 1u) == 0u) { mask >>= 1; shift++; }
    return shift;
}

// Number of set bits in a mask — used to scale a channel up to 8 bits.
int bitsInMask(uint32_t mask) {
    int bits = 0;
    while (mask) { bits += (mask & 1u); mask >>= 1; }
    return bits;
}

uint8_t scaleToByte(uint32_t value, int bits) {
    if (bits <= 0) return 0;
    if (bits >= 8) return (uint8_t)(value >> (bits - 8));
    // Replicate bits to fill 8 bits (e.g. 5-bit 0..31 -> 0..255).
    uint32_t maxVal = (1u << bits) - 1u;
    return (uint8_t)((value * 255u) / maxVal);
}

} // namespace

bool decodeDDS(const std::vector<uint8_t>& fileData,
               std::vector<uint8_t>& outRGBA8,
               int& outWidth,
               int& outHeight) {
    if (fileData.size() < 128) return false;
    const uint8_t* d = fileData.data();

    if (!(d[0] == 'D' && d[1] == 'D' && d[2] == 'S' && d[3] == ' ')) return false;

    uint32_t height = readU32(d + 12);
    uint32_t width  = readU32(d + 16);
    if (width == 0 || height == 0 || width > 8192 || height > 8192) return false;

    uint32_t pfFlags   = readU32(d + 80);
    uint32_t fourCC    = readU32(d + 84);
    uint32_t rgbCount  = readU32(d + 88);
    uint32_t rMask     = readU32(d + 92);
    uint32_t gMask     = readU32(d + 96);
    uint32_t bMask     = readU32(d + 100);
    uint32_t aMask     = readU32(d + 104);

    const uint32_t DDPF_ALPHAPIXELS = 0x1;
    const uint32_t DDPF_FOURCC      = 0x4;
    const uint32_t DDPF_RGB         = 0x40;

    if (pfFlags & DDPF_FOURCC) {
        (void)fourCC;
        return false; // Compressed (DXT/BC) formats aren't needed for this archive's textures.
    }
    if (!(pfFlags & DDPF_RGB)) return false;
    if (rgbCount != 16 && rgbCount != 24 && rgbCount != 32) return false;

    bool hasAlpha = (pfFlags & DDPF_ALPHAPIXELS) && aMask != 0;
    int bytesPerPixel = (int)(rgbCount / 8);

    int rShift = shiftForMask(rMask), rBits = bitsInMask(rMask);
    int gShift = shiftForMask(gMask), gBits = bitsInMask(gMask);
    int bShift = shiftForMask(bMask), bBits = bitsInMask(bMask);
    int aShift = shiftForMask(aMask), aBits = bitsInMask(aMask);

    size_t pixelDataOffset = 128;
    size_t rowBytes = (size_t)width * bytesPerPixel;
    size_t neededBytes = rowBytes * height;
    if (pixelDataOffset + neededBytes > fileData.size()) return false;

    outWidth = (int)width;
    outHeight = (int)height;
    outRGBA8.assign((size_t)width * height * 4, 0);

    const uint8_t* src = d + pixelDataOffset;
    for (uint32_t y = 0; y < height; y++) {
        const uint8_t* row = src + (size_t)y * rowBytes;
        uint8_t* outRow = outRGBA8.data() + (size_t)y * width * 4;
        for (uint32_t x = 0; x < width; x++) {
            uint32_t pixel = 0;
            const uint8_t* px = row + (size_t)x * bytesPerPixel;
            for (int b = 0; b < bytesPerPixel; b++) pixel |= ((uint32_t)px[b]) << (8 * b);

            uint8_t r = scaleToByte((pixel & rMask) >> rShift, rBits);
            uint8_t g = scaleToByte((pixel & gMask) >> gShift, gBits);
            uint8_t b8 = scaleToByte((pixel & bMask) >> bShift, bBits);
            uint8_t a = hasAlpha ? scaleToByte((pixel & aMask) >> aShift, aBits) : 255;

            uint8_t* o = outRow + (size_t)x * 4;
            o[0] = r; o[1] = g; o[2] = b8; o[3] = a;
        }
    }
    return true;
}

std::string resolveTextureXPKPath(const std::string& rawPath) {
    // Strip directory (handle both \ and / separators).
    size_t slash = rawPath.find_last_of("\\/");
    std::string base = (slash == std::string::npos) ? rawPath : rawPath.substr(slash + 1);

    // Strip extension.
    size_t dot = base.find_last_of('.');
    if (dot != std::string::npos) base = base.substr(0, dot);

    // Lowercase.
    std::transform(base.begin(), base.end(), base.begin(),
                    [](unsigned char c) { return (char)std::tolower(c); });

    return "maps\\" + base + ".dds";
}

} // namespace TextureLoader
