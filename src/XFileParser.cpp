#include "XFileParser.h"

#include <zlib.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

// ============================================================
// Debug log
// ============================================================

std::string& xpkDebugLog() {
    static std::string log;
    return log;
}

// ============================================================
// Safe readers
// ============================================================

static bool canRead(
    size_t offset,
    size_t amount,
    size_t size
) {
    return offset <= size &&
           amount <= (size - offset);
}

static uint16_t readU16(
    const uint8_t* data,
    size_t offset
) {
    return (uint16_t)data[offset] |
           ((uint16_t)data[offset + 1] << 8);
}

static uint32_t readU32(
    const uint8_t* data,
    size_t offset
) {
    return
        ((uint32_t)data[offset]) |
        ((uint32_t)data[offset + 1] << 8) |
        ((uint32_t)data[offset + 2] << 16) |
        ((uint32_t)data[offset + 3] << 24);
}

// ============================================================
// MSZip
//
// XPK compressed X files use MSZip blocks:
//
//     'C' 'K'
//     compressed DEFLATE stream
//
// The compressed stream itself is raw DEFLATE.
// ============================================================

std::vector<uint8_t>
XFileParser::decompressMSZip(
    const uint8_t* data,
    size_t size
) {
    xpkDebugLog().clear();

    std::vector<uint8_t> output;

    if (!data || size < 8) {
        return output;
    }

    size_t offset = 0;
    int blockNumber = 0;

    while (offset + 8 <= size &&
           blockNumber < 4096) {

        // ----------------------------------------------------
        // Search for CK signature.
        // ----------------------------------------------------

        size_t ckPos = offset;

        while (ckPos + 1 < size) {

            if (data[ckPos] == 'C' &&
                data[ckPos + 1] == 'K') {
                break;
            }

            ++ckPos;
        }

        if (ckPos + 1 >= size)
            break;

        // ----------------------------------------------------
        // MSZip block header.
        // ----------------------------------------------------

        size_t compressedStart =
            ckPos + 2;

        if (compressedStart >= size)
            break;

        // Existing Santa XPK data uses the two-byte size
        // field at CK+4.
        if (ckPos + 6 > size)
            break;

        uint16_t expectedSize =
            readU16(data, ckPos + 4);

        // Some malformed/search hits can look like CK.
        if (expectedSize == 0 ||
            expectedSize > 65535) {

            offset = compressedStart;
            ++blockNumber;
            continue;
        }

        std::vector<uint8_t> blockOutput(
            expectedSize
        );

        z_stream stream{};
        stream.next_in =
            const_cast<Bytef*>(
                reinterpret_cast<const Bytef*>(
                    data + compressedStart
                )
            );

        stream.avail_in =
            (uInt)(size - compressedStart);

        stream.next_out =
            reinterpret_cast<Bytef*>(
                blockOutput.data()
            );

        stream.avail_out =
            (uInt)blockOutput.size();

        int init =
            inflateInit2(
                &stream,
                -MAX_WBITS
            );

        if (init != Z_OK) {
            offset = compressedStart;
            ++blockNumber;
            continue;
        }

        int ret =
            inflate(
                &stream,
                Z_FINISH
            );

        size_t produced =
            (size_t)stream.total_out;

        size_t consumed =
            (size_t)stream.total_in;

        inflateEnd(&stream);

        if (produced > 0) {

            if (produced > blockOutput.size()) {
                produced = blockOutput.size();
            }

            output.insert(
                output.end(),
                blockOutput.begin(),
                blockOutput.begin() + produced
            );
        }

        // ----------------------------------------------------
        // Valid DEFLATE block.
        // ----------------------------------------------------

        if (ret == Z_STREAM_END &&
            consumed > 0) {

            offset =
                compressedStart + consumed;

        } else {

            // Do not get stuck at the same CK.
            offset =
                compressedStart;
        }

        ++blockNumber;
    }

    char logBuffer[256];

    std::snprintf(
        logBuffer,
        sizeof(logBuffer),
        "MSZip: %zu bytes, %d blocks\n",
        output.size(),
        blockNumber
    );

    xpkDebugLog() += logBuffer;

    return output;
}

// ============================================================
// X binary token parser
// ============================================================

std::vector<XToken>
XFileParser::parseTokens(
    const uint8_t* data,
    size_t size,
    int maxTokens
) {
    std::vector<XToken> tokens;

    if (!data ||
        size < 2 ||
        maxTokens <= 0) {
        return tokens;
    }

    size_t offset = 0;

    int templateDepth = 0;
    int braceDepth = 0;

    while (offset + 2 <= size &&
           (int)tokens.size() < maxTokens) {

        uint16_t tokenType =
            readU16(data, offset);

        offset += 2;

        // ----------------------------------------------------
        // Known binary X token range.
        // ----------------------------------------------------

        if (tokenType > 51) {
            // Unknown token. Stop instead of silently
            // desynchronizing the complete stream.
            break;
        }

        XToken token{};

        token.type = tokenType;
        token.intValue = 0;
        token.floatValue = 0.0f;
        token.dwordValue = 0;
        token.wordValue = 0;

        bool valid = true;

        switch (tokenType) {

            // ------------------------------------------------
            // NAME
            // ------------------------------------------------

            case 1: {

                if (!canRead(
                        offset,
                        4,
                        size)) {
                    valid = false;
                    break;
                }

                uint32_t length =
                    readU32(data, offset);

                offset += 4;

                if (length > 100000 ||
                    !canRead(
                        offset,
                        length,
                        size)) {
                    valid = false;
                    break;
                }

                token.name.assign(
                    reinterpret_cast<const char*>(
                        data + offset
                    ),
                    length
                );

                offset += length;

                break;
            }

            // ------------------------------------------------
            // STRING
            // ------------------------------------------------

            case 2: {

                if (!canRead(
                        offset,
                        4,
                        size)) {
                    valid = false;
                    break;
                }

                uint32_t length =
                    readU32(data, offset);

                offset += 4;

                if (length > 100000 ||
                    !canRead(
                        offset,
                        length,
                        size)) {
                    valid = false;
                    break;
                }

                token.name.assign(
                    reinterpret_cast<const char*>(
                        data + offset
                    ),
                    length
                );

                offset += length;

                // Santa X files use a two-byte terminator
                // following STRING data.
                if (canRead(offset, 2, size)) {
                    offset += 2;
                } else {
                    valid = false;
                }

                break;
            }

            // ------------------------------------------------
            // INT
            // ------------------------------------------------

            case 3: {

                if (!canRead(
                        offset,
                        4,
                        size)) {
                    valid = false;
                    break;
                }

                token.intValue =
                    (int32_t)readU32(
                        data,
                        offset
                    );

                offset += 4;

                break;
            }

            // ------------------------------------------------
            // GUID
            // ------------------------------------------------

            case 5: {

                if (!canRead(
                        offset,
                        16,
                        size)) {
                    valid = false;
                    break;
                }

                offset += 16;

                break;
            }

            // ------------------------------------------------
            // Integer list
            // ------------------------------------------------

            case 6: {

                if (!canRead(
                        offset,
                        4,
                        size)) {
                    valid = false;
                    break;
                }

                uint32_t count =
                    readU32(data, offset);

                offset += 4;

                if (count > 1000000 ||
                    !canRead(
                        offset,
                        (size_t)count * 4,
                        size)) {
                    valid = false;
                    break;
                }

                token.intList.reserve(count);

                for (uint32_t i = 0;
                     i < count;
                     ++i) {

                    token.intList.push_back(
                        (int32_t)readU32(
                            data,
                            offset
                        )
                    );

                    offset += 4;
                }

                break;
            }

            // ------------------------------------------------
            // Float list
            // ------------------------------------------------

            case 7: {

                if (!canRead(
                        offset,
                        4,
                        size)) {
                    valid = false;
                    break;
                }

                uint32_t count =
                    readU32(data, offset);

                offset += 4;

                if (count > 1000000 ||
                    !canRead(
                        offset,
                        (size_t)count * 4,
                        size)) {
                    valid = false;
                    break;
                }

                token.floatList.reserve(count);

                for (uint32_t i = 0;
                     i < count;
                     ++i) {

                    uint32_t bits =
                        readU32(
                            data,
                            offset
                        );

                    float value;

                    std::memcpy(
                        &value,
                        &bits,
                        sizeof(float)
                    );

                    token.floatList.push_back(
                        value
                    );

                    offset += 4;
                }

                break;
            }

            // ------------------------------------------------
            // Braces / punctuation
            // ------------------------------------------------

            case 10:
                ++braceDepth;
                break;

            case 11:
                if (braceDepth > 0)
                    --braceDepth;
                break;

            case 12:
            case 13:
            case 14:
            case 15:
            case 16:
            case 17:
            case 18:
            case 19:
            case 20:
                break;

            // ------------------------------------------------
            // TEMPLATE
            // ------------------------------------------------

            case 31:
                ++templateDepth;
                break;

            // ------------------------------------------------
            // WORD
            // ------------------------------------------------

            case 40:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            2,
                            size)) {
                        valid = false;
                        break;
                    }

                    token.wordValue =
                        readU16(
                            data,
                            offset
                        );

                    offset += 2;
                }

                break;

            // ------------------------------------------------
            // DWORD
            // ------------------------------------------------

            case 41:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            4,
                            size)) {
                        valid = false;
                        break;
                    }

                    token.dwordValue =
                        (int32_t)readU32(
                            data,
                            offset
                        );

                    offset += 4;
                }

                break;

            // ------------------------------------------------
            // FLOAT
            // ------------------------------------------------

            case 42:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            4,
                            size)) {
                        valid = false;
                        break;
                    }

                    uint32_t bits =
                        readU32(
                            data,
                            offset
                        );

                    std::memcpy(
                        &token.floatValue,
                        &bits,
                        sizeof(float)
                    );

                    offset += 4;
                }

                break;

            // ------------------------------------------------
            // DOUBLE
            // ------------------------------------------------

            case 43:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            8,
                            size)) {
                        valid = false;
                        break;
                    }

                    offset += 8;
                }

                break;

            // ------------------------------------------------
            // CHAR / UCHAR
            // ------------------------------------------------

            case 44:
            case 45:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            1,
                            size)) {
                        valid = false;
                        break;
                    }

                    offset += 1;
                }

                break;

            // ------------------------------------------------
            // SWORD
            // ------------------------------------------------

            case 46:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            2,
                            size)) {
                        valid = false;
                        break;
                    }

                    offset += 2;
                }

                break;

            // ------------------------------------------------
            // SDWORD
            // ------------------------------------------------

            case 47:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            4,
                            size)) {
                        valid = false;
                        break;
                    }

                    offset += 4;
                }

                break;

            // ------------------------------------------------
            // LPSTR / UNICODE / CSTRING
            // ------------------------------------------------

            case 48:
            case 49:
            case 50:

                if (templateDepth == 0) {

                    if (!canRead(
                            offset,
                            4,
                            size)) {
                        valid = false;
                        break;
                    }

                    uint32_t length =
                        readU32(
                            data,
                            offset
                        );

                    offset += 4;

                    if (length > 100000 ||
                        !canRead(
                            offset,
                            length,
                            size)) {
                        valid = false;
                        break;
                    }

                    offset += length;
                }

                break;

            // ------------------------------------------------
            // ARRAY
            // ------------------------------------------------

            case 51:
                break;

            default:
                break;
        }

        if (!valid)
            break;

        tokens.push_back(
            std::move(token)
        );
    }

    return tokens;
}

// ============================================================
// Token description
// ============================================================

std::string
XFileParser::describeToken(
    const XToken& token
) {
    std::ostringstream out;

    switch (token.type) {

        case 1:
            out << "NAME: \"" << token.name << "\"";
            break;

        case 2:
            out << "STRING: \"" << token.name << "\"";
            break;

        case 3:
            out << "INT: " << token.intValue;
            break;

        case 5:
            out << "GUID";
            break;

        case 6:
            out << "ILIST("
                << token.intList.size()
                << ")";
            break;

        case 7:
            out << "FLIST("
                << token.floatList.size()
                << ")";
            break;

        case 10:
            out << "{";
            break;

        case 11:
            out << "}";
            break;

        case 12:
            out << "(";
            break;

        case 13:
            out << ")";
            break;

        case 14:
            out << "[";
            break;

        case 15:
            out << "]";
            break;

        case 16:
            out << "<";
            break;

        case 17:
            out << ">";
            break;

        case 18:
            out << ".";
            break;

        case 19:
            out << ",";
            break;

        case 20:
            out << ";";
            break;

        case 31:
            out << "TEMPLATE";
            break;

        case 40:
            out << "WORD";
            break;

        case 41:
            out << "DWORD";
            break;

        case 42:
            out << "FLOAT";
            break;

        case 43:
            out << "DOUBLE";
            break;

        case 44:
            out << "CHAR";
            break;

        case 45:
            out << "UCHAR";
            break;

        case 46:
            out << "SWORD";
            break;

        case 47:
            out << "SDWORD";
            break;

        case 48:
            out << "LPSTR";
            break;

        case 49:
            out << "UNICODE";
            break;

        case 50:
            out << "CSTRING";
            break;

        case 51:
            out << "ARRAY";
            break;

        default:
            out << "UNKNOWN("
                << token.type
                << ")";
            break;
    }

    return out.str();
}
