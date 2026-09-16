#include "AssetManager.h"
#include <iostream>
#include <vector>
#include <string>

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
    std::vector<XPKEntry> orderedEntries;
    uint32_t totalMetadataSize = 0;
    
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
        entry.offset = 0;
        
        orderedEntries.push_back(entry);
        orderedFilenames.push_back(filename);
        
        totalMetadataSize = offsets[i] + 4 + filename.length() + 1;
    }
    
    uint32_t currentDataOffset = headerSize + totalMetadataSize;
    
    for (auto& entry : orderedEntries) {
        entry.offset = currentDataOffset;
        currentDataOffset += entry.size;
        fileTable[entry.filename] = entry;
    }
    
    std::cout << "XPK loaded: " << fileTable.size() << " files" << std::endl;
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
    return {};
}

std::vector<std::string> AssetManager::getAllFilenames() {
    return orderedFilenames;
}
