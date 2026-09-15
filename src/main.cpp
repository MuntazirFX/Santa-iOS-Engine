#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <string>

int main() {
    std::cout << "Santa iOS Engine - Finding mouse.tga" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    uint32_t fileCount = 0;
    file.read(reinterpret_cast<char*>(&fileCount), sizeof(fileCount));

    std::vector<uint32_t> offsets(fileCount);
    file.read(reinterpret_cast<char*>(offsets.data()), fileCount * sizeof(uint32_t));

    uint32_t headerSize = 4 + (fileCount * 4);
    std::cout << "Total Files: " << fileCount << " | Header Size: " << headerSize << std::endl;

    // Saari 177 files ka metadata print karein
    for (uint32_t i = 0; i < fileCount; ++i) {
        file.seekg(headerSize + offsets[i], std::ios::beg);

        uint32_t fileSize = 0;
        file.read(reinterpret_cast<char*>(&fileSize), sizeof(fileSize));

        std::string filename;
        char ch;
        while (file.get(ch) && ch != '\0') {
            filename += ch;
        }

        // Sirf un files ko print karein jinke naam mein "mouse" hai
        if (filename.find("mouse") != std::string::npos) {
            std::cout << ">>> FOUND at index " << i << ": " << filename 
                      << " | Size: " << fileSize 
                      << " | Offset: " << offsets[i] << std::endl;
        }
    }

    return 0;
}
