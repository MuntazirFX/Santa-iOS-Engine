#pragma once
#include <string>
#include <vector>
#include <fstream>
#include <cstdint>
#include <unordered_map>

struct XPKEntry {
    std::string filename;
    uint32_t offset; // XPK file mein asal absolute offset
    uint32_t size;
};

class AssetManager {
public:
    AssetManager() = default;
    ~AssetManager();

    bool loadXPK(const std::string& filepath);
    std::vector<uint8_t> getAssetData(const std::string& filename);
    std::vector<std::string> getAllFilenames();

private:
    std::ifstream xpkFile;
    std::unordered_map<std::string, XPKEntry> fileTable;
    std::vector<std::string> orderedFilenames;
};
