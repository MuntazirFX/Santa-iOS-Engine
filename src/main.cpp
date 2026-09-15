#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main() {
    std::cout << "Santa iOS Engine - Smart TGA Finder" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // Data section 3843 bytes par shuru hota hai (jo humne pehle calculate kiya tha)
    uint32_t dataStart = 3843;
    
    file.seekg(0, std::ios::end);
    size_t fileSize = file.tellg();
    file.seekg(dataStart, std::ios::beg);

    std::vector<uint8_t> data(fileSize - dataStart);
    file.read(reinterpret_cast<char*>(data.data()), data.size());
    file.close();

    std::cout << "Data section loaded from " << dataStart << " to " << fileSize << std::endl;

    // TGA header ke possible starting patterns
    // 00 00 02 = Uncompressed TrueColor
    // 00 00 0A = RLE Compressed TrueColor
    std::vector<uint8_t> pattern1 = {0x00, 0x00, 0x02};
    std::vector<uint8_t> pattern2 = {0x00, 0x00, 0x0A};
    
    int foundCount = 0;
    for (size_t i = 0; i < data.size() - 18; ++i) {
        bool match = false;
        if (data[i] == pattern1[0] && data[i+1] == pattern1[1] && data[i+2] == pattern1[2]) match = true;
        if (data[i] == pattern2[0] && data[i+1] == pattern2[1] && data[i+2] == pattern2[2]) match = true;

        if (match) {
            // Header mila, ab isay validate karein
            uint16_t width = data[i+12] | (data[i+13] << 8);
            uint16_t height = data[i+14] | (data[i+15] << 8);
            uint8_t bitsPerPixel = data[i+16];
            uint8_t imageType = data[i+2];

            // Valid TGA hone ke liye dimensions aur bpp sahi hone chahiye
            if (width > 0 && height > 0 && (bitsPerPixel == 24 || bitsPerPixel == 32)) {
                std::cout << ">> VALID TGA FOUND at absolute offset: " << (dataStart + i) << std::endl;
                std::cout << "   Image Type: " << (int)imageType << " | Dimensions: " << width << "x" << height << " | BPP: " << (int)bitsPerPixel << std::endl;
                foundCount++;
                if (foundCount >= 10) break; // 10 mil jayein toh ruk jayein
            }
        }
    }
    std::cout << "Search complete. Total valid TGAs found: " << foundCount << std::endl;
    return 0;
}
