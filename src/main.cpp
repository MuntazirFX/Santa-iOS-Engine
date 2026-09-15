#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main() {
    std::cout << "Santa iOS Engine - TGA Finder" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // Poori file memory mein parhein
    file.seekg(0, std::ios::end);
    size_t fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<uint8_t> data(fileSize);
    file.read(reinterpret_cast<char*>(data.data()), fileSize);
    file.close();

    std::cout << "XPK File Size: " << fileSize << " bytes" << std::endl;

    // TGA header ka pattern (Uncompressed RGB, 24-bit ya 32-bit)
    std::vector<uint8_t> pattern = {0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    
    std::cout << "Searching for TGA header pattern..." << std::endl;
    int foundCount = 0;
    for (size_t i = 0; i < data.size() - pattern.size(); ++i) {
        bool match = true;
        for (size_t j = 0; j < pattern.size(); ++j) {
            if (data[i + j] != pattern[j]) {
                match = false;
                break;
            }
        }
        if (match) {
            std::cout << "Found TGA header at absolute offset: " << i << std::endl;
            foundCount++;
            if (foundCount >= 10) {
                std::cout << "Found 10 TGA headers, stopping search." << std::endl;
                break;
            }
        }
    }
    std::cout << "Search complete. Total found (first 10): " << foundCount << std::endl;
    return 0;
}
