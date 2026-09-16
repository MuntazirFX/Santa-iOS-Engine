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
    [output appendFormat:@"=== .x at offset %lu ===\n\n", (unsigned long)offset];
    
    // Decompress MSZip data (with debug log)
    std::vector<uint8_t> decompressed = XFileParser::decompressMSZip(bytes + offset, xpkData.length - offset);
    
    // Show debug log on screen
    std::string debugStr = xpkDebugLog();
    [output appendString:[NSString stringWithUTF8String:debugStr.c_str()]];
    [output appendString:@"\n"];
    
    [output appendFormat:@"\nDecompressed size: %lu bytes\n\n", (unsigned long)decompressed.size()];
    
    if (decompressed.size() < 16) {
        [output appendString:@"Decompression failed!\n"];
        return output;
    }
    
    // Print first 64 bytes
    [output appendString:@"First 64 bytes of result:\n"];
    for (int i = 0; i < 64 && i < (int)decompressed.size(); i++) {
        [output appendFormat:@"%02x ", decompressed[i]];
        if ((i+1) % 16 == 0) [output appendString:@"\n"];
    }
    
    [output appendString:@"\nASCII: "];
    for (int i = 0; i < 64 && i < (int)decompressed.size(); i++) {
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
