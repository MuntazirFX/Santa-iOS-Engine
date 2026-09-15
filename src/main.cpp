#include <iostream>
#include "AssetManager.h"

int main() {
    std::cout << "Santa iOS Engine Started!" << std::endl;

    AssetManager assetMgr;
    if (assetMgr.loadXPK("assets/xmas.xpk")) {
        // Ab hum XPK ke andar se koi file memory mein load karke test karte hain
        // Misaal ke taur par, "data\\elements.txt" (Dhyan rahe, Windows path use karna hai)
        std::string testFile = "data\\elements.txt";
        std::vector<uint8_t> data = assetMgr.getAssetData(testFile);

        if (!data.empty()) {
            std::cout << "Successfully loaded: " << testFile << " | Size in memory: " << data.size() << " bytes" << std::endl;
            
            // File ke pehle 50 characters print karein
            std::cout << "First 50 characters: ";
            for (size_t i = 0; i < data.size() && i < 50; ++i) {
                std::cout << (char)data[i];
            }
            std::cout << std::endl;
        } else {
            std::cout << "Failed to load asset from memory." << std::endl;
        }
    } else {
        std::cout << "Failed to load XPK." << std::endl;
    }

    return 0;
}
