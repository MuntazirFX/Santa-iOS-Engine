#include <iostream>
#include <fstream>
#include <iomanip>
#include <vector>

void printHexDump(const std::vector<uint8_t>& data, size_t count) {
    for (size_t i = 0; i < data.size() && i < count; ++i) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)data[i] << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl;
    }
    std::cout << std::dec << std::endl;
}

int main() {
    std::cout << "Santa iOS Engine Started!" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // Pehli file (data\elements.txt) ka offset aur size
    uint32_t firstFileOffset = 3843;
    uint32_t firstFileSize = 3127;
    
    // Dusri file (effects\fire.txt) ka offset calculate karein
    uint32_t secondFileOffset = firstFileOffset + firstFileSize; // 6970

    std::cout << "Second file (effects\\fire.txt) offset: " << secondFileOffset << std::endl;

    file.seekg(secondFileOffset, std::ios::beg);
    std::vector<uint8_t> data(64);
    file.read(reinterpret_cast<char*>(data.data()), 64);

    std::cout << "Hex Dump (First 64 bytes): " << std::endl;
    printHexDump(data, 64);

    return 0;
}
