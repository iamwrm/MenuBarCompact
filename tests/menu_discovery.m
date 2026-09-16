#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

// Deterministic AX graph: overlapping roots must not produce duplicate controls
// or choose a pressable container instead of its already-visited child.
@interface TestNode : NSObject
@property NSString *role;
@property NSArray<TestNode *> *children;
@property BOOL pressable;
@property NSUInteger attributeReads, actionReads;
@end
@implementation TestNode
@end
static AXError TestCopyAttribute(AXUIElementRef element,CFStringRef key,CFTypeRef *value){
    TestNode *node=(__bridge TestNode *)element;node.attributeReads++;
    id result=CFEqual(key,kAXRoleAttribute)?node.role:(CFEqual(key,kAXChildrenAttribute)?node.children:nil);
    *value=result?CFBridgingRetain(result):NULL;return result?kAXErrorSuccess:kAXErrorNoValue;
}
static AXError TestCopyActions(AXUIElementRef element,CFArrayRef *value){
    TestNode *node=(__bridge TestNode *)element;node.actionReads++;
    *value=(CFArrayRef)CFBridgingRetain(node.pressable?@[(__bridge NSString *)kAXPressAction]:@[]);return kAXErrorSuccess;
}
static AXError TestTimeout(AXUIElementRef element,float timeout){(void)element;(void)timeout;return kAXErrorSuccess;}
#define AXUIElementCopyAttributeValue TestCopyAttribute
#define AXUIElementCopyActionNames TestCopyActions
#define AXUIElementSetMessagingTimeout TestTimeout
#import "../MenuActivation.h"
static TestNode *Node(NSString *role,BOOL pressable,NSArray *children){TestNode *n=[TestNode new];n.role=role;n.pressable=pressable;n.children=children;return n;}
static void Require(BOOL condition,const char *message){if(!condition){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
int main(void){@autoreleasepool{
    TestNode *leaf=Node(@"AXButton",YES,@[]),*parent=Node(@"AXGroup",YES,@[leaf]);
    TestNode *insideMenu=Node(@"AXMenuItem",YES,@[]),*menu=Node(@"AXMenu",NO,@[insideMenu]);
    TestNode *legacy=Node(@"AXMenuItem",YES,@[]),*root=Node(@"AXApplication",NO,@[parent,menu,legacy]);
    NSMutableArray *result=[NSMutableArray new];NSUInteger budget=100;
    CFMutableDictionaryRef visited=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    MBAXButtons((__bridge AXUIElementRef)leaf,result,0,&budget,visited);
    NSUInteger reads=leaf.attributeReads;
    MBAXButtons((__bridge AXUIElementRef)root,result,0,&budget,visited);
    MBAXButtons((__bridge AXUIElementRef)parent,result,0,&budget,visited);
    Require(result.count==2 && result[0]==leaf && result[1]==legacy,"Overlapping roots produce only the unique status controls");
    Require(leaf.attributeReads==reads && leaf.actionReads==1,"A shared leaf is queried once per scan");
    Require(parent.actionReads==0 && root.actionReads==0,"Containers with status children need no action query");
    Require(insideMenu.attributeReads==0,"Do not traverse an open menu's contents");
    Require(budget==95,"Only five unique nodes consume the traversal budget");
    CFRelease(visited);
    visited=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    budget=0;[result removeAllObjects];
    MBAXButtons((__bridge AXUIElementRef)leaf,result,0,&budget,visited);
    Require(result.count==0 && leaf.attributeReads==reads,"An exhausted scan makes no AX requests");
    CFRelease(visited);
    puts("Menu discovery tests passed: overlapping roots, leaf selection, open-menu isolation, and request budget.");
}return 0;}
