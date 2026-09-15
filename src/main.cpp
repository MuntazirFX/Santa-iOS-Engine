#include <iostream>
#include <iomanip>
#include <vector>
#include <cstdint>
#include "AssetManager.h"

int main() {
    std::cout << "Santa iOS Engine - TGA Parser Test (Via AssetManager)" << std::endl;

    AssetManager assetMgr;
    if (!assetMgr.loadXPK("assets/xmas.xpk")) {
        std::cout << "Failed to load XPK." << std::endl;
        return 1;
    }

    // Ab hum AssetManager se mouse.tga ka data mangwayenge
    std::string tgaFile = "maps\\mouse.tga";
    std::vector<uint8_t> tgaData = assetMgr.getAssetData(tgaFile);

    if (tgaData.empty()) {
        std::cout << "Failed to load TGA file from XPK." << std::endl;
        return 1;
    }

    std::cout << "Loaded: " << tgaFile << " | Size: " << tgaData.size() << " bytes" << std::endl;

    // TGA Header parse karein (18 bytes)
    if (tgaData.size() < 18) {
        std::cout << "File bohot choti hai, TGA format nahi hai." << std::endl;
        return 1;
    }

    uint8_t idLength = tgaData[0];
    uint8_t colorMapType = tgaData[1];
    uint8_t imageType = tgaData[2];
    uint16_t width = tgaData[12] | (tgaData[13] << 8);
    uint16_t height = tgaData[14] | (tgaData[15] << 8);
    uint8_t bitsPerPixel = tgaData[16];

    std::cout << "--- TGA Header Info ---" << std::endl;
    std::cout << "ID Length: " << (int)idLength << std::endl;
    std::cout << "Color Map Type: " << (int)colorMapType << std::endl;
    std::cout << "Image Type: " << (int)imageType << " (2=Uncompressed, 10=RLE Compressed)" << std::endl;
    std::cout << "Dimensions: " << width << " x " << height << " pixels" << std::endl;
    std::cout << "Bits Per Pixel: " << (int)bitsPerPixel << std::endl;

    return 0;
}
