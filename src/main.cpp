#include <iostream>
#include <iomanip>
#include <vector>
#include "AssetManager.h"

void printHexDump(const std::vector<uint8_t>& data, size_t count) {
    for (size_t i = 0; i < data.size() && i < count; ++i) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)data[i] << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl;
    }
    std::cout << std::dec << std::endl;
}

int main() {
    std::cout << "Santa iOS Engine - Hex Dump Debug" << std::endl;

    AssetManager assetMgr;
    if (!assetMgr.loadXPK("assets/xmas.xpk")) {
        std::cout << "Failed to load XPK." << std::endl;
        return 1;
    }

    // Test 1: mouse.tga (jo zero de raha tha)
    std::string tgaFile = "maps\\mouse.tga";
    std::vector<uint8_t> tgaData = assetMgr.getAssetData(tgaFile);
    std::cout << "\n--- Testing: " << tgaFile << " ---" << std::endl;
    std::cout << "Size: " << tgaData.size() << " bytes" << std::endl;
    if (!tgaData.empty()) {
        std::cout << "Hex Dump (First 32 bytes):" << std::endl;
        printHexDump(tgaData, 32);
    } else {
        std::cout << "Data is empty!" << std::endl;
    }

    // Test 2: fire.txt (jo pehle sahi aya tha)
    std::string txtFile = "effects\\fire.txt";
    std::vector<uint8_t> txtData = assetMgr.getAssetData(txtFile);
    std::cout << "\n--- Testing: " << txtFile << " ---" << std::endl;
    std::cout << "Size: " << txtData.size() << " bytes" << std::endl;
    if (!txtData.empty()) {
        std::cout << "Hex Dump (First 32 bytes):" << std::endl;
        printHexDump(txtData, 32);
    } else {
        std::cout << "Data is empty!" << std::endl;
    }

    return 0;
}
