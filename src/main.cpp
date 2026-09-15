#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

bool isPowerOfTwo(int n) {
    return n > 0 && (n & (n - 1)) == 0;
}

int main() {
    std::cout << "Santa iOS Engine - Strict TGA Search" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    file.seekg(0, std::ios::end);
    size_t fileSize = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> data(fileSize);
    file.read(reinterpret_cast<char*>(data.data()), fileSize);
    file.close();

    std::cout << "XPK File Size: " << fileSize << " bytes" << std::endl;

    // Data section 3843 bytes par shuru hota hai
    uint32_t dataStart = 3843;
    int foundCount = 0;

    for (size_t i = dataStart; i < data.size() - 18; ++i) {
        uint8_t idLength = data[i];
        uint8_t colorMapType = data[i+1];
        uint8_t imageType = data[i+2];
        
        // Strict validation
        if (colorMapType != 0) continue;
        if (imageType != 2 && imageType != 10) continue;
        if (idLength > 32) continue;
        
        uint16_t width = data[i+12] | (data[i+13] << 8);
        uint16_t height = data[i+14] | (data[i+15] << 8);
        uint8_t bitsPerPixel = data[i+16];
        uint8_t descriptor = data[i+17];

        // Texture dimensions 16-1024, aur BPP 24 ya 32 hona chahiye
        if (width < 16 || width > 1024) continue;
        if (height < 16 || height > 1024) continue;
        if (bitsPerPixel != 24 && bitsPerPixel != 32) continue;

        // Descriptor ke low nibble 0 ya 8 hona chahiye (alpha channel ke liye)
        if ((descriptor & 0x0F) != 0 && (descriptor & 0x0F) != 8) continue;

        std::cout << ">> VALID TGA at offset " << i 
                  << " | Type: " << (int)imageType
                  << " | Dim: " << width << "x" << height 
                  << " | BPP: " << (int)bitsPerPixel << std::endl;
        foundCount++;
        
        if (foundCount >= 15) break;
    }

    std::cout << "Total valid TGAs found: " << foundCount << std::endl;
    return 0;
}
