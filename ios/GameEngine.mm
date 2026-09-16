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
    
    // Header check
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"=== .x file at offset %lu ===\n", (unsigned long)offset];
    
    // Print header (16 bytes)
    [output appendString:@"Header: "];
    for (int i = 0; i < 16 && offset + i < xpkData.length; i++) {
        char c = (char)bytes[offset + i];
        if (c >= 32 && c < 127) [output appendFormat:@"%c", c];
        else [output appendString:@"."];
    }
    [output appendString:@"\n\n"];
    
    // Parse tokens
    std::vector<XToken> tokens = XFileParser::parseTokens(bytes + offset, xpkData.length - offset, maxTokens);
    
    [output appendFormat:@"Tokens (%lu):\n", (unsigned long)tokens.size()];
    for (const auto& token : tokens) {
        std::string desc = XFileParser::describeToken(token);
        [output appendFormat:@"%s\n", desc.c_str()];
    }
    
    return output;
}

@end
