#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

static id MBAXValue(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value=NULL;
    if(AXUIElementCopyAttributeValue(element,key,&value)!=kAXErrorSuccess)return nil;
    return CFBridgingRelease(value);
}
static NSArray *MBAXChildren(AXUIElementRef element) {
    id children=MBAXValue(element,kAXChildrenAttribute);
    return [children isKindOfClass:NSArray.class]?children:@[];
}
static void MBAXButtons(AXUIElementRef element, NSMutableArray *result, NSUInteger depth, NSUInteger *budget) {
    if(!*budget || depth>5)return;
    (*budget)--;
    AXUIElementSetMessagingTimeout(element,0.2);
    CFArrayRef actions=NULL;
    AXUIElementCopyActionNames(element,&actions);
    BOOL pressable=actions && (CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXPressAction) || CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXShowMenuAction));
    if(actions)CFRelease(actions);
    // System controls can use host-specific AX roles on macOS 27. The
    // search root is already restricted to menu extras or MenuBarAgent.
    if(pressable){[result addObject:(__bridge id)element];return;}
    for(id child in MBAXChildren(element))MBAXButtons((__bridge AXUIElementRef)child,result,depth+1,budget);
}
static NSArray *MBAXStatusButtons(pid_t pid, BOOL host) {
    if(pid<=0)return @[];
    AXUIElementRef app=AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(app,0.3);
    NSMutableArray *result=[NSMutableArray new];NSUInteger budget=100;
    id extras=MBAXValue(app,kAXExtrasMenuBarAttribute);
    if(extras)MBAXButtons((__bridge AXUIElementRef)extras,result,0,&budget);
    // The macOS 27 host exposes status controls under its dialog, rather than
    // AXExtrasMenuBar. Never traverse arbitrary app windows as a fallback.
    if(host && !result.count)MBAXButtons(app,result,0,&budget);
    CFRelease(app);return result;
}
static NSArray *MBHostButtons(void) {
    NSRunningApplication *host=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.MenuBarAgent"].firstObject;
    return MBAXStatusButtons(host.processIdentifier,YES);
}
static NSString *MBAXIdentity(id element) {
    AXUIElementRef e=(__bridge AXUIElementRef)element;
    NSMutableArray *parts=[NSMutableArray new];
    for(NSString *key in @[@"AXIdentifier",@"AXTitle",@"AXDescription"]){id value=MBAXValue(e,(__bridge CFStringRef)key);if([value isKindOfClass:NSString.class] && [value length])[parts addObject:value];}
    return [parts componentsJoinedByString:@" "];
}
static BOOL MBAXSameElement(id a,id b) {return CFEqual((__bridge CFTypeRef)a,(__bridge CFTypeRef)b);}
static NSArray *MBMenuTargets(NSString *identifier,pid_t pid,NSArray *before) {
    NSArray *owned=MBAXStatusButtons(pid,NO);
    if(owned.count)return owned;
    NSArray *host=MBHostButtons();
    NSString *needle=nil;
    if([identifier isEqual:@"system.battery"])needle=@"com.apple.menuextra.battery";
    if([identifier isEqual:@"system.spotlight"])needle=@"Spotlight";
    if(needle){NSMutableArray *matches=[NSMutableArray new];for(id e in host)if([MBAXIdentity(e) rangeOfString:needle options:NSCaseInsensitiveSearch].location!=NSNotFound)[matches addObject:e];if(matches.count)return matches;}
    // Only this selected item was allowed into the host. An unambiguous new
    // control is a safe fallback for unlabeled Input Method and hosted extras.
    NSMutableArray *added=[NSMutableArray new];
    for(id e in host){BOOL found=NO;for(id prior in before)if(MBAXSameElement(e,prior)){found=YES;break;}if(!found)[added addObject:e];}
    return added.count==1?added:@[];
}
static AXError MBPressMenuTarget(id target) {
    AXUIElementRef element=(__bridge AXUIElementRef)target;
    AXUIElementSetMessagingTimeout(element,1.0);
    CFArrayRef actions=NULL;AXUIElementCopyActionNames(element,&actions);
    BOOL press=actions && CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXPressAction);
    BOOL show=actions && CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXShowMenuAction);
    if(actions)CFRelease(actions);
    // Do not retry a timed-out press: it may already have opened a menu.
    return press?AXUIElementPerformAction(element,kAXPressAction):(show?AXUIElementPerformAction(element,kAXShowMenuAction):kAXErrorActionUnsupported);
}
