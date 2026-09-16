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

// Kisi bhi asset ko XPK se load karein
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

@end
