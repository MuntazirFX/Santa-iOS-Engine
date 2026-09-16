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

// MSZip decompression with full debug logging
std::vector<uint8_t> XFileParser::decompressMSZip(const uint8_t* data, size_t size) {
    xpkDebugLog().clear();
    std::vector<uint8_t> output;
    if (size < 30) {
        xpkDebugLog() += "Size too small\n";
        return output;
    }
    
    char buf[512];
    snprintf(buf, sizeof(buf), "Total size: %zu bytes\n", size);
    xpkDebugLog() += buf;
    
    // Print first 32 bytes
    xpkDebugLog() += "First 32 bytes: ";
    for (int i = 0; i < 32; i++) {
        snprintf(buf, sizeof(buf), "%02x ", data[i]);
        xpkDebugLog() += buf;
    }
    xpkDebugLog() += "\n";
    
    size_t offset = 16;
    int blockNum = 0;
    
    while (offset + 6 <= size) {
        // Scan for CK
        while (offset + 1 < size && !(data[offset] == 0x43 && data[offset+1] == 0x4B)) {
            offset++;
        }
        if (offset + 6 > size) break;
        
        size_t ckPos = offset;
        offset += 2;
        uint16_t compSize = readU16(data, offset); offset += 2;
        uint16_t uncompSize = readU16(data, offset); offset += 2;
        
        snprintf(buf, sizeof(buf), "\nBlock %d: CK at %zu, comp=%u, uncomp=%u\n",
                 blockNum, ckPos, compSize, uncompSize);
        xpkDebugLog() += buf;
        
        if (compSize <= 6 || uncompSize == 0) {
            xpkDebugLog() += "Invalid sizes, stopping\n";
            break;
        }
        if (offset + compSize - 6 > size) {
            xpkDebugLog() += "Out of bounds, stopping\n";
            break;
        }
        
        size_t dataSize = compSize - 6;
        
        // Print first 8 bytes of compressed data
        xpkDebugLog() += "Comp data[0-7]: ";
        for (int i = 0; i < 8; i++) {
            snprintf(buf, sizeof(buf), "%02x ", data[offset + i]);
            xpkDebugLog() += buf;
        }
        xpkDebugLog() += "\n";
        
        // Try raw deflate
        uint8_t* outBuf = new uint8_t[uncompSize];
        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        strm.next_in = (Bytef*)(data + offset);
        strm.avail_in = (uInt)dataSize;
        strm.next_out = outBuf;
        strm.avail_out = uncompSize;
        
        int initRet = inflateInit2(&strm, -MAX_WBITS);
        snprintf(buf, sizeof(buf), "initRet=%d\n", initRet);
        xpkDebugLog() += buf;
        
        if (initRet == Z_OK) {
            int ret = inflate(&strm, Z_FINISH);
            uLong totalOut = strm.total_out;
            inflateEnd(&strm);
            snprintf(buf, sizeof(buf), "inflate ret=%d, totalOut=%lu\n", ret, totalOut);
            xpkDebugLog() += buf;
            
            if (ret == Z_STREAM_END && totalOut > 0) {
                output.insert(output.end(), outBuf, outBuf + totalOut);
                xpkDebugLog() += "SUCCESS!\n";
            }
        }
        delete[] outBuf;
        
        // Advance to next block
        offset = ckPos + compSize;
        blockNum++;
        
        if (blockNum > 10) {
            xpkDebugLog() += "Stopping after 10 blocks\n";
            break;
        }
    }
    
    snprintf(buf, sizeof(buf), "\nTotal decompressed: %lu bytes\n", (unsigned long)output.size());
    xpkDebugLog() += buf;
    
    return output;
}

std::vector<XToken> XFileParser::parseTokens(const uint8_t* data, size_t size, int maxTokens) {
    std::vector<XToken> tokens;
    if (size < 16) return tokens;
    size_t offset = 16;
    
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
            case 1: {
                uint32_t len = readU32(data, offset);
                offset += 4;
                if (offset + len > size) { offset = size; break; }
                token.name = std::string((const char*)(data + offset), len);
                offset += len;
                break;
            }
            case 2: {
                uint32_t len = readU32(data, offset);
                offset += 4;
                if (offset + len > size) { offset = size; break; }
                token.name = std::string((const char*)(data + offset), len);
                offset += len;
                break;
            }
            case 3: token.intValue = (int)readU32(data, offset); offset += 4; break;
            case 5: offset += 16; break;
            case 6: {
                uint32_t count = readU32(data, offset);
                offset += 4;
                if (count > 100000) { offset = size; break; }
                for (uint32_t i = 0; i < count && offset + 4 <= size; i++) {
                    token.intList.push_back((int)readU32(data, offset));
                    offset += 4;
                }
                break;
            }
            case 7: {
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
