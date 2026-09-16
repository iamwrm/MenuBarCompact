#import "RestrictionBridge.h"
#import <dlfcn.h>
@interface NSObject (MenuRestriction)
- (id)initWithAllowedSystemItems:(NSArray *)items allowedBundleIdentifiers:(NSArray *)bundles;
- (void)activateWithConfiguration:(id)config completionHandler:(void (^)(NSError *))completion;
- (void)invalidate;
@end
@implementation MBRestrictionHandle {
    id _configuration, _assertion;
}
static NSError *BridgeError(NSString *message) {
    return [NSError errorWithDomain:@"MenuBarCompact.Restriction" code:1 userInfo:@{NSLocalizedDescriptionKey:message?:@"Private menu-bar API unavailable"}];
}
- (instancetype)initWithSystems:(NSArray<NSNumber *> *)systems bundles:(NSArray<NSString *> *)bundles error:(NSError **)error {
    if(!(self=[super init]))return nil;
    dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",RTLD_NOW);
    Class config=NSClassFromString(@"MBAssessmentModeConfiguration"), assertion=NSClassFromString(@"MBAssessmentModeAssertion");
    if(![config instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)] ||
       ![assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)] || ![assertion instancesRespondToSelector:@selector(invalidate)]){
        if(error)*error=BridgeError(@"Hiding is unavailable on this macOS version");return nil;
    }
    @try {
        _configuration=[[config alloc] initWithAllowedSystemItems:systems allowedBundleIdentifiers:bundles];
        _assertion=[assertion new];
        if(_configuration && _assertion)return self;
        if(error)*error=BridgeError(@"Could not start hiding; all items remain visible");
    } @catch(NSException *exception){if(error)*error=BridgeError(exception.reason);}
    return nil;
}
- (void)activate:(void (^)(NSError *))completion {
    @try {[_assertion activateWithConfiguration:_configuration completionHandler:completion];}
    @catch(NSException *exception){completion(BridgeError(exception.reason));}
}
- (void)invalidate {
    id assertion=_assertion;_assertion=nil;_configuration=nil;
    @try {[assertion invalidate];} @catch(NSException *exception){NSLog(@"Restriction invalidation: %@",exception.reason);}
}
@end
