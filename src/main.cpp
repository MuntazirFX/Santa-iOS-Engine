#include <iostream>
#include <fstream>
#include <vector>
#include <string>

int main() {
    std::cout << "Santa iOS Engine Started!" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // Header se File Count parhein
    uint32_t fileCount = 0;
    file.read(reinterpret_cast<char*>(&fileCount), sizeof(fileCount));
    std::cout << "Total Files: " << fileCount << std::endl;

    // Saare offsets parhein
    std::vector<uint32_t> offsets(fileCount);
    file.read(reinterpret_cast<char*>(offsets.data()), fileCount * sizeof(uint32_t));

    // Header ka size calculate karein
    uint32_t headerSize = 4 + (fileCount * 4);
    std::cout << "Header Size: " << headerSize << " bytes" << std::endl;
    std::cout << "----------------------------------------" << std::endl;

    // Har file ka size aur naam print karein
    for (uint32_t i = 0; i < fileCount; ++i) {
        // AHEM FIX: Offset ko header size ke saath add karein
        file.seekg(headerSize + offsets[i], std::ios::beg);
        
        uint32_t fileSize = 0;
        file.read(reinterpret_cast<char*>(&fileSize), sizeof(fileSize));

        std::string filename;
        char ch;
        while (file.get(ch) && ch != '\0') {
            filename += ch;
        }

        std::cout << "File: " << filename << " | Size: " << fileSize << " bytes" << std::endl;
    }

    return 0;
}
