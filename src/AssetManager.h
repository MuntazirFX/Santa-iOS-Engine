#pragma once
#include <string>
#include <vector>
#include <fstream>
#include <cstdint>

struct XPKEntry {
    std::string filename;
    uint32_t offset;
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
    std::vector<XPKEntry> fileTable;
};
