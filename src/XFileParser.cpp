#include "XFileParser.h"
#include <cstring>
#include <cstdio>
#include <sstream>
#include <zlib.h>

std::string& xpkDebugLog() {
    static std::string log;
    return log;
}

static uint32_t readU32(const uint8_t* data, size_t offset) {
    return data[offset] | (data[offset+1] << 8) | (data[offset+2] << 16) | (data[offset+3] << 24);
}

static uint16_t readU16(const uint8_t* data, size_t offset) {
    return data[offset] | (data[offset+1] << 8);
}

// MSZip / bzip decompression — CK+2 start, raw deflate
std::vector<uint8_t> XFileParser::decompressMSZip(const uint8_t* data, size_t size) {
    xpkDebugLog().clear();
    std::vector<uint8_t> output;
    if (size < 30) return output;
    
    char buf[512];
    size_t offset = 0;
    int blockNum = 0;
    
    while (offset + 6 <= size && blockNum < 20) {
        // Scan for CK
        while (offset + 1 < size && !(data[offset] == 0x43 && data[offset+1] == 0x4B)) {
            offset++;
        }
        if (offset + 6 > size) break;
        
        size_t ckPos = offset;
        
        // Try decompression starting at CK+2 (data starts at compSize field)
        size_t startOffset = ckPos + 2;
        if (startOffset >= size) break;
        
        // Read uncompSize (for buffer size)
        uint16_t uncompSize = readU16(data, ckPos + 4);
        if (uncompSize == 0 || uncompSize > 100000) {
            snprintf(buf, sizeof(buf), "Block %d: invalid uncompSize %u\n", blockNum, uncompSize);
            xpkDebugLog() += buf;
            offset = ckPos + 6;
            continue;
        }
        
        uint8_t* outBuf = new uint8_t[uncompSize];
        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        strm.next_in = (Bytef*)(data + startOffset);
        strm.avail_in = (uInt)(size - startOffset);
        strm.next_out = outBuf;
        strm.avail_out = uncompSize;
        
        if (inflateInit2(&strm, -MAX_WBITS) == Z_OK) {
            int ret = inflate(&strm, Z_FINISH);
            uLong totalOut = strm.total_out;
            inflateEnd(&strm);
            
            snprintf(buf, sizeof(buf), "Block %d: CK=%zu, uncomp=%u, ret=%d, totalOut=%lu\n",
                     blockNum, ckPos, uncompSize, ret, totalOut);
            xpkDebugLog() += buf;
            
            if (totalOut > 0) {
                output.insert(output.end(), outBuf, outBuf + totalOut);
            }
            delete[] outBuf;
            
            if (ret == Z_STREAM_END) {
                // Find next CK block
                offset = ckPos + 6 + totalOut;
                blockNum++;
                continue;
            }
        } else {
            delete[] outBuf;
        }
        
        offset = ckPos + 6;
        blockNum++;
    }
    
    snprintf(buf, sizeof(buf), "Total decompressed: %lu bytes across %d blocks\n",
             (unsigned long)output.size(), blockNum);
    xpkDebugLog() += buf;
    
    return output;
}

// Token parser — starts at offset 0 (no 16-byte header in bzip)
std::vector<XToken> XFileParser::parseTokens(const uint8_t* data, size_t size, int maxTokens) {
    std::vector<XToken> tokens;
    if (size < 4) return tokens;
    size_t offset = 0;
    
    while (offset < size && (int)tokens.size() < maxTokens) {
        uint16_t tokenType = readU16(data, offset);
        offset += 2;
        
        XToken token;
        token.type = tokenType;
        token.intValue = 0;
        token.floatValue = 0;
        token.dwordValue = 0;
        token.wordValue = 0;
        
        switch (tokenType) {
            case 1: { // NAME
                uint32_t len = readU32(data, offset);
                offset += 4;
                if (offset + len > size) { offset = size; break; }
                token.name = std::string((const char*)(data + offset), len);
                offset += len;
                break;
            }
            case 2: { // STRING
                uint32_t len = readU32(data, offset);
                offset += 4;
                if (offset + len > size) { offset = size; break; }
                token.name = std::string((const char*)(data + offset), len);
                offset += len;
                break;
            }
            case 3: token.intValue = (int)readU32(data, offset); offset += 4; break;
            case 5: offset += 16; break;
            case 6: { // INTEGER_LIST
                uint32_t count = readU32(data, offset);
                offset += 4;
                if (count > 100000) { offset = size; break; }
                for (uint32_t i = 0; i < count && offset + 4 <= size; i++) {
                    token.intList.push_back((int)readU32(data, offset));
                    offset += 4;
                }
                break;
            }
            case 7: { // FLOAT_LIST
                uint32_t count = readU32(data, offset);
                offset += 4;
                if (count > 100000) { offset = size; break; }
                for (uint32_t i = 0; i < count && offset + 4 <= size; i++) {
                    uint32_t bits = readU32(data, offset);
                    float f; memcpy(&f, &bits, 4);
                    token.floatList.push_back(f);
                    offset += 4;
                }
                break;
            }
            case 10: case 11: case 12: case 13:
            case 14: case 15: case 16: case 17:
            case 18: case 19: case 20:
            case 31:
                break;
            case 40: token.wordValue = readU16(data, offset); offset += 2; break;
            case 41: token.dwordValue = (int)readU32(data, offset); offset += 4; break;
            case 42: {
                uint32_t bits = readU32(data, offset);
                memcpy(&token.floatValue, &bits, 4);
                offset += 4;
                break;
            }
            case 43: offset += 8; break;
            case 44: case 45: offset += 1; break;
            case 46: offset += 2; break;
            case 47: offset += 4; break;
            default: offset = size; break;
        }
        tokens.push_back(token);
    }
    return tokens;
}

std::string XFileParser::describeToken(const XToken& token) {
    std::ostringstream oss;
    switch (token.type) {
        case 1: oss << "NAME: \"" << token.name << "\""; break;
        case 2: oss << "STR:  \"" << token.name << "\""; break;
        case 3: oss << "INT:  " << token.intValue; break;
        case 5: oss << "GUID"; break;
        case 6: oss << "ILIST(" << token.intList.size() << ")"; break;
        case 7: oss << "FLIST(" << token.floatList.size() << ")"; break;
        case 10: oss << "{"; break;
        case 11: oss << "}"; break;
        case 12: oss << "("; break;
        case 13: oss << ")"; break;
        case 14: oss << "["; break;
        case 15: oss << "]"; break;
        case 16: oss << "<"; break;
        case 17: oss << ">"; break;
        case 18: oss << "."; break;
        case 19: oss << ","; break;
        case 20: oss << ";"; break;
        case 31: oss << "TEMPLATE"; break;
        case 40: oss << "WORD: " << token.wordValue; break;
        case 41: oss << "DWORD:" << token.dwordValue; break;
        case 42: oss << "FLOAT:" << token.floatValue; break;
        case 43: oss << "DOUBLE"; break;
        case 44: oss << "CHAR"; break;
        case 45: oss << "UCHAR"; break;
        case 46: oss << "SWORD"; break;
        case 47: oss << "DWORD2"; break;
        default: oss << "??(" << token.type << ")"; break;
    }
    return oss.str();
}
