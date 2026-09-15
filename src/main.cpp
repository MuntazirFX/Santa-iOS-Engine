#include <iostream>
#include <fstream>
#include <iomanip>

int main() {
    std::cout << "Santa iOS Engine Started!" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // File ke shuru ke 64 bytes parhein
    unsigned char header[64];
    file.read(reinterpret_cast<char*>(header), 64);

    std::cout << "--- xmas.xpk ke pehle 64 bytes (Hex format) ---" << std::endl;
    for (int i = 0; i < 64; i++) {
        // Hex format mein print karein
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)header[i] << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl; // 16 bytes ke baad nayi line
    }
    std::cout << std::dec << std::endl; // Decimal par wapas
    std::cout << "--- Dump Complete ---" << std::endl;

    return 0;
}
