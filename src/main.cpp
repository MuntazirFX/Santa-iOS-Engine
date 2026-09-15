#include <iostream>
#include "AssetManager.h"

int main() {
    std::cout << "Santa iOS Engine Started!" << std::endl;

    AssetManager assetMgr;
    // Hum assets folder se xmas.xpk load karne ki koshish karenge
    if (assetMgr.loadXPK("assets/xmas.xpk")) {
        std::cout << "XPK loaded successfully!" << std::endl;
    } else {
        std::cout << "Failed to load XPK. (Is the file in assets folder?)" << std::endl;
    }

    return 0;
}
