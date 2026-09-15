#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main() {
    std::cout << "Santa iOS Engine - TGA Parser Test" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // Jo offset humne search se dhoonda tha
    uint32_t tgaOffset = 54469;
    
    file.seekg(tgaOffset, std::ios::beg);
    unsigned char header[18];
    file.read(reinterpret_cast<char*>(header), 18);

    uint8_t idLength = header[0];
    uint8_t colorMapType = header[1];
    uint8_t imageType = header[2];
    uint16_t width = header[12] | (header[13] << 8);
    uint16_t height = header[14] | (header[15] << 8);
    uint8_t bitsPerPixel = header[16];

    std::cout << "--- TGA Header at Offset " << tgaOffset << " ---" << std::endl;
    std::cout << "ID Length: " << (int)idLength << std::endl;
    std::cout << "Color Map Type: " << (int)colorMapType << std::endl;
    std::cout << "Image Type: " << (int)imageType << " (2=Uncompressed, 10=RLE Compressed)" << std::endl;
    std::cout << "Dimensions: " << width << " x " << height << " pixels" << std::endl;
    std::cout << "Bits Per Pixel: " << (int)bitsPerPixel << std::endl;

    return 0;
}
