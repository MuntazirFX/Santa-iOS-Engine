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
    [output appendFormat:@"=== .x at offset %lu ===\n", (unsigned long)offset];
    
    // 1. Print first 64 bytes as Hex
    [output appendString:@"\nFirst 64 bytes:\n"];
    for (int i = 0; i < 64 && (offset + i) < xpkData.length; i++) {
        [output appendFormat:@"%02x ", bytes[offset + i]];
        if ((i+1) % 16 == 0) [output appendString:@"\n"];
    }
    
    // 2. Print ASCII of first 32 bytes
    [output appendString:@"\nASCII: "];
    for (int i = 0; i < 32 && (offset + i) < xpkData.length; i++) {
        char c = (char)bytes[offset + i];
        if (c >= 32 && c < 127) [output appendFormat:@"%c", c];
        else [output appendString:@"."];
    }
    
    // 3. Scan for CK signature from byte 8 to byte 40
    [output appendString:@"\n\nScanning for 'CK' (0x43 0x4B):\n"];
    int ckOffset = -1;
    for (int i = 8; i < 40; i++) {
        if (offset + i + 5 >= xpkData.length) break;
        if (bytes[offset + i] == 0x43 && bytes[offset + i + 1] == 0x4B) {
            ckOffset = i;
            uint16_t compSize = bytes[offset + i + 2] | (bytes[offset + i + 3] << 8);
            uint16_t uncompSize = bytes[offset + i + 4] | (bytes[offset + i + 5] << 8);
            [output appendFormat:@"Found CK at relative offset: %d\n", i];
            [output appendFormat:@"compSize = %u bytes\n", compSize];
            [output appendFormat:@"uncompSize = %u bytes\n", uncompSize];
            break;
        }
    }
    if (ckOffset == -1) {
        [output appendString:@"NO CK SIGNATURE FOUND (8-40)!\n"];
    }
    
    return output;
}

@end
