#import "AppDelegate.h"
#import "GameEngine.h"
#import "MetalView.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    
    MetalView *mv = [[MetalView alloc] initWithFrame:vc.view.bounds];
    mv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:mv];
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 40, vc.view.bounds.size.width, 110)];
    tv.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:10];
    tv.editable = NO;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [vc.view addSubview:tv];
    
    MeshData *mesh = [GameEngine extractSantaWithTransforms:960968];
    
    if (mesh && mesh.vertexCount > 0 && mesh.faceCount > 0) {
        NSString *tex = mesh.textureName ? [mesh.textureName lastPathComponent] : @"(none)";
        tv.text = [NSString stringWithFormat:@"🎅 MESH COLOR TEST\n%d v, %d faces\nTex: %@\n\n🔴 Red = Santa | 🟢 Green = Tree\n🟡 Yellow = House | 🔵 Blue = Misc",
                   mesh.vertexCount, mesh.faceCount, tex];
        [mv setMeshToRender:mesh];
    } else {
        tv.text = @"Santa extraction failed!";
    }
    
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
