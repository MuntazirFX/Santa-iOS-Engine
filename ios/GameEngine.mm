#import "GameEngine.h"
#include "AssetManager.h"
#include "XFileParser.h"
#include <string>
#include <vector>
#include <fstream>

@implementation GameEngine

+ (NSString *)startEngine {
    NSMutableString *status = [NSMutableString string];
    [status appendString:@"Engine Started\n"];
    
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (resourcePath == nil) {
        [status appendString:@"ERROR: xmas.xpk not found!"];
        return status;
    }
    
    std::string xpkPath = [resourcePath UTF8String];
    AssetManager assetMgr;
    if (assetMgr.loadXPK(xpkPath)) {
        [status appendString:@"XPK Loaded!\n"];
    } else {
        [status appendString:@"XPK failed!"];
    }
    return status;
}

+ (NSData *)loadAssetNamed:(NSString *)name {
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!resourcePath) return nil;
    
    std::string xpkPath = [resourcePath UTF8String];
    AssetManager assetMgr;
    if (!assetMgr.loadXPK(xpkPath)) return nil;
    
    std::string assetName = [name UTF8String];
    std::vector<uint8_t> data = assetMgr.getAssetData(assetName);
    
    if (data.empty()) return nil;
    return [NSData dataWithBytes:data.data() length:data.size()];
}

+ (NSString *)parseXFileAtOffset:(NSUInteger)offset maxTokens:(int)maxTokens {
    NSString *xpkPath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    NSData *xpkData = [NSData dataWithContentsOfFile:xpkPath];
    if (!xpkData) return @"No XPK data";
    
    const uint8_t *bytes = (const uint8_t *)xpkData.bytes;
    if (offset >= xpkData.length) return @"Offset out of bounds";
    
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"=== .x file at offset %lu ===\n", (unsigned long)offset];
    
    // Check header
    char header[17] = {0};
    memcpy(header, bytes + offset, 16);
    [output appendFormat:@"Header: %s\n\n", header];
    
    // Decompress MSZip (bzip) data
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    [output appendFormat:@"Decompressed size: %lu bytes\n", (unsigned long)decompressed.size()];
    
    if (decompressed.size() < 16) {
        [output appendString:@"Decompression failed!\n"];
        return output;
    }
    
    // Print first 32 bytes of decompressed data (Hex + ASCII)
    [output appendString:@"\nFirst 32 bytes:\n"];
    for (int i = 0; i < 32 && i < (int)decompressed.size(); i++) {
        [output appendFormat:@"%02x ", decompressed[i]];
        if ((i+1) % 16 == 0) [output appendString:@"\n"];
    }
    [output appendString:@"\nASCII: "];
    for (int i = 0; i < 32 && i < (int)decompressed.size(); i++) {
        char c = (char)decompressed[i];
        if (c >= 32 && c < 127) [output appendFormat:@"%c", c];
        else [output appendString:@"."];
    }
    [output appendString:@"\n\n"];
    
    // Parse tokens
    std::vector<XToken> tokens = XFileParser::parseTokens(decompressed.data(), decompressed.size(), maxTokens);
    [output appendFormat:@"Tokens (%lu):\n", (unsigned long)tokens.size()];
    for (const auto& token : tokens) {
        std::string desc = XFileParser::describeToken(token);
        [output appendFormat:@"%s\n", desc.c_str()];
    }
    
    return output;
}

@end
