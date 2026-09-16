#import "SystemCatalog.h"
#import <Cocoa/Cocoa.h>
@interface NSObject (MBRuntimeSystemItems)
+ (NSArray *)items;
@end
static NSDictionary *MBDiscoverSystemItems(BOOL force) {
    static NSDictionary *cachedCatalog;static NSArray *cachedLoaded;
    NSArray *loaded=[NSUserDefaults.standardUserDefaults persistentDomainForName:@"com.apple.systemuiserver"][@"menuExtras"]?:@[];
    if(!force && cachedCatalog && [loaded isEqual:cachedLoaded])return cachedCatalog;
    Class reader=NSClassFromString(@"MBRuntimeSystemItems");
    NSArray *runtime=[reader respondsToSelector:@selector(items)]?[reader items]:@[];
    // Failing open is preferable to hiding unknown new OS categories by omission.
    if(!runtime.count)return nil;
    NSMutableArray *plugins=[NSMutableArray new];
    NSURL *directory=[NSURL fileURLWithPath:@"/System/Library/CoreServices/Menu Extras" isDirectory:YES];
    for(NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]){
        if(![url.pathExtension isEqual:@"menu"])continue;
        NSBundle *bundle=[NSBundle bundleWithURL:url];
        NSString *identifier=bundle.bundleIdentifier;
        if(![identifier hasPrefix:@"com.apple.menuextra."])continue;
        NSString *name=[bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if(!name.length)name=MBReadableItemName(url.lastPathComponent.stringByDeletingPathExtension);
        [plugins addObject:@{@"bundle":identifier,@"name":name,@"path":url.path,@"host":([loaded containsObject:url.path] && loaded.count==1)?@"com.apple.systemuiserver":@""}];
    }
    NSMutableArray *specials=[NSMutableArray new];
    // Spotlight is a hosted app, not an enum category or .menu plug-in. Keep
    // the existing preference key, and add it only when its OS bundle exists.
    NSBundle *spotlight=[NSBundle bundleWithPath:@"/System/Library/CoreServices/Spotlight.app"];
    if(spotlight.bundleIdentifier){[specials addObject:@{@"key":@"system.spotlight",@"metadata":@{@"name":@"Spotlight",@"symbol":@"magnifyingglass",@"systems":@[],@"bundles":@[spotlight.bundleIdentifier,@"com.apple.campo"],@"axIdentifiers":@[],@"axName":@"Spotlight",@"protected":@NO,@"source":@"Hosted system app"}}];}
    cachedLoaded=[loaded copy];cachedCatalog=MBBuildSystemCatalog(runtime,plugins,specials);return cachedCatalog;
}
