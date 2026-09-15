#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <filesystem>
#include <algorithm>

namespace fs = std::filesystem;

struct FileEntry {
    std::string filename;
    uint32_t size;
};

int main() {
    std::cout << "Santa iOS Engine - XPK Extractor" << std::endl;

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

    uint32_t headerSize = 4 + (fileCount * 4);
    std::cout << "Header Size: " << headerSize << " bytes" << std::endl;

    // Metadata (size + filename) parhein
    std::vector<FileEntry> fileEntries;
    uint32_t totalMetadataSize = 0;
    
    for (uint32_t i = 0; i < fileCount; ++i) {
        file.seekg(headerSize + offsets[i], std::ios::beg);
        
        uint32_t fileSize = 0;
        file.read(reinterpret_cast<char*>(&fileSize), sizeof(fileSize));

        std::string filename;
        char ch;
        while (file.get(ch) && ch != '\0') {
            filename += ch;
        }

        fileEntries.push_back({filename, fileSize});
        totalMetadataSize = offsets[i] + 4 + filename.length() + 1;
    }

    // Data section kahan se shuru hota hai
    uint32_t dataStart = headerSize + totalMetadataSize;
    std::cout << "Data starts at: " << dataStart << std::endl;

    // 'extracted' folder banayein
    fs::create_directory("extracted");

    // Har file ko extract karein
    for (const auto& entry : fileEntries) {
        std::string outPath = "extracted/" + entry.filename;
        std::replace(outPath.begin(), outPath.end(), '\\', '/'); // Windows paths ko Mac/Linux paths mein badlein

        fs::path p(outPath);
        fs::create_directories(p.parent_path()); // Folder banayein (jaise extracted/maps/)

        std::ofstream outFile(outPath, std::ios::binary);
        if (!outFile.is_open()) {
            std::cerr << "Failed to create: " << outPath << std::endl;
            continue;
        }

        file.seekg(dataStart, std::ios::beg);
        std::vector<char> buffer(entry.size);
        file.read(buffer.data(), entry.size);
        outFile.write(buffer.data(), entry.size);
        outFile.close();

        std::cout << "Extracted: " << entry.filename << " | Size: " << entry.size << " bytes" << std::endl;
        dataStart += entry.size; // Agli file ke data par jayein
    }

    std::cout << "Extraction Complete!" << std::endl;
    return 0;
}
