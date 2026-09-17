#include "AssetManager.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include <limits>


// ============================================================
// Destructor
// ============================================================

AssetManager::~AssetManager()
{
    if (xpkFile.is_open())
    {
        xpkFile.close();
    }
}


// ============================================================
// Load XPK
//
// Santa XPK:
//
// [uint32 fileCount]
// [uint32 offset[fileCount]]
// [metadata entries]
// [raw file data]
//
// Metadata:
//
// [uint32 fileSize]
// [null terminated filename]
//
// offsets are relative to the beginning of the metadata area.
// ============================================================

bool AssetManager::loadXPK(
    const std::string& filepath
)
{
    // --------------------------------------------------------
    // Reset old state
    // --------------------------------------------------------

    if (xpkFile.is_open())
    {
        xpkFile.close();
    }

    fileTable.clear();
    orderedFilenames.clear();


    // --------------------------------------------------------
    // Validate path
    // --------------------------------------------------------

    if (filepath.empty())
    {
        std::cerr
            << "[XPK] ERROR: empty filepath"
            << std::endl;

        return false;
    }


    std::cout
        << "[XPK] Trying to open: "
        << filepath
        << std::endl;


    // --------------------------------------------------------
    // First verify with C fopen().
    //
    // This gives a useful distinction between:
    //   - path/access failure
    //   - C++ stream failure
    // --------------------------------------------------------

    FILE *testFile =
        std::fopen(
            filepath.c_str(),
            "rb"
        );


    if (!testFile)
    {
        std::cerr
            << "[XPK] fopen FAILED: "
            << std::strerror(errno)
            << std::endl;

        std::cerr
            << "[XPK] Path: "
            << filepath
            << std::endl;

        return false;
    }


    if (std::fseek(
            testFile,
            0,
            SEEK_END
        ) != 0)
    {
        std::cerr
            << "[XPK] fseek failed"
            << std::endl;

        std::fclose(testFile);

        return false;
    }


    long long cFileLength =
        std::ftell(testFile);


    std::rewind(testFile);

    std::fclose(testFile);


    std::cout
        << "[XPK] fopen OK, size="
        << cFileLength
        << std::endl;


    if (cFileLength < 4)
    {
        std::cerr
            << "[XPK] ERROR: file smaller than header"
            << std::endl;

        return false;
    }


    // --------------------------------------------------------
    // Open using C++ stream
    // --------------------------------------------------------

    xpkFile.open(
        filepath.c_str(),
        std::ios::in |
        std::ios::binary
    );


    if (!xpkFile.is_open())
    {
        std::cerr
            << "[XPK] ifstream FAILED"
            << std::endl;

        return false;
    }


    // --------------------------------------------------------
    // Determine file size
    // --------------------------------------------------------

    xpkFile.seekg(
        0,
        std::ios::end
    );


    std::streamoff fileLength =
        xpkFile.tellg();


    if (fileLength < 4)
    {
        std::cerr
            << "[XPK] ERROR: invalid file length"
            << std::endl;

        xpkFile.close();

        return false;
    }


    xpkFile.seekg(
        0,
        std::ios::beg
    );


    std::cout
        << "[XPK] ifstream size="
        << fileLength
        << std::endl;


    // --------------------------------------------------------
    // File count
    // --------------------------------------------------------

    uint32_t fileCount = 0;


    xpkFile.read(
        reinterpret_cast<char*>(&fileCount),
        sizeof(fileCount)
    );


    if (!xpkFile ||
        fileCount == 0 ||
        fileCount > 100000)
    {
        std::cerr
            << "[XPK] ERROR: invalid file count: "
            << fileCount
            << std::endl;

        xpkFile.close();

        return false;
    }


    std::cout
        << "[XPK] File count="
        << fileCount
        << std::endl;


    // --------------------------------------------------------
    // Offset table
    // --------------------------------------------------------

    const uint64_t headerSize =
        4ULL +
        static_cast<uint64_t>(fileCount) * 4ULL;


    if (static_cast<uint64_t>(fileLength) <
        headerSize)
    {
        std::cerr
            << "[XPK] ERROR: archive shorter than offset table"
            << std::endl;

        xpkFile.close();

        return false;
    }


    std::vector<uint32_t> offsets(
        fileCount
    );


    xpkFile.read(
        reinterpret_cast<char*>(offsets.data()),
        static_cast<std::streamsize>(
            fileCount * sizeof(uint32_t)
        )
    );


    if (!xpkFile)
    {
        std::cerr
            << "[XPK] ERROR: could not read offset table"
            << std::endl;

        xpkFile.close();

        return false;
    }


    // --------------------------------------------------------
    // Metadata
    // --------------------------------------------------------

    struct PendingEntry
    {
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
         ++i)
    {
        uint64_t metadataPosition =
            headerSize +
            static_cast<uint64_t>(offsets[i]);


        if (metadataPosition + 4ULL >
            static_cast<uint64_t>(fileLength))
        {
            std::cerr
                << "[XPK] ERROR: invalid metadata offset "
                << i
                << " = "
                << offsets[i]
                << std::endl;

            xpkFile.close();

            return false;
        }


        xpkFile.clear();


        xpkFile.seekg(
            static_cast<std::streamoff>(
                metadataPosition
            ),
            std::ios::beg
        );


        if (!xpkFile)
        {
            std::cerr
                << "[XPK] ERROR: seek metadata failed "
                << i
                << std::endl;

            xpkFile.close();

            return false;
        }


        uint32_t fileSize = 0;


        xpkFile.read(
            reinterpret_cast<char*>(&fileSize),
            sizeof(fileSize)
        );


        if (!xpkFile)
        {
            std::cerr
                << "[XPK] ERROR: could not read file size "
                << i
                << std::endl;

            xpkFile.close();

            return false;
        }


        // ----------------------------------------------------
        // Filename
        // ----------------------------------------------------

        std::string filename;

        bool foundNull = false;


        for (size_t n = 0;
             n < 65536;
             ++n)
        {
            char c = 0;


            xpkFile.read(
                &c,
                1
            );


            if (!xpkFile)
            {
                break;
            }


            if (c == '\0')
            {
                foundNull = true;
                break;
            }


            filename.push_back(c);
        }


        if (!foundNull ||
            filename.empty())
        {
            std::cerr
                << "[XPK] ERROR: invalid filename at entry "
                << i
                << std::endl;

            xpkFile.close();

            return false;
        }


        // ----------------------------------------------------
        // Calculate metadata endpoint
        // ----------------------------------------------------

        uint64_t entryEnd =
            metadataPosition +
            4ULL +
            static_cast<uint64_t>(
                filename.size()
            ) +
            1ULL;


        metadataEnd =
            std::max(
                metadataEnd,
                entryEnd
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
    // Data begins immediately after metadata.
    // --------------------------------------------------------

    uint64_t dataStart =
        metadataEnd;


    if (dataStart >
        static_cast<uint64_t>(fileLength))
    {
        std::cerr
            << "[XPK] ERROR: data start outside archive"
            << std::endl;

        xpkFile.close();

        return false;
    }


    std::cout
        << "[XPK] Metadata end="
        << dataStart
        << std::endl;


    // --------------------------------------------------------
    // Build file table
    // --------------------------------------------------------

    uint64_t currentData =
        dataStart;


    for (const PendingEntry& pendingEntry :
         pending)
    {
        uint64_t nextData =
            currentData +
            static_cast<uint64_t>(
                pendingEntry.size
            );


        if (nextData >
            static_cast<uint64_t>(fileLength))
        {
            std::cerr
                << "[XPK] ERROR: file data exceeds archive: "
                << pendingEntry.filename
                << " size="
                << pendingEntry.size
                << std::endl;

            xpkFile.close();

            return false;
        }


        if (currentData >
            std::numeric_limits<uint32_t>::max())
        {
            std::cerr
                << "[XPK] ERROR: data offset exceeds uint32"
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
            static_cast<uint32_t>(
                currentData
            );


        fileTable[entry.filename] =
            entry;


        orderedFilenames.push_back(
            entry.filename
        );


        currentData =
            nextData;
    }


    // --------------------------------------------------------
    // Final validation
    // --------------------------------------------------------

    if (fileTable.empty())
    {
        std::cerr
            << "[XPK] ERROR: no files in archive"
            << std::endl;

        xpkFile.close();

        return false;
    }


    std::cout
        << "[XPK] SUCCESS: loaded "
        << fileTable.size()
        << " files"
        << std::endl;


    std::cout
        << "[XPK] Data start="
        << dataStart
        << std::endl;


    return true;
}


// ============================================================
// Get Asset
// ============================================================

std::vector<uint8_t>
AssetManager::getAssetData(
    const std::string& filename
)
{
    auto it =
        fileTable.find(filename);


    // --------------------------------------------------------
    // Slash normalization
    // --------------------------------------------------------

    if (it == fileTable.end())
    {
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


        if (it == fileTable.end())
        {
            std::replace(
                normalized.begin(),
                normalized.end(),
                '\\',
                '/'
            );


            it =
                fileTable.find(normalized);
        }
    }


    if (it == fileTable.end())
    {
        std::cerr
            << "[XPK] Asset not found: "
            << filename
            << std::endl;

        return {};
    }


    const XPKEntry& entry =
        it->second;


    if (!xpkFile.is_open())
    {
        std::cerr
            << "[XPK] ERROR: XPK stream is closed"
            << std::endl;

        return {};
    }


    if (entry.size == 0)
    {
        return {};
    }


    // --------------------------------------------------------
    // Read file
    // --------------------------------------------------------

    std::vector<uint8_t> data(
        entry.size
    );


    xpkFile.clear();


    xpkFile.seekg(
        static_cast<std::streamoff>(
            entry.offset
        ),
        std::ios::beg
    );


    if (!xpkFile)
    {
        std::cerr
            << "[XPK] ERROR: seek failed for "
            << entry.filename
            << " offset="
            << entry.offset
            << std::endl;

        return {};
    }


    xpkFile.read(
        reinterpret_cast<char*>(
            data.data()
        ),
        static_cast<std::streamsize>(
            entry.size
        )
    );


    std::streamsize actual =
        xpkFile.gcount();


    if (actual !=
        static_cast<std::streamsize>(
            entry.size
        ))
    {
        std::cerr
            << "[XPK] ERROR: short read for "
            << entry.filename
            << " expected="
            << entry.size
            << " actual="
            << actual
            << std::endl;

        return {};
    }


    return data;
}


// ============================================================
// All filenames
// ============================================================

std::vector<std::string>
AssetManager::getAllFilenames()
{
    return orderedFilenames;
}
