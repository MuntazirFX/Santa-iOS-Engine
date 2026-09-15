#include <iostream>
#include <iomanip>
#include "AssetManager.h"

// Data ko hex format mein print karne ke liye helper function
void printHexDump(const std::vector<uint8_t>& data, size_t count) {
    for (size_t i = 0; i < data.size() && i < count; ++i) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)data[i] << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl;
    }
    std::cout << std::dec << std::endl;
}

int main() {
    std::cout << "Santa iOS Engine Started!" << std::endl;

    AssetManager assetMgr;
    if (assetMgr.loadXPK("assets/xmas.xpk")) {
        
        // Test 1: elements.txt
        std::string testFile1 = "data\\elements.txt";
        std::vector<uint8_t> data1 = assetMgr.getAssetData(testFile1);
        if (!data1.empty()) {
            std::cout << "Loaded: " << testFile1 << " | Size: " << data1.size() << " bytes" << std::endl;
            std::cout << "Hex Dump (First 32 bytes): " << std::endl;
            printHexDump(data1, 32);
        }

        // Test 2: Ek texture file (TGA image)
        std::string testFile2 = "maps\\mouse.tga";
        std::vector<uint8_t> data2 = assetMgr.getAssetData(testFile2);
        if (!data2.empty()) {
            std::cout << "Loaded: " << testFile2 << " | Size: " << data2.size() << " bytes" << std::endl;
            std::cout << "Hex Dump (First 32 bytes): " << std::endl;
            printHexDump(data2, 32);
        }
    } else {
        std::cout << "Failed to load XPK." << std::endl;
    }

    return 0;
}
