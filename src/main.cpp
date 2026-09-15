#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

int main() {
    std::cout << "Santa iOS Engine - TGA to PPM Converter" << std::endl;

    std::ifstream file("assets/xmas.xpk", std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Error: assets/xmas.xpk file nahi mili!" << std::endl;
        return 1;
    }

    // Pehli TGA ka offset
    uint32_t tgaOffset = 5642606;
    
    file.seekg(tgaOffset, std::ios::beg);
    
    // TGA Header parhein (18 bytes)
    unsigned char header[18];
    file.read(reinterpret_cast<char*>(header), 18);

    uint8_t idLength = header[0];
    uint8_t imageType = header[2];
    uint16_t width = header[12] | (header[13] << 8);
    uint16_t height = header[14] | (header[15] << 8);
    uint8_t bitsPerPixel = header[16];
    uint8_t imageDescriptor = header[17];

    std::cout << "TGA Info: " << width << "x" << height << " | BPP: " << (int)bitsPerPixel << " | Type: " << (int)imageType << std::endl;

    // Pixel data ka start (ID length ke baad)
    uint32_t pixelDataStart = tgaOffset + 18 + idLength;
    file.seekg(pixelDataStart, std::ios::beg);

    // Pixels parhein
    int bytesPerPixel = bitsPerPixel / 8;
    int imageSize = width * height * bytesPerPixel;
    std::vector<uint8_t> pixels(imageSize);
    file.read(reinterpret_cast<char*>(pixels.data()), imageSize);
    file.close();

    // Ab PPM file banayein (P6 format mein)
    std::ofstream ppmFile("test_output.ppm", std::ios::binary);
    ppmFile << "P6\n" << width << " " << height << "\n255\n";

    // TGA BGR format mein hota hai, PPM RGB chahta hai
    for (int i = 0; i < width * height; ++i) {
        uint8_t b = pixels[i * bytesPerPixel];
        uint8_t g = pixels[i * bytesPerPixel + 1];
        uint8_t r = pixels[i * bytesPerPixel + 2];
        
        ppmFile.write(reinterpret_cast<char*>(&r), 1);
        ppmFile.write(reinterpret_cast<char*>(&g), 1);
        ppmFile.write(reinterpret_cast<char*>(&b), 1);
    }
    ppmFile.close();

    std::cout << "test_output.ppm successfully ban gayi!" << std::endl;
    return 0;
}
