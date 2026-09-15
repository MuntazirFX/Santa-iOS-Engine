#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <iomanip>

void printHexDump(const std::vector<uint8_t>& data, size_t count) {
    for (size_t i = 0; i < data.size() && i < count; ++i) {
        std::cout << std::hex << std::setw(2) << std::setfill('0') << (int)data[i] << " ";
        if ((i + 1) % 16 == 0) std::cout << std::endl;
    }
    std::cout << std::dec << std::endl;
}

int main() {
    std::cout << "Santa iOS Engine - TGA Pixel Data Check" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    uint32_t tgaOffset = 5642606;
    
    file.seekg(tgaOffset, std::ios::beg);
    unsigned char header[18];
    file.read(reinterpret_cast<char*>(header), 18);

    uint8_t idLength = header[0];
    uint16_t width = header[12] | (header[13] << 8);
    uint16_t height = header[14] | (header[15] << 8);
    uint8_t bitsPerPixel = header[16];

    std::cout << "TGA Info: " << width << "x" << height << " | BPP: " << (int)bitsPerPixel << std::endl;

    uint32_t pixelDataStart = tgaOffset + 18 + idLength;
    file.seekg(pixelDataStart, std::ios::beg);

    int bytesPerPixel = bitsPerPixel / 8;
    int imageSize = width * height * bytesPerPixel;
    
    // Sirf pehle 64 bytes parhein taake pata chale data kaisa hai
    std::vector<uint8_t> pixelSample(64);
    file.read(reinterpret_cast<char*>(pixelSample.data()), 64);
    file.close();

    std::cout << "Pixel Data (First 64 bytes):" << std::endl;
    printHexDump(pixelSample, 64);

    // Check karein ke kya saara data zero hai
    bool allZero = true;
    for (uint8_t b : pixelSample) {
        if (b != 0) { allZero = false; break; }
    }
    std::cout << "All zeros? " << (allZero ? "YES" : "NO") << std::endl;

    return 0;
}
