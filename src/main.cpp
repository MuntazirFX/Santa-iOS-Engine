#include <iostream>
#include <iomanip>
#include "AssetManager.h"

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
        std::string testFile = "data\\elements.txt";
        std::vector<uint8_t> data = assetMgr.getAssetData(testFile);

        if (!data.empty()) {
            std::cout << "Loaded: " << testFile << " | Size: " << data.size() << " bytes" << std::endl;
            std::cout << "Hex Dump (First 32 bytes): " << std::endl;
            printHexDump(data, 32);
        } else {
            std::cout << "Failed to load asset." << std::endl;
        }
    } else {
        std::cout << "Failed to load XPK." << std::endl;
    }

    return 0;
}
