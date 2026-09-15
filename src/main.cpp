#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <iomanip>

int main() {
    std::cout << "Santa iOS Engine - Direct Offset Test" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // Header parhein
    uint32_t fileCount = 0;
    file.read(reinterpret_cast<char*>(&fileCount), sizeof(fileCount));
    std::cout << "Total Files: " << fileCount << std::endl;

    std::vector<uint32_t> offsets(fileCount);
    file.read(reinterpret_cast<char*>(offsets.data()), fileCount * sizeof(uint32_t));

    uint32_t headerSize = 4 + (fileCount * 4); // 4 bytes count + 4 bytes per offset

    // mouse.tga list mein 144th file hai (index 143)
    int mouseIndex = 143; 
    uint32_t mouseOffsetInHeader = offsets[mouseIndex];
    uint32_t absoluteMouseOffset = headerSize + mouseOffsetInHeader;

    std::cout << "mouse.tga Offset in header: " << mouseOffsetInHeader << std::endl;
    std::cout << "mouse.tga Absolute Offset in XPK: " << absoluteMouseOffset << std::endl;

    // Wahan se 18 bytes parhein (TGA header)
    file.seekg(absoluteMouseOffset, std::ios::beg);
    unsigned char tgaHeader[18];
    file.read(reinterpret_cast<char*>(tgaHeader), 18);

    uint16_t width = tgaHeader[12] | (tgaHeader[13] << 8);
    uint16_t height = tgaHeader[14] | (tgaHeader[15] << 8);
    uint8_t bitsPerPixel = tgaHeader[16];
    uint8_t imageType = tgaHeader[2];

    std::cout << "--- TGA Header at Offset " << absoluteMouseOffset << " ---" << std::endl;
    std::cout << "Image Type: " << (int)imageType << " (2=Uncompressed, 10=RLE)" << std::endl;
    std::cout << "Dimensions: " << width << " x " << height << " pixels" << std::endl;
    std::cout << "Bits Per Pixel: " << (int)bitsPerPixel << std::endl;

    return 0;
}
