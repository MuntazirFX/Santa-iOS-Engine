#import "GameEngine.h"
#include "AssetManager.h"
#include <string>
#include <vector>

@implementation GameEngine

+ (void)startEngine {
    NSLog(@"[GameEngine] Starting Santa iOS Engine...");
    
    // App bundle se xmas.xpk ka path dhoondein
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"xmas" ofType:@"xpk"];
    if (resourcePath == nil) {
        NSLog(@"[GameEngine] ERROR: xmas.xpk bundle mein nahi mili!");
        return;
    }
    
    std::string xpkPath = [resourcePath UTF8String];
    NSLog(@"[GameEngine] XPK Path: %s", xpkPath.c_str());
    
    // AssetManager banayein aur XPK load karein
    AssetManager assetMgr;
    if (assetMgr.loadXPK(xpkPath)) {
        NSLog(@"[GameEngine] SUCCESS: XPK loaded!");
        
        // Test: ek file load karein
        std::vector<uint8_t> data = assetMgr.getAssetData("maps\\mouse.tga");
        NSLog(@"[GameEngine] Loaded mouse.tga: %lu bytes", (unsigned long)data.size());
    } else {
        NSLog(@"[GameEngine] FAILED: XPK load nahi hui!");
    }
}

@end
