#import "GameEngine.h"
#include "AssetManager.h"
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
        [status appendString:@"XPK Loaded Successfully!\n"];
        [status appendString:@"177 files ready in memory."];
    } else {
        [status appendString:@"ERROR: XPK failed!"];
    }
    return status;
}

+ (NSData *)loadTGATextureData {
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (!resourcePath) return nil;
    
    std::ifstream file([resourcePath UTF8String], std::ios::binary);
    if (!file.is_open()) return nil;
    
    // Known TGA offset (64x64, 32 BPP) jo humne pehle dhoonda tha
    uint32_t tgaOffset = 5642606;
    
    file.seekg(tgaOffset, std::ios::beg);
    unsigned char header[18];
    file.read(reinterpret_cast<char*>(header), 18);
    
    uint8_t idLength = header[0];
    uint16_t width = header[12] | (header[13] << 8);
    uint16_t height = header[14] | (header[15] << 8);
    uint8_t bpp = header[16];
    
    uint32_t pixelDataOffset = tgaOffset + 18 + idLength;
    uint32_t pixelDataSize = width * height * (bpp / 8);
    
    file.seekg(pixelDataOffset, std::ios::beg);
    std::vector<uint8_t> pixelData(pixelDataSize);
    file.read(reinterpret_cast<char*>(pixelData.data()), pixelDataSize);
    file.close();
    
    NSLog(@"[GameEngine] TGA Loaded: %dx%d @ %d BPP (%d bytes)", width, height, bpp, pixelDataSize);
    
    // Debug: pehle 16 pixel bytes dikhayein
    NSMutableString *hexDump = [NSMutableString string];
    for (int i = 0; i < 16 && i < pixelData.size(); i++) {
        [hexDump appendFormat:@"%02x ", pixelData[i]];
    }
    NSLog(@"[GameEngine] First 16 pixel bytes: %@", hexDump);
    
    return [NSData dataWithBytes:pixelData.data() length:pixelDataSize];
}

@end
