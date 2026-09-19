#pragma once
#include <cstdint>
#include <vector>
#include <string>

// Minimal DDS (DirectDraw Surface) decoder.
//
// This game's texture files (assets/maps/*.dds inside xmas.xpk) are
// uncompressed 16-bit-per-pixel surfaces (confirmed via header inspection:
// no FOURCC, dwRGBBitCount=16, masks R=0xF800 G=0x07E0 B=0x001F — i.e.
// RGB565), with a full mipmap chain following the base level. This
// decoder reads the standard DDS header, verifies/derives the pixel
// format from its bit masks, and decodes ONLY the base (largest) mip
// level to a tightly-packed RGBA8 buffer, top-to-bottom row order
// (matching typical UV convention with V=0 at the top).
namespace TextureLoader {

// Decodes a DDS file's base mip level into an RGBA8 (4 bytes/pixel) buffer.
// Supports uncompressed RGB/RGBA pixel formats of 16, 24, or 32 bits per
// pixel, deriving channel positions from the DDS_PIXELFORMAT bit masks.
// Compressed (FOURCC / DXT) formats are not supported and will fail.
// Returns true and fills outRGBA8/outWidth/outHeight on success.
bool decodeDDS(const std::vector<uint8_t>& fileData,
                std::vector<uint8_t>& outRGBA8,
                int& outWidth,
                int& outHeight);

// Given a texture path as embedded in a DirectX .x file (e.g. an absolute
// Windows dev path like "D:\...\Weinachtsmann\Nicolaus.bmp"), resolves it
// to this archive's actual asset path, e.g. "maps\nicolaus.dds":
// strips the directory, drops the extension, lowercases, and rebuilds as
// "maps\\<name>.dds" — the convention this game's compiled asset pack uses.
std::string resolveTextureXPKPath(const std::string& rawPath);

} // namespace TextureLoader
