#include "AssetManager.h"
#include <iostream>

AssetManager::~AssetManager() {
    if (xpkFile.is_open()) {
        xpkFile.close();
    }
}

bool AssetManager::loadXPK(const std::string& filepath) {
    xpkFile.open(filepath, std::ios::binary);
    if (!xpkFile.is_open()) {
        std::cerr << "Failed to open XPK file: " << filepath << std::endl;
        return false;
    }

    // NOTE: Yeh ek basic structure hai. Agar XPK format mukhtalif hai, 
    // toh in lines ko hex editor ke mutabiq adjust karna hoga.
    char magic[4];
    xpkFile.read(magic, 4);

    uint32_t fileCount = 0;
    xpkFile.read(reinterpret_cast<char*>(&fileCount), sizeof(fileCount));

    std::cout << "XPK Magic: " << magic << " | File Count: " << fileCount << std::endl;

    for (uint32_t i = 0; i < fileCount; ++i) {
        XPKEntry entry;
        char ch;
        // Read filename (assuming null-terminated string)
        while (xpkFile.get(ch) && ch != '\0') {
            entry.filename += ch;
        }

        xpkFile.read(reinterpret_cast<char*>(&entry.offset), sizeof(entry.offset));
        xpkFile.read(reinterpret_cast<char*>(&entry.size), sizeof(entry.size));

        fileTable.push_back(entry);
        std::cout << "Found: " << entry.filename << " | Offset: " << entry.offset << " | Size: " << entry.size << std::endl;
    }

    return true;
}

std::vector<uint8_t> AssetManager::getAssetData(const std::string& filename) {
    for (const auto& entry : fileTable) {
        if (entry.filename == filename) {
            std::vector<uint8_t> data(entry.size);
            xpkFile.seekg(entry.offset, std::ios::beg);
            xpkFile.read(reinterpret_cast<char*>(data.data()), entry.size);
            return data;
        }
    }
    std::cerr << "Asset not found: " << filename << std::endl;
    return {};
}
