#include <iostream>
#include <fstream>
#include <vector>
#include <iomanip>

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
    std::cout << "File Count: " << fileCount << std::endl;

    if (fileCount > 1000) { 
        std::cerr << "File count bohot zyada hai, format galat hai." << std::endl;
        return 1;
    }

    // Saare offsets parhein
    std::vector<uint32_t> offsets(fileCount);
    file.read(reinterpret_cast<char*>(offsets.data()), fileCount * sizeof(uint32_t));

    // Header ka size calculate karein
    uint32_t headerSize = 4 + (fileCount * 4);
    std::cout << "Calculated Header Size: " << headerSize << " bytes" << std::endl;

    // Pehli file ka data headerSize se shuru hota hai, uske pehle 16 bytes print karein
    file.seekg(headerSize, std::ios::beg);
    unsigned char dataHeader[16];
    file.read(reinterpret_cast<char*>(dataHeader), 16);

    std::cout << "Pehli file ke pehle 16 bytes: ";
    for (int i = 0; i < 16; i++) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)dataHeader[i] << " ";
    }
    std::cout << std::dec << std::endl;

    return 0;
}
