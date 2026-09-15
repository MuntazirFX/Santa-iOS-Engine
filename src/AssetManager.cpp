#include "AssetManager.h"
#include <iostream>
#include <algorithm>

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

    uint32_t fileCount = 0;
    xpkFile.read(reinterpret_cast<char*>(&fileCount), sizeof(fileCount));

    std::vector<uint32_t> offsets(fileCount);
    xpkFile.read(reinterpret_cast<char*>(offsets.data()), fileCount * sizeof(uint32_t));

    uint32_t headerSize = 4 + (fileCount * 4);
    uint32_t metadataEnd = headerSize;

    // Pehla pass: Saari metadata parhein aur data section ka aakhri hissa dhoondein
    for (uint32_t i = 0; i < fileCount; ++i) {
        xpkFile.seekg(headerSize + offsets[i], std::ios::beg);
        
        uint32_t fileSize = 0;
        xpkFile.read(reinterpret_cast<char*>(&fileSize), sizeof(fileSize));

        std::string filename;
        char ch;
        while (xpkFile.get(ch) && ch != '\0') {
            filename += ch;
        }

        XPKEntry entry;
        entry.filename = filename;
        entry.size = fileSize;
        entry.offset = 0; // Placeholder

        fileTable[filename] = entry;

        // Metadata ka end dhoondein
        uint32_t currentMetadataEnd = headerSize + offsets[i] + 4 + filename.length() + 1;
        metadataEnd = std::max(metadataEnd, currentMetadataEnd);
    }

    // Doosra pass: Data ka absolute offset calculate karein
    uint32_t currentDataOffset = metadataEnd;
    for (auto& pair : fileTable) {
        pair.second.offset = currentDataOffset;
        currentDataOffset += pair.second.size;
    }

    std::cout << "XPK loaded successfully! Total " << fileTable.size() << " files ready in memory." << std::endl;
    return true;
}

std::vector<uint8_t> AssetManager::getAssetData(const std::string& filename) {
    auto it = fileTable.find(filename);
    if (it != fileTable.end()) {
        std::vector<uint8_t> data(it->second.size);
        xpkFile.seekg(it->second.offset, std::ios::beg);
        xpkFile.read(reinterpret_cast<char*>(data.data()), it->second.size);
        return data;
    }
    std::cerr << "Asset not found: " << filename << std::endl;
    return {};
}
