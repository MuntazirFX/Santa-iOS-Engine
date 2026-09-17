#include "AssetManager.h"

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

// ============================================================
// Destructor
// ============================================================

AssetManager::~AssetManager() {
    if (xpkFile.is_open()) {
        xpkFile.close();
    }
}

// ============================================================
// Load XPK
//
// Structure used by current Santa XPK:
//
// [uint32 fileCount]
// [uint32 offset[fileCount]]
// [metadata entries]
// [raw file data]
//
// Each metadata entry:
//
// [uint32 fileSize]
// [null terminated filename]
//
// offsets point into the metadata area.
// ============================================================

bool AssetManager::loadXPK(
    const std::string& filepath
) {
    // --------------------------------------------------------
    // Reset previous state.
    // --------------------------------------------------------

    if (xpkFile.is_open()) {
        xpkFile.close();
    }

    fileTable.clear();
    orderedFilenames.clear();

    // --------------------------------------------------------
    // Open
    // --------------------------------------------------------

    xpkFile.open(
        filepath,
        std::ios::binary
    );

    if (!xpkFile.is_open()) {

        std::cerr
            << "Failed to open XPK: "
            << filepath
            << std::endl;

        return false;
    }

    // --------------------------------------------------------
    // File size
    // --------------------------------------------------------

    xpkFile.seekg(
        0,
        std::ios::end
    );

    std::streamoff fileLength =
        xpkFile.tellg();

    if (fileLength < 4) {
        xpkFile.close();
        return false;
    }

    xpkFile.seekg(
        0,
        std::ios::beg
    );

    // --------------------------------------------------------
    // File count
    // --------------------------------------------------------

    uint32_t fileCount = 0;

    xpkFile.read(
        reinterpret_cast<char*>(&fileCount),
        sizeof(fileCount)
    );

    if (!xpkFile.good() ||
        fileCount == 0 ||
        fileCount > 100000) {

        std::cerr
            << "Invalid XPK file count"
            << std::endl;

        xpkFile.close();
        return false;
    }

    // --------------------------------------------------------
    // Offset table
    // --------------------------------------------------------

    const uint64_t headerSize =
        4ULL +
        (uint64_t)fileCount * 4ULL;

    if ((uint64_t)fileLength <
        headerSize) {

        xpkFile.close();
        return false;
    }

    std::vector<uint32_t> offsets(
        fileCount
    );

    xpkFile.read(
        reinterpret_cast<char*>(
            offsets.data()
        ),
        (std::streamsize)(
            fileCount * sizeof(uint32_t)
        )
    );

    if (!xpkFile.good()) {

        xpkFile.close();
        return false;
    }

    // --------------------------------------------------------
    // Read metadata.
    // --------------------------------------------------------

    struct PendingEntry {
        std::string filename;
        uint32_t size;
        uint32_t metadataOffset;
    };

    std::vector<PendingEntry> pending;
    pending.reserve(fileCount);

    uint64_t metadataEnd =
        headerSize;

    for (uint32_t i = 0;
         i < fileCount;
         ++i) {

        uint64_t metadataPosition =
            headerSize +
            (uint64_t)offsets[i];

        if (metadataPosition + 4 >
            (uint64_t)fileLength) {

            std::cerr
                << "Invalid XPK metadata offset: "
                << i
                << std::endl;

            xpkFile.close();
            return false;
        }

        xpkFile.seekg(
            (std::streamoff)metadataPosition,
            std::ios::beg
        );

        uint32_t fileSize = 0;

        xpkFile.read(
            reinterpret_cast<char*>(&fileSize),
            sizeof(fileSize)
        );

        if (!xpkFile.good()) {

            xpkFile.close();
            return false;
        }

        std::string filename;

        // ----------------------------------------------------
        // Read null-terminated filename safely.
        // ----------------------------------------------------

        bool foundNull = false;

        for (size_t n = 0;
             n < 65536;
             ++n) {

            char c = 0;

            xpkFile.read(
                &c,
                1
            );

            if (!xpkFile.good()) {
                break;
            }

            if (c == '\0') {
                foundNull = true;
                break;
            }

            filename.push_back(c);
        }

        if (!foundNull ||
            filename.empty()) {

            std::cerr
                << "Invalid XPK filename at entry "
                << i
                << std::endl;

            xpkFile.close();
            return false;
        }

        uint64_t end =
            metadataPosition +
            4ULL +
            (uint64_t)filename.size() +
            1ULL;

        metadataEnd =
            std::max(
                metadataEnd,
                end
            );

        PendingEntry entry;

        entry.filename =
            filename;

        entry.size =
            fileSize;

        entry.metadataOffset =
            offsets[i];

        pending.push_back(
            std::move(entry)
        );
    }

    // --------------------------------------------------------
    // Data area.
    //
    // The metadata entries are described by offsets. We use
    // the highest metadata endpoint rather than relying on the
    // last offset entry being ordered.
    // --------------------------------------------------------

    uint64_t dataStart =
        metadataEnd;

    if (dataStart >
        (uint64_t)fileLength) {

        xpkFile.close();
        return false;
    }

    // --------------------------------------------------------
    // Build data offsets.
    //
    // The archive's files are stored sequentially in metadata
    // table order.
    // --------------------------------------------------------

    uint64_t currentData =
        dataStart;

    for (const PendingEntry& pendingEntry :
         pending) {

        if (currentData +
            pendingEntry.size >
            (uint64_t)fileLength) {

            std::cerr
                << "XPK file data exceeds archive: "
                << pendingEntry.filename
                << std::endl;

            xpkFile.close();
            return false;
        }

        XPKEntry entry;

        entry.filename =
            pendingEntry.filename;

        entry.size =
            pendingEntry.size;

        entry.offset =
            (uint32_t)currentData;

        fileTable[entry.filename] =
            entry;

        orderedFilenames.push_back(
            entry.filename
        );

        currentData +=
            pendingEntry.size;
    }

    std::cout
        << "XPK loaded: "
        << fileTable.size()
        << " files, data start "
        << dataStart
        << std::endl;

    return !fileTable.empty();
}

// ============================================================
// Get asset
// ============================================================

std::vector<uint8_t>
AssetManager::getAssetData(
    const std::string& filename
) {
    auto it =
        fileTable.find(filename);

    if (it == fileTable.end()) {

        // ----------------------------------------------------
        // Exact path failed. Try slash normalization because
        // XPK archives can contain Windows-style paths.
        // ----------------------------------------------------

        std::string normalized =
            filename;

        std::replace(
            normalized.begin(),
            normalized.end(),
            '/',
            '\\'
        );

        it =
            fileTable.find(normalized);

        if (it == fileTable.end()) {

            std::replace(
                normalized.begin(),
                normalized.end(),
                '\\',
                '/'
            );

            it =
                fileTable.find(normalized);

            if (it == fileTable.end()) {
                return {};
            }
        }
    }

    const XPKEntry& entry =
        it->second;

    if (!xpkFile.is_open() ||
        entry.size == 0) {
        return {};
    }

    // --------------------------------------------------------
    // Read
    // --------------------------------------------------------

    std::vector<uint8_t> data(
        entry.size
    );

    xpkFile.clear();

    xpkFile.seekg(
        (std::streamoff)entry.offset,
        std::ios::beg
    );

    if (!xpkFile.good()) {
        return {};
    }

    xpkFile.read(
        reinterpret_cast<char*>(
            data.data()
        ),
        (std::streamsize)entry.size
    );

    if (!xpkFile.good() &&
        !xpkFile.eof()) {
        return {};
    }

    std::streamsize actual =
        xpkFile.gcount();

    if (actual !=
        (std::streamsize)entry.size) {
        return {};
    }

    return data;
}

// ============================================================
// All filenames
// ============================================================

std::vector<std::string>
AssetManager::getAllFilenames() {
    return orderedFilenames;
}
