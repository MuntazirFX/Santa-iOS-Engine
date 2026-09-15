#pragma once
#include <string>
#include <vector>
#include <fstream>
#include <cstdint>
#include <unordered_map>

struct XPKEntry {
    std::string filename;
    uint32_t offset; // File data file mein kahan se shuru hota hai
    uint32_t size;
};

class AssetManager {
public:
    AssetManager() = default;
    ~AssetManager();

    bool loadXPK(const std::string& filepath);
    std::vector<uint8_t> getAssetData(const std::string& filename);

private:
    std::ifstream xpkFile;
    std::unordered_map<std::string, XPKEntry> fileTable;
};
