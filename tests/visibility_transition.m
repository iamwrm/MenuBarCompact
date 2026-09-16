// Exercise the production lifecycle with fake assertions, without loading or
// changing the real menu-bar host. No NSApplication or settings are launched.
#define main MenuBarCompactApplicationMain
#import "../main.m"
#undef main

@interface MBAssessmentModeConfiguration : NSObject
@end
@implementation MBAssessmentModeConfiguration
- (id)initWithAllowedSystemItems:(NSArray *)items allowedBundleIdentifiers:(NSArray *)bundles {(void)items;(void)bundles;return [super init];}
@end
@interface MBAssessmentModeAssertion : NSObject
@property NSUInteger invalidations;
@property(copy) void (^completion)(NSError *);
@end
@implementation MBAssessmentModeAssertion
- (void)activateWithConfiguration:(id)config completionHandler:(void (^)(NSError *))completion {(void)config;self.completion=completion;}
- (void)invalidate {self.invalidations++;}
@end
@interface TestController : MenuBarCompact
@end
@implementation TestController
- (void)updateUI {}
- (void)log:(NSString *)message {(void)message;}
@end
static void Require(BOOL value,const char *message){if(!value){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
static void Drain(void){[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];}
static void Complete(MBAssessmentModeAssertion *assertion,NSError *error){void (^block)(NSError *)=assertion.completion;assertion.completion=nil;block(error);Drain();}
int main(void){@autoreleasepool{
    TestController *controller=[TestController new];controller.ready=YES;controller.discoveryReady=YES;controller.running=@{};
    controller.rules=[@{@"test.one":@1,@"test.two":@1} mutableCopy];
    [controller applyVisibility];MBAssessmentModeAssertion *first=controller.assertion;
    Require(first && controller.activationPending,"Initial assertion activates asynchronously");
    Complete(first,nil);Require(controller.settledAssertion==first,"Successful assertion becomes the retained baseline");
    __block NSInteger ready=0;
    controller.activeItem=@"test.one";controller.visibilityReadyHandler=^(BOOL success){ready=success?1:-1;};
    [controller applyVisibility];MBAssessmentModeAssertion *second=controller.assertion;
    Require(second!=first && first.invalidations==0 && ready==0,"Keep old restriction until replacement acknowledgement; do not open a menu early");
    Complete(second,nil);
    Require(first.invalidations==1 && controller.settledAssertion==second && ready==1,"Successful handoff retires only the old restriction and resumes activation");
    controller.activeItem=nil;[controller applyVisibility];MBAssessmentModeAssertion *superseded=controller.assertion;
    controller.activeItem=@"test.two";[controller applyVisibility];MBAssessmentModeAssertion *latest=controller.assertion;
    Require(second.invalidations==0 && superseded.invalidations==1,"Replacing an in-flight update preserves the last working restriction");
    Complete(superseded,nil);
    Require(controller.assertion==latest && controller.settledAssertion==second,"A stale completion must not retire the working restriction");
    Complete(latest,nil);Require(second.invalidations==1 && controller.settledAssertion==latest,"Only the latest successful update completes the handoff");
    controller.activeItem=nil;ready=0;controller.visibilityReadyHandler=^(BOOL success){ready=success?1:-1;};[controller applyVisibility];
    MBAssessmentModeAssertion *failed=controller.assertion;
    Complete(failed,[NSError errorWithDomain:@"test" code:1 userInfo:nil]);
    Require(!controller.assertion && !controller.settledAssertion && latest.invalidations==1 && failed.invalidations==1 && ready==-1,"Failure releases both restrictions and fails the pending menu request");
    [controller applyVisibility];MBAssessmentModeAssertion *timedOut=controller.assertion;
    ready=0;controller.visibilityReadyHandler=^(BOOL success){ready=success?1:-1;};[controller.activationTimeout fire];Drain();
    Require(!controller.assertion && timedOut.invalidations==1 && ready==-1,"Timeout fails open and resolves the waiting menu request");
    Complete(timedOut,nil);Require(!controller.assertion,"Late acknowledgement cannot restore a timed-out assertion");
    [controller applyVisibility];MBAssessmentModeAssertion *final=controller.assertion;Complete(final,nil);
    [controller releaseRestriction];Require(final.invalidations==1,"Releasing a settled assertion invalidates it exactly once");
    controller.paused=YES;ready=0;controller.visibilityReadyHandler=^(BOOL success){ready=success?1:-1;};[controller applyVisibility];Drain();
    Require(ready==-1,"A paused controller cannot open a pending menu");
    puts("Visibility transition tests passed: handoff, acknowledgement, supersession, failure, timeout, late replies, and release.");
}return 0;}
