#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include "AssetManager.h"

int main() {
    std::cout << "Santa iOS Engine Started!" << std::endl;

    AssetManager assetMgr;
    if (!assetMgr.loadXPK("assets/xmas.xpk")) {
        std::cout << "Failed to load XPK." << std::endl;
        return 1;
    }

    // TGA file load karein
    std::string tgaFile = "maps\\mouse.tga";
    std::vector<uint8_t> tgaData = assetMgr.getAssetData(tgaFile);

    if (tgaData.empty()) {
        std::cout << "Failed to load TGA file." << std::endl;
        return 1;
    }

    std::cout << "Loaded: " << tgaFile << " | Total Size: " << tgaData.size() << " bytes" << std::endl;

    // TGA Header parse karein (18 bytes)
    if (tgaData.size() < 18) {
        std::cout << "File TGA format mein nahi hai." << std::endl;
        return 1;
    }

    uint8_t idLength = tgaData[0];
    uint8_t colorMapType = tgaData[1];
    uint8_t imageType = tgaData[2];
    uint16_t width = tgaData[12] | (tgaData[13] << 8);
    uint16_t height = tgaData[14] | (tgaData[15] << 8);
    uint8_t bitsPerPixel = tgaData[16];
    uint8_t imageDescriptor = tgaData[17];

    std::cout << "--- TGA Header Info ---" << std::endl;
    std::cout << "Image Type: " << (int)imageType << " (2 = Uncompressed RGB, 10 = RLE Compressed)" << std::endl;
    std::cout << "Dimensions: " << width << " x " << height << " pixels" << std::endl;
    std::cout << "Bits Per Pixel: " << (int)bitsPerPixel << std::endl;
    std::cout << "Image Descriptor: " << (int)imageDescriptor << std::endl;
    std::cout << "ID Length: " << (int)idLength << " bytes" << std::endl;

    // Agar ID length hai, toh data uske baad shuru hota hai
    uint32_t pixelDataStart = 18 + idLength;
    std::cout << "Pixel Data starts at byte: " << pixelDataStart << std::endl;

    return 0;
}
