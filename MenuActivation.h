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
static BOOL MBAXButtons(AXUIElementRef element, NSMutableArray *result, NSUInteger depth, NSUInteger *budget, CFMutableDictionaryRef visited) {
    const void *known=NULL;
    if(CFDictionaryGetValueIfPresent(visited,element,&known))return [(__bridge NSNumber *)known boolValue];
    if(!*budget || depth>5)return NO;
    (*budget)--;CFDictionarySetValue(visited,element,kCFBooleanFalse);
    AXUIElementSetMessagingTimeout(element,0.2);
    NSString *role=MBAXValue(element,kAXRoleAttribute);
    // Stop at menus, but allow legacy status controls with AXMenuItem roles.
    if([role isEqual:(__bridge NSString *)kAXMenuRole])return NO;
    BOOL childControl=NO;
    for(id child in MBAXChildren(element))if(MBAXButtons((__bridge AXUIElementRef)child,result,depth+1,budget,visited))childControl=YES;
    if(childControl){CFDictionarySetValue(visited,element,kCFBooleanTrue);return YES;}
    // Only query actions for leaves; host containers can advertise a press too.
    CFArrayRef actions=NULL;AXUIElementCopyActionNames(element,&actions);
    BOOL pressable=actions && (CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXPressAction) || CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXShowMenuAction));
    if(actions)CFRelease(actions);
    if(pressable){[result addObject:(__bridge id)element];CFDictionarySetValue(visited,element,kCFBooleanTrue);}
    return pressable;
}
static NSArray *MBAXStatusButtons(pid_t pid, BOOL host) {
    if(pid<=0)return @[];
    AXUIElementRef app=AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(app,0.3);
    NSMutableArray *result=[NSMutableArray new];NSUInteger budget=100;
    CFMutableDictionaryRef visited=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    id extras=MBAXValue(app,kAXExtrasMenuBarAttribute);
    if(extras)MBAXButtons((__bridge AXUIElementRef)extras,result,0,&budget,visited);
    // Both roots can expose the same macOS 27 host controls. Cache traversal
    // results for this scan so overlapping subtrees cost no extra AX requests.
    if(host){
        MBAXButtons(app,result,0,&budget,visited);
        id windows=MBAXValue(app,kAXWindowsAttribute);
        if([windows isKindOfClass:NSArray.class])for(id window in windows)MBAXButtons((__bridge AXUIElementRef)window,result,0,&budget,visited);
    }
    CFRelease(visited);CFRelease(app);return result;
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
static NSArray *MBMenuTargets(pid_t pid,NSArray *before,NSDictionary *metadata) {
    NSArray *owned=MBAXStatusButtons(pid,NO);
    if(owned.count && ![metadata[@"preferHost"] boolValue])return owned;
    NSArray *host=MBHostButtons();
    // iStat's helper proxy rejects activation; use its matching native host
    // control when identities agree, or the existing unambiguous reveal delta.
    if([metadata[@"preferHost"] boolValue]){
        NSMutableArray *hosted=[NSMutableArray new];NSMutableSet *identities=[NSMutableSet new];
        for(id proxy in owned){NSString *identity=MBAXIdentity(proxy);if(identity.length)[identities addObject:identity];}
        for(id element in host){NSString *identity=MBAXIdentity(element);if(!identity.length)continue;
            if([identities containsObject:identity])[hosted addObject:element];
        }
        if(hosted.count)return hosted;
    }
    NSMutableArray *matches=[NSMutableArray new];
    for(id element in host){
        NSString *ax=[metadata[@"axIdentifiers"] count]?MBAXValue((__bridge AXUIElementRef)element,CFSTR("AXIdentifier")):nil;BOOL match=NO;
        for(NSString *expected in metadata[@"axIdentifiers"])if([ax isKindOfClass:NSString.class] && [ax caseInsensitiveCompare:expected]==NSOrderedSame){match=YES;break;}
        NSString *name=metadata[@"axName"];
        if(!match && name.length && [MBAXIdentity(element) rangeOfString:name options:NSCaseInsensitiveSearch].location!=NSNotFound)match=YES;
        if(match)[matches addObject:element];
    }
    if(matches.count)return matches;
    // Only this selected item was allowed into the host. An unambiguous new
    // control is a safe fallback for unlabeled Input Method and hosted extras.
    NSMutableArray *added=[NSMutableArray new];
    for(id e in host){BOOL found=NO;for(id prior in before)if(MBAXSameElement(e,prior)){found=YES;break;}if(!found)[added addObject:e];}
    return added.count==1?added:@[];
}
// Geometry is checked before posting a fallback mouse event. A stale or
// malformed AX element must never cause a click in an application window.
static BOOL MBMenuClickPoint(CGPoint origin,CGSize dimensions,NSArray<NSValue *> *displayFrames,CGPoint *point) {
    if(!isfinite(origin.x) || !isfinite(origin.y) || !isfinite(dimensions.width) || !isfinite(dimensions.height))return NO;
    if(dimensions.width<=0 || dimensions.width>400 || dimensions.height<=0 || dimensions.height>64)return NO;
    CGRect item=CGRectMake(origin.x,origin.y,dimensions.width,dimensions.height);
    for(NSValue *value in displayFrames){CGRect bar=NSRectToCGRect(value.rectValue);bar.size.height=64;
        if(CGRectContainsRect(bar,item)){*point=CGPointMake(CGRectGetMidX(item),CGRectGetMidY(item));return YES;}
    }
    return NO;
}
static NSValue *MBMenuTargetScreenRect(id target) {
    AXUIElementRef element=(__bridge AXUIElementRef)target;
    id position=MBAXValue(element,kAXPositionAttribute),size=MBAXValue(element,kAXSizeAttribute);
    if(!position || !size || CFGetTypeID((__bridge CFTypeRef)position)!=AXValueGetTypeID() || CFGetTypeID((__bridge CFTypeRef)size)!=AXValueGetTypeID())return nil;
    CGPoint origin;CGSize dimensions;
    if(!AXValueGetValue((__bridge AXValueRef)position,kAXValueCGPointType,&origin) || !AXValueGetValue((__bridge AXValueRef)size,kAXValueCGSizeType,&dimensions))return nil;
    CGDirectDisplayID displays[32];uint32_t count=0;NSMutableArray *frames=[NSMutableArray new];
    if(CGGetActiveDisplayList(32,displays,&count)!=kCGErrorSuccess)return nil;
    for(uint32_t i=0;i<count;i++)[frames addObject:[NSValue valueWithRect:NSRectFromCGRect(CGDisplayBounds(displays[i]))]];
    CGPoint point;if(!MBMenuClickPoint(origin,dimensions,frames,&point))return nil;
    return [NSValue valueWithRect:NSMakeRect(origin.x,origin.y,dimensions.width,dimensions.height)];
}
static AXError MBClickMenuTarget(AXUIElementRef element) {
    NSValue *rect=MBMenuTargetScreenRect((__bridge id)element);if(!rect)return kAXErrorActionUnsupported;
    CGPoint point=CGPointMake(NSMidX(rect.rectValue),NSMidY(rect.rectValue));
    CGEventRef current=CGEventCreate(NULL);CGPoint previous=current?CGEventGetLocation(current):point;if(current)CFRelease(current);
    CGEventRef down=CGEventCreateMouseEvent(NULL,kCGEventLeftMouseDown,point,kCGMouseButtonLeft);
    CGEventRef up=CGEventCreateMouseEvent(NULL,kCGEventLeftMouseUp,point,kCGMouseButtonLeft);
    if(!down || !up){if(down)CFRelease(down);if(up)CFRelease(up);return kAXErrorFailure;}
    CGEventSetIntegerValueField(down,kCGMouseEventClickState,1);CGEventSetIntegerValueField(up,kCGMouseEventClickState,1);
    CGEventPost(kCGHIDEventTap,down);CGEventPost(kCGHIDEventTap,up);CFRelease(down);CFRelease(up);
    CGWarpMouseCursorPosition(previous);return kAXErrorSuccess;
}
static AXError MBPressMenuTarget(id target) {
    AXUIElementRef element=(__bridge AXUIElementRef)target;
    AXUIElementSetMessagingTimeout(element,1.0);
    CFArrayRef actions=NULL;AXUIElementCopyActionNames(element,&actions);
    BOOL press=actions && CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXPressAction);
    BOOL show=actions && CFArrayContainsValue(actions,CFRangeMake(0,CFArrayGetCount(actions)),kAXShowMenuAction);
    if(actions)CFRelease(actions);
    // Do not retry a timed-out press: it may already have opened a menu.
    AXError result=press?AXUIElementPerformAction(element,kAXPressAction):(show?AXUIElementPerformAction(element,kAXShowMenuAction):kAXErrorActionUnsupported);
    // Some macOS 27 host buttons advertise AXPress but reject it. Only a
    // definitive unsupported response permits this single coordinate click.
    if(result==kAXErrorActionUnsupported || result==kAXErrorNotImplemented)return MBClickMenuTarget(element);
    return result;
}
