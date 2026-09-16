#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dlfcn.h>
#import "VisibilityPolicy.h"
#import "MenuActivation.h"
#import "SystemDiscovery.h"
#import "VisibilityEditor.h"
#import "MaintenancePolicy.h"

// Narrow macOS 27 runtime interface, reconstructed in our diagnostic project.
// Runtime lookup lets the app fail open if a future OS removes this API.
@interface NSObject (MenuRestriction)
- (id)initWithAllowedSystemItems:(NSArray *)items allowedBundleIdentifiers:(NSArray *)bundles;
- (void)activateWithConfiguration:(id)config completionHandler:(void (^)(NSError *))completion;
- (void)invalidate;
@end

typedef NS_ENUM(NSInteger, VisibilityMode) { Collapsed, Revealed, Everything };
static NSString *const OwnID = @"io.github.iamwrm.MenuBarCompact";
static NSString *const ThawID = @"com.stonerl.Thaw";
static NSString *const IStatID = @"com.bjango.istatmenus.status";

@interface MenuBarCompact : NSObject <NSApplicationDelegate, MBVisibilityEditorDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSPopoverDelegate, NSWindowDelegate>
@property NSStatusItem *statusItem;
@property NSWindow *window;
@property NSTextField *summaryLabel, *compatibilityLabel, *loginLabel;
@property NSButton *loginButton, *autoHideButton, *takeOverButton, *toggleButton, *allAppsButton;
@property NSSearchField *search;
@property NSScrollView *visibilityEditorScroll;
@property NSArray<MBVisibilityLane *> *visibilityLanes;
@property BOOL userResizedSettings, layingOutSettings;
@property NSArray<NSArray<NSTextField *> *> *visibilityLabels;
@property NSArray<NSTextField *> *visibilityCounts;
@property NSMutableDictionary<NSString *,NSNumber *> *rules;
@property NSMutableDictionary<NSString *,NSString *> *names;
@property NSArray<NSDictionary *> *rows;
@property NSDictionary<NSString *,NSRunningApplication *> *running;
@property id assertion, settledAssertion;
@property(copy) void (^visibilityReadyHandler)(BOOL);
@property NSArray *lastAllowlist, *lastSystemAllowlist;
@property NSTimer *rehideTimer, *maintenance, *activationTimeout;
@property NSArray *verifiedCompatibilityFingerprint;
@property NSTimeInterval lastCompatibilityAudit, lastCompatibilityAttempt;
@property NSCache<NSString *,NSImage *> *iconCache;
@property NSMutableDictionary<NSNumber *,NSArray *> *renderedLaneRows;
@property NSImage *closedStatusImage, *openStatusImage;
@property NSTask *compatibilityTask;
@property NSUInteger generation, refreshGeneration;
@property VisibilityMode mode;
@property BOOL ready, menuOpen, paused, activationPending, discoveryReady;
@property NSString *stateMessage, *compatibilityMessage;
@property NSURL *logURL;
@property NSPopover *overflow;
@property BOOL includeAlwaysHidden;
@property NSString *activeItem;
@property NSTimer *interactionTimer;
@property NSUInteger interactionGeneration;
@property id outsideMonitor;

@end

@implementation MenuBarCompact
- (void)log:(NSString *)message {
    NSString *line=[NSString stringWithFormat:@"%@ %@\n",NSDate.date,message];
    NSLog(@"%@",message);
    NSFileHandle *file=[NSFileHandle fileHandleForWritingToURL:self.logURL error:nil];
    if(file){[file seekToEndOfFile];[file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[file closeFile];}
}
- (BOOL)protectedID:(NSString *)identifier {
    if(MBSystemItems()[identifier])return [MBSystemItems()[identifier][@"protected"] boolValue];
    return MBProtectedBundle(identifier,OwnID);
}
- (void)saveRules {
    [NSUserDefaults.standardUserDefaults setObject:self.rules forKey:@"VisibilityRules"];
    [NSUserDefaults.standardUserDefaults setObject:self.names forKey:@"AppNames"];
}
- (void)importThawOnce {
    NSDictionary *thaw=[NSUserDefaults.standardUserDefaults persistentDomainForName:ThawID];
    NSDictionary *groups=thaw[@"MenuBarItemManager.savedSectionOrder"];
    // Import only the current saved groups, not Thaw's accumulated historical pins.
    for(NSString *group in @[@"alwaysHidden",@"hidden",@"visible"]){
        for(NSString *item in groups[group]){
            NSString *identifier=[item componentsSeparatedByString:@":"].firstObject;
            if(identifier.length && ![self protectedID:identifier])self.rules[identifier]=[group isEqual:@"hidden"]?@1:([group isEqual:@"alwaysHidden"]?@2:@0);
        }
    }
    [self saveRules];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if([NSRunningApplication runningApplicationsWithBundleIdentifier:OwnID].count>1){[NSApp terminate:nil];return;}
    NSURL *support=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"MenuBarCompact"];
    [NSFileManager.defaultManager createDirectoryAtURL:support withIntermediateDirectories:YES attributes:nil error:nil];
    self.logURL=[support URLByAppendingPathComponent:@"events.log"];
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:self.logURL.path error:nil];
    if([attrs fileSize]>512*1024)[NSFileManager.defaultManager moveItemAtURL:self.logURL toURL:[support URLByAppendingPathComponent:[NSString stringWithFormat:@"events-%@.log",NSUUID.UUID.UUIDString]] error:nil];
    if(![NSFileManager.defaultManager fileExistsAtPath:self.logURL.path])[NSData.data writeToURL:self.logURL atomically:YES];
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    // Preserve the user's settings from the original prototype after the rename.
    if(![prefs objectForKey:@"VisibilityRules"]){
        NSDictionary *legacy=[prefs persistentDomainForName:@"local.codex.MenuShelter"];
        for(NSString *key in @[@"VisibilityRules",@"AppNames",@"AutoRehide"]){
            if(legacy[key])[prefs setObject:legacy[key] forKey:key];
        }
    }
    [prefs registerDefaults:@{@"AutoRehide":@YES}];
    [self discoverSystemItems:nil];
    BOOL first=[prefs objectForKey:@"VisibilityRules"]==nil;
    self.rules=[[prefs dictionaryForKey:@"VisibilityRules"] mutableCopy]?:[NSMutableDictionary new];
    self.names=[[prefs dictionaryForKey:@"AppNames"] mutableCopy]?:[NSMutableDictionary new];
    if(first)[self importThawOnce];
    for(NSString *identifier in self.rules.allKeys)if([self protectedID:identifier])[self.rules removeObjectForKey:identifier];
    self.names[IStatID]=@"iStat Menus";
    self.mode=Collapsed;
    self.stateMessage=@"Starting…";self.compatibilityMessage=@"Checking iStat compatibility…";
    dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",RTLD_NOW);
    if(![prefs objectForKey:@"NSStatusItem Preferred Position MenuBarCompact.Main"])[prefs setInteger:0 forKey:@"NSStatusItem Preferred Position MenuBarCompact.Main"];
    self.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.autosaveName=@"MenuBarCompact.Main";
    self.statusItem.button.target=self;self.statusItem.button.action=@selector(statusClick:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp|NSEventMaskRightMouseUp];
    self.statusItem.button.accessibilityLabel=@"MenuBarCompact";
    NSMenu *main=[NSMenu new];NSMenuItem *root=[NSMenuItem new];[main addItem:root];
    NSMenu *app=[NSMenu new];[app addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    [app addItemWithTitle:@"Quit MenuBarCompact" action:@selector(terminate:) keyEquivalent:@"q"];root.submenu=app;NSApp.mainMenu=main;
    NSNotificationCenter *workspace=NSWorkspace.sharedWorkspace.notificationCenter;
    for(NSString *event in @[NSWorkspaceDidLaunchApplicationNotification,NSWorkspaceDidTerminateApplicationNotification,NSWorkspaceDidWakeNotification,NSWorkspaceSessionDidBecomeActiveNotification]){
        [workspace addObserver:self selector:@selector(workspaceChanged:) name:event object:nil];
    }
    [workspace addObserver:self selector:@selector(suspend:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(suspend:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [self refreshApps];[self checkCompatibility:nil];
    // Workspace notifications handle normal changes. One coalescible sweep
    // catches helper events missed by the macOS beta without frequent polling.
    self.maintenance=[NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(maintain:) userInfo:nil repeats:YES];
    self.maintenance.tolerance=10;
    if([NSProcessInfo.processInfo.arguments containsObject:@"--enable-login"])[self setLoginEnabled:YES];
    if(first || [NSProcessInfo.processInfo.arguments containsObject:@"--settings"])[self showSettings:nil];
    [self log:@"START MenuBarCompact 0.6.7"];
}
- (void)workspaceChanged:(NSNotification *)note {
    if([note.name isEqual:NSWorkspaceDidWakeNotification] || [note.name isEqual:NSWorkspaceSessionDidBecomeActiveNotification]){
        self.paused=NO;self.maintenance.fireDate=[NSDate dateWithTimeIntervalSinceNow:60];[self releaseRestriction];
    }
    NSUInteger revision=++self.refreshGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(revision!=self.refreshGeneration)return;
        if(self.paused)return;
        [self refreshApps];[self checkCompatibility:nil];[self applyVisibility];
    });
}
- (void)suspend:(NSNotification *)note {self.paused=YES;self.maintenance.fireDate=NSDate.distantFuture;[self.overflow performClose:nil];[self finishInteraction];[self releaseRestriction];}
- (void)maintain:(id)sender {if(self.paused)return;[self pollApps:nil];[self discoverSystemItems:nil];[self checkCompatibility:nil];}
- (void)pollApps:(id)sender {
    NSMutableDictionary *latest=[NSMutableDictionary new], *previous=[NSMutableDictionary new];
    for(NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications)if(app.bundleIdentifier.length && !app.terminated)latest[app.bundleIdentifier]=@(app.processIdentifier);
    for(NSString *identifier in self.running)previous[identifier]=@(self.running[identifier].processIdentifier);
    if(![latest isEqual:previous]){[self refreshApps];[self applyVisibility];}
}
- (void)refreshApps {
    NSMutableDictionary *running=[NSMutableDictionary new];
    for(NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications){
        if(app.bundleIdentifier.length && !app.terminated){running[app.bundleIdentifier]=app;if(app.localizedName.length)self.names[app.bundleIdentifier]=app.localizedName;}
    }
    self.running=running;[self rebuildRows];
}
- (void)discoverSystemItems:(id)sender {
    BOOL wasReady=self.discoveryReady;
    NSDictionary *catalog=MBDiscoverSystemItems(sender!=nil);self.discoveryReady=catalog.count>0;
    if(!catalog){[self log:@"DISCOVERY unavailable — hiding paused"];[self applyVisibility];return;}
    if(wasReady==self.discoveryReady && [catalog isEqual:MBSystemItems()] && !sender)return;
    if(![catalog isEqual:MBSystemItems()]){
        MBSetSystemItems(catalog);[self.iconCache removeAllObjects];
        [self log:[NSString stringWithFormat:@"DISCOVERY %lu system items (%lu runtime categories)",(unsigned long)catalog.count,(unsigned long)MBSystemCategoryIDs().count]];
    }
    if(self.rules)[self rebuildRows];if(self.ready)[self applyVisibility];
}
- (void)rebuildRows {
    if(!self.window.visible)return;
    NSMutableSet *ids=[NSMutableSet setWithArray:self.rules.allKeys];
    [ids addObject:IStatID];
    [ids addObjectsFromArray:MBSystemItems().allKeys];
    for(NSRunningApplication *app in self.running.allValues){
        if(self.allAppsButton.state==NSControlStateValueOn && ![self protectedID:app.bundleIdentifier] && (app.activationPolicy!=NSApplicationActivationPolicyProhibited || self.rules[app.bundleIdentifier]))[ids addObject:app.bundleIdentifier];
    }
    NSString *query=self.search.stringValue?:@"";
    NSMutableArray *rows=[NSMutableArray new];
    for(NSString *identifier in ids){
        NSString *name=MBSystemItems()[identifier][@"name"]?:self.names[identifier];
        if(!name){NSURL *url=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];name=url?[[NSFileManager.defaultManager displayNameAtPath:url.path] stringByDeletingPathExtension]:identifier;self.names[identifier]=name;}
        if([identifier isEqual:IStatID])name=@"iStat Menus";
        if(query.length && [name rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound && [identifier rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound)continue;
        [rows addObject:@{@"id":identifier,@"name":name?:identifier,@"running":@(self.running[identifier]!=nil),@"pid":@(self.running[identifier].processIdentifier),@"rule":self.rules[identifier]?:@0,@"system":MBSystemItems()[identifier]?:@{}}];
    }
    NSArray *sorted=[rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
    self.rows=sorted;
    [self renderVisibilityLanes];
}
- (void)visibilityDidFinish:(BOOL)success {
    void (^handler)(BOOL)=self.visibilityReadyHandler;self.visibilityReadyHandler=nil;
    if(handler)dispatch_async(dispatch_get_main_queue(),^{handler(success);});
}
- (void)releaseRestriction {
    self.generation++;self.activationPending=NO;[self.activationTimeout invalidate];self.activationTimeout=nil;
    id current=self.assertion;self.assertion=nil;
    if(current){[current invalidate];[self log:@"RELEASE visibility restriction"];}
    if(self.settledAssertion!=current)[self.settledAssertion invalidate];self.settledAssertion=nil;
    self.lastAllowlist=nil;self.lastSystemAllowlist=nil;
}
- (void)applyVisibility {
    if(self.paused){[self visibilityDidFinish:NO];return;}
    if(!self.discoveryReady){[self releaseRestriction];self.stateMessage=@"System item discovery unavailable; hiding is paused";[self updateUI];[self visibilityDidFinish:NO];return;}
    if(self.running[ThawID]){[self releaseRestriction];self.stateMessage=@"Paused while Thaw is running";[self updateUI];[self visibilityDidFinish:NO];return;}
    if(!self.ready){[self releaseRestriction];self.stateMessage=@"Waiting for iStat compatibility";[self updateUI];[self visibilityDidFinish:NO];return;}
    NSDictionary *effectiveRules=MBInteractionRules(self.rules,self.activeItem);
    NSDictionary *plan=MBVisibilityPlan(self.running.allKeys,effectiveRules,OwnID,Collapsed);
    NSUInteger excluded=[plan[@"excluded"] unsignedIntegerValue];
    NSArray *systems=plan[@"systems"];
    if(self.mode==Everything || excluded==0){[self releaseRestriction];self.stateMessage=self.mode==Everything?@"Showing all items":@"All configured items are visible";[self updateUI];[self visibilityDidFinish:YES];return;}
    NSArray *bundles=plan[@"bundles"];
    if(self.assertion && [bundles isEqual:self.lastAllowlist] && [systems isEqual:self.lastSystemAllowlist]){
        if(!self.activationPending)self.stateMessage=self.mode==Collapsed?@"Hidden items are tucked away":@"Showing hidden items";
        [self updateUI];if(!self.activationPending)[self visibilityDidFinish:YES];return;
    }
    // Keep the last successful restriction until its replacement is active.
    // Releasing first briefly exposes every icon and forces two full layouts.
    self.generation++;[self.activationTimeout invalidate];self.activationTimeout=nil;
    if(self.assertion!=self.settledAssertion)[self.assertion invalidate];
    self.assertion=nil;self.activationPending=NO;
    Class configuration=NSClassFromString(@"MBAssessmentModeConfiguration"), assertion=NSClassFromString(@"MBAssessmentModeAssertion");
    if(!configuration || !assertion || ![configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)] || ![assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)] || ![assertion instancesRespondToSelector:@selector(invalidate)]){
        [self releaseRestriction];self.stateMessage=@"Hiding is unavailable on this macOS version";[self updateUI];[self visibilityDidFinish:NO];return;
    }
    @try {
        id config=[[configuration alloc] initWithAllowedSystemItems:systems allowedBundleIdentifiers:bundles];
        self.assertion=[assertion new];
        if(!config || !self.assertion){[self releaseRestriction];self.stateMessage=@"Could not start hiding; all items remain visible";[self updateUI];[self visibilityDidFinish:NO];return;}
        self.lastAllowlist=bundles;self.lastSystemAllowlist=systems;self.activationPending=YES;
        NSUInteger revision=self.generation;
        self.stateMessage=@"Updating menu bar…";
        [self.assertion activateWithConfiguration:config completionHandler:^(NSError *error){
            dispatch_async(dispatch_get_main_queue(),^{
                if(revision!=self.generation)return;
                self.activationPending=NO;[self.activationTimeout invalidate];self.activationTimeout=nil;
                if(error){[self releaseRestriction];self.stateMessage=@"Could not hide apps; all items remain visible";[self log:[NSString stringWithFormat:@"ACTIVATE failed: %@",error]];}
                else {if(self.settledAssertion!=self.assertion)[self.settledAssertion invalidate];self.settledAssertion=self.assertion;self.stateMessage=self.mode==Collapsed?@"Hidden items are tucked away":@"Showing hidden items";[self log:[NSString stringWithFormat:@"ACTIVATE success mode=%ld excluded=%lu iStat=%@",(long)self.mode,(unsigned long)excluded,[bundles containsObject:IStatID]?@"allowed":@"hidden"]];}
                [self updateUI];[self visibilityDidFinish:error==nil];
            });
        }];
        // Do not retain an uncertain assertion indefinitely if the private host stops replying.
        self.activationTimeout=[NSTimer scheduledTimerWithTimeInterval:5 repeats:NO block:^(NSTimer *timer){
            if(revision==self.generation && self.activationPending){[self releaseRestriction];self.stateMessage=@"Menu bar did not respond; hiding is paused";[self updateUI];[self visibilityDidFinish:NO];}
        }];
    } @catch(NSException *exception){[self releaseRestriction];self.stateMessage=@"Hiding is unavailable; all items remain visible";[self log:exception.reason];[self visibilityDidFinish:NO];}
    [self updateUI];
}
- (void)finishInteraction {
    self.interactionGeneration++;self.visibilityReadyHandler=nil;
    [self.interactionTimer invalidate];self.interactionTimer=nil;
    if(self.outsideMonitor){[NSEvent removeMonitor:self.outsideMonitor];self.outsideMonitor=nil;}
    if(self.activeItem){self.activeItem=nil;[self applyVisibility];}
}
- (void)schedulePanelClose {
    [self.rehideTimer invalidate];self.rehideTimer=nil;
    if(self.overflow.shown && [NSUserDefaults.standardUserDefaults boolForKey:@"AutoRehide"]){
        self.rehideTimer=[NSTimer timerWithTimeInterval:15 target:self selector:@selector(hide:) userInfo:nil repeats:NO];
        [NSRunLoop.mainRunLoop addTimer:self.rehideTimer forMode:NSRunLoopCommonModes];
    }
}
- (void)toggle:(id)sender {
    if(self.overflow.shown){[self hide:nil];return;}
    [self openOverflowIncludingAlwaysHidden:NO];
}
- (void)showAll:(id)sender {[self openOverflowIncludingAlwaysHidden:YES];}
- (void)hide:(id)sender {[self.overflow performClose:nil];[self.rehideTimer invalidate];self.rehideTimer=nil;[self finishInteraction];[self updateUI];}
- (void)popoverDidClose:(NSNotification *)note {[self.rehideTimer invalidate];self.rehideTimer=nil;[self updateUI];}
- (void)includeAlways:(NSButton *)sender {[self openOverflowIncludingAlwaysHidden:sender.state==NSControlStateValueOn];}
- (void)requestMenuAccess:(id)sender {
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (NSImage *)rowIconForIdentifier:(NSString *)identifier name:(NSString *)name {
    if(!self.iconCache){self.iconCache=[NSCache new];self.iconCache.countLimit=128;}
    NSString *key=[NSString stringWithFormat:@"%@:%d",identifier,self.running[identifier].processIdentifier];
    NSImage *image=[self.iconCache objectForKey:key];
    if(!image){image=[self loadRowIconForIdentifier:identifier name:name];if(image)[self.iconCache setObject:image forKey:key];}
    return image;
}
- (NSImage *)loadRowIconForIdentifier:(NSString *)identifier name:(NSString *)name {
    NSDictionary *system=MBSystemItems()[identifier];
    if(system){
        NSBundle *plugin=[system[@"bundlePath"] length]?[NSBundle bundleWithPath:system[@"bundlePath"]]:nil;
        for(NSString *resource in @[@"MenuBarIcon",@"menu",@"StatusBarIcon"]){NSImage *image=[plugin imageForResource:resource];if(image){image=[image copy];image.template=YES;return image;}}
        return [NSImage imageWithSystemSymbolName:system[@"symbol"] accessibilityDescription:name]?:[NSImage imageWithSystemSymbolName:@"menubar.rectangle" accessibilityDescription:name];
    }
    // Read artwork from the installed app without loading its executable.
    // These are representative glyphs, not live status snapshots.
    NSURL *bundleURL=self.running[identifier].bundleURL;
    NSBundle *bundle=bundleURL?[NSBundle bundleWithURL:bundleURL]:nil;
    NSMutableArray *candidates=[@[@"MenuBarIcon",@"StatusBarIcon",@"StatusItemIcon",@"TrayIcon"] mutableCopy];
    NSDictionary *known=@{@"org.pqrs.ShowyEdge":@"menu",@"com.openai.codex":@"Icon/Logo",@"com.box.desktop.ui":@"BoxLogo"};
    if(known[identifier])[candidates insertObject:known[identifier] atIndex:0];
    for(NSString *resource in candidates){
        NSImage *image=[bundle imageForResource:resource];
        if(image){image=[image copy];image.template=YES;return image;}
    }
    return self.running[identifier].icon?:[NSImage imageWithSystemSymbolName:@"app" accessibilityDescription:name];
}
- (void)openOverflowIncludingAlwaysHidden:(BOOL)all {
    [self refreshApps];[self finishInteraction];
    self.mode=Collapsed;[self applyVisibility];self.includeAlwaysHidden=all;
    NSMutableArray *items=[NSMutableArray new];
    for(NSString *identifier in MBPanelItems(self.running.allKeys,self.rules,OwnID,all)){
        NSDictionary *system=MBSystemItems()[identifier];
        NSString *name=system[@"name"]?:self.names[identifier]?:identifier;
        NSImage *icon=[self rowIconForIdentifier:identifier name:name];
        icon=[(icon?:[NSImage imageWithSystemSymbolName:@"app" accessibilityDescription:name]) copy];icon.size=NSMakeSize(32,32);
        [items addObject:@{@"id":identifier,@"name":name,@"icon":icon}];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
    // One icon-height strip. Horizontal scrolling keeps it a single row on
    // narrow displays, with no app tiles, headings, or persistent labels.
    CGFloat available=(self.statusItem.button.window.screen?:NSScreen.mainScreen).visibleFrame.size.width-40;
    CGFloat contentWidth=MAX(1,items.count)*32, width=MIN(available,contentWidth+16),height=32;
    NSViewController *controller=[NSViewController new];controller.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,width,height)];
    NSScrollView *strip=[[NSScrollView alloc] initWithFrame:NSMakeRect(8,0,width-16,height)];
    strip.drawsBackground=NO;strip.hasHorizontalScroller=YES;strip.autohidesScrollers=YES;strip.scrollerStyle=NSScrollerStyleOverlay;
    NSView *row=[[NSView alloc] initWithFrame:NSMakeRect(0,0,contentWidth,height)];strip.documentView=row;[controller.view addSubview:strip];
    NSUInteger index=0;
    for(NSDictionary *item in items){
        NSImage *icon=[item[@"icon"] copy];icon.size=NSMakeSize(18,18);
        if(MBSystemItems()[item[@"id"]])icon=[icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightRegular]];
        NSButton *button=[NSButton buttonWithImage:icon target:self action:@selector(openHiddenMenu:)];
        button.identifier=item[@"id"];button.imagePosition=NSImageOnly;button.imageScaling=NSImageScaleProportionallyDown;button.bezelStyle=NSBezelStyleRegularSquare;button.bordered=NO;
        button.toolTip=item[@"name"];button.accessibilityLabel=[@"Open menu for " stringByAppendingString:item[@"name"]];
        button.frame=NSMakeRect(index*32,2,32,28);[row addSubview:button];index++;
    }
    if(!items.count){NSButton *empty=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:@"No running hidden items"] target:self action:@selector(showSettings:)];empty.bordered=NO;empty.frame=NSMakeRect(0,2,32,28);empty.toolTip=@"No running hidden items — open Settings";[row addSubview:empty];}
    if(!self.overflow){self.overflow=[NSPopover new];self.overflow.animates=NO;self.overflow.behavior=NSPopoverBehaviorTransient;self.overflow.delegate=self;}
    self.overflow.contentViewController=controller;self.overflow.contentSize=NSMakeSize(width,height);
    if(!self.overflow.shown)[self.overflow showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
    [NSApp activateIgnoringOtherApps:YES];[self.overflow.contentViewController.view.window makeKeyWindow];
    [self schedulePanelClose];[self updateUI];[self log:[NSString stringWithFormat:@"PANEL open items=%lu; main bar remains collapsed; Accessibility=%@",(unsigned long)items.count,AXIsProcessTrusted()?@"allowed":@"needed"]];
}
- (void)showMenuError:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert=[NSAlert new];alert.messageText=title;alert.informativeText=detail;[alert addButtonWithTitle:@"OK"];
    [NSApp activateIgnoringOtherApps:YES];[alert runModal];
}
- (void)activateMenuForIdentifier:(NSString *)identifier pid:(pid_t)pid before:(NSArray *)before metadata:(NSDictionary *)metadata revision:(NSUInteger)revision started:(NSTimeInterval)started {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        // The host's acknowledgement precedes layout on some OS builds. Probe
        // immediately, then wait only while the selected control is unavailable
        // or moving. Never repeat a press, even when its reply times out.
        NSArray *targets=@[];NSValue *previousRect=nil;id previousTarget=nil;
        NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+2.2;
        BOOL stable=NO;NSUInteger probes=0;
        while(NSProcessInfo.processInfo.systemUptime<deadline){
            if(revision!=self.interactionGeneration)return;
            targets=MBMenuTargets(pid,before,metadata);probes++;
            if(targets.count>1)break;
            NSValue *rect=targets.count==1?MBMenuTargetScreenRect(targets.firstObject):nil;
            stable=rect && previousRect && [rect isEqual:previousRect] && MBAXSameElement(targets.firstObject,previousTarget);
            if(stable)break;
            previousRect=rect;previousTarget=targets.firstObject;
            [NSThread sleepForTimeInterval:probes<4?0.04:0.1];
        }
        dispatch_async(dispatch_get_main_queue(),^{
            if(revision!=self.interactionGeneration)return;
            if(!stable){
                [self finishInteraction];[self showMenuError:@"Could not open this menu" detail:targets.count>1?@"This app exposes multiple menu controls. Direct selection is not available yet.":@"The menu-bar host did not expose a stable matching control. The item has been hidden again."];return;
            }
            [self log:[NSString stringWithFormat:@"MENU ready %@ after %.0f ms (%lu probes)",identifier,(NSProcessInfo.processInfo.systemUptime-started)*1000,(unsigned long)probes]];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                if(revision!=self.interactionGeneration)return;
                AXError result=[identifier isEqual:IStatID]?MBClickMenuTarget((__bridge AXUIElementRef)targets.firstObject):MBPressMenuTarget(targets.firstObject);
                dispatch_async(dispatch_get_main_queue(),^{
                    if(revision!=self.interactionGeneration)return;
                    [self log:[NSString stringWithFormat:@"MENU activation result=%d for %@ after %.0f ms",result,identifier,(NSProcessInfo.processInfo.systemUptime-started)*1000]];
                    if(result!=kAXErrorSuccess && result!=kAXErrorCannotComplete){
                        [self finishInteraction];[self showMenuError:@"Could not open this menu" detail:@"The app declined the Accessibility menu request."];return;
                    }
                    self.interactionTimer=[NSTimer scheduledTimerWithTimeInterval:30 repeats:NO block:^(NSTimer *timer){[self finishInteraction];}];
                    self.outsideMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp|NSEventMaskRightMouseUp|NSEventMaskKeyDown handler:^(NSEvent *event){
                        if(event.type==NSEventTypeKeyDown && event.keyCode!=53)return;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(revision==self.interactionGeneration)[self finishInteraction];});
                    }];
                });
            });
        });
    });
}
- (void)openHiddenMenu:(NSButton *)sender {
    if(!AXIsProcessTrusted()){
        [self.overflow performClose:nil];[self requestMenuAccess:nil];
        [self showMenuError:@"macOS has not granted this build access" detail:@"If MenuBarCompact is already enabled in Device Control and Data Access, remove its old entry and add /Applications/MenuBarCompact.app again. This update uses a consistent developer signature so later builds can retain the grant."];return;
    }
    NSTimeInterval started=NSProcessInfo.processInfo.systemUptime;
    NSString *identifier=sender.identifier;
    NSDictionary *metadata=[identifier isEqual:IStatID]?@{@"preferHost":@YES}:MBSystemItems()[identifier];
    [self finishInteraction];[self.rehideTimer invalidate];
    NSUInteger revision=self.interactionGeneration;
    pid_t pid=self.running[identifier].processIdentifier;
    if([metadata[@"hostBundle"] length])pid=self.running[metadata[@"hostBundle"]].processIdentifier;
    if([identifier isEqual:@"system.input-method"])pid=self.running[@"com.apple.TextInputMenuAgent"].processIdentifier;
    [self.overflow performClose:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSArray *before=MBHostButtons();
        dispatch_async(dispatch_get_main_queue(),^{
            if(revision!=self.interactionGeneration)return;
            self.activeItem=identifier;
            __weak MenuBarCompact *weakSelf=self;
            self.visibilityReadyHandler=^(BOOL success){
                MenuBarCompact *owner=weakSelf;
                if(!owner || revision!=owner.interactionGeneration)return;
                if(!success){[owner finishInteraction];[owner showMenuError:@"Could not reveal this item" detail:@"The menu-bar host did not accept the visibility change. Try opening the panel again."];return;}
                [owner activateMenuForIdentifier:identifier pid:pid before:before metadata:metadata revision:revision started:started];
            };
            [self applyVisibility];
        });
    });
}
- (void)statusClick:(id)sender {
    NSEvent *event=NSApp.currentEvent;
    if(event.type==NSEventTypeRightMouseUp){
        NSMenu *menu=[NSMenu new];menu.delegate=self;
        for(NSArray *entry in @[@[@"Hidden icons…",NSStringFromSelector(@selector(toggle:))],@[@"All hidden icons…",NSStringFromSelector(@selector(showAll:))],@[@"Settings…",NSStringFromSelector(@selector(showSettings:))]]){
            NSMenuItem *item=[menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];item.target=self;
        }
        [menu addItem:NSMenuItem.separatorItem];[menu addItemWithTitle:@"Quit MenuBarCompact" action:@selector(terminate:) keyEquivalent:@"q"];
        self.statusItem.menu=menu;[self.statusItem.button performClick:nil];self.statusItem.menu=nil;
    }else if(event.modifierFlags&NSEventModifierFlagOption){[self showAll:nil];}
    else {[self toggle:nil];}
}
- (void)menuWillOpen:(NSMenu *)menu {self.menuOpen=YES;}
- (void)menuDidClose:(NSMenu *)menu {self.menuOpen=NO;}
- (NSArray *)compatibilityFingerprint {
    NSString *support=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSMutableArray *paths=[NSMutableArray new];
    for(NSString *bundle in @[[support stringByAppendingPathComponent:@"iStat Menus 7/iStat Menus Menubar.app"],@"/Applications/iStat Menus Menubar Compatibility.app"]){
        for(NSString *file in @[@"Contents/MacOS/iStat Menus Menubar",@"Contents/Info.plist",@"Contents/_CodeSignature/CodeResources"])[paths addObject:[bundle stringByAppendingPathComponent:file]];
    }
    [paths addObject:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.bjango.istatmenus.status.plist"]];
    [paths addObject:[support stringByAppendingPathComponent:@"MenuBarCompact/workaround.json"]];
    return @[MBFileFingerprint(paths),@(self.running[IStatID].processIdentifier)];
}
- (void)checkCompatibility:(id)sender {
    if(self.compatibilityTask || self.paused)return;
    NSArray *fingerprint=[self compatibilityFingerprint];
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(!MBNeedsCompatibilityAudit(fingerprint,self.verifiedCompatibilityFingerprint,self.ready,now-self.lastCompatibilityAudit,self.lastCompatibilityAttempt>0?now-self.lastCompatibilityAttempt:60,sender!=nil))return;
    self.lastCompatibilityAttempt=now;
    NSString *script=[NSBundle.mainBundle pathForResource:@"istat_workaround" ofType:@"py"];
    if(!script){self.ready=NO;self.compatibilityMessage=@"Compatibility helper is missing; reinstall MenuBarCompact";[self applyVisibility];return;}
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/python3"];task.arguments=@[script,@"ensure"];task.qualityOfService=NSQualityOfServiceUtility;
    NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=pipe;self.compatibilityTask=task;
    NSError *error;
    if(![task launchAndReturnError:&error]){self.compatibilityTask=nil;self.ready=NO;self.compatibilityMessage=@"Could not check iStat; open diagnostics for details";[self log:error.description];[self applyVisibility];return;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];
        dispatch_async(dispatch_get_main_queue(),^{
            self.compatibilityTask=nil;self.ready=task.terminationStatus==0;
            self.compatibilityMessage=self.ready?@"iStat compatibility is ready · checked automatically":@"iStat compatibility needs attention · hiding is paused";
            if(!self.ready || sender)[self log:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]?:@"Compatibility check returned no output"];
            [self refreshApps];
            if(self.ready){self.verifiedCompatibilityFingerprint=[self compatibilityFingerprint];self.lastCompatibilityAudit=NSProcessInfo.processInfo.systemUptime;}
            [self applyVisibility];
        });
    });
}
- (void)setLoginEnabled:(BOOL)enabled {
    NSError *error=nil;SMAppService *service=SMAppService.mainAppService;
    BOOL success=YES;
    if(enabled && service.status!=SMAppServiceStatusEnabled)success=[service registerAndReturnError:&error];
    else if(!enabled && service.status!=SMAppServiceStatusNotRegistered)success=[service unregisterAndReturnError:&error];
    if(!success)[self log:[NSString stringWithFormat:@"LOGIN: %@",error]];
    [self updateLoginUI];
}
- (void)toggleLogin:(NSButton *)sender {[self setLoginEnabled:sender.state==NSControlStateValueOn];}
- (void)toggleAutoHide:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.state==NSControlStateValueOn forKey:@"AutoRehide"];
    [self schedulePanelClose];
}
- (void)takeOver:(id)sender {
    [self.running[ThawID] terminate];self.stateMessage=@"Waiting for Thaw to quit…";[self updateUI];
}
- (void)openDiagnostics:(id)sender {[NSWorkspace.sharedWorkspace openURL:self.logURL];}
- (void)toggleAppScope:(id)sender {self.search.placeholderString=self.allAppsButton.state==NSControlStateValueOn?@"Find an app":@"Find a configured item";[self rebuildRows];}
- (void)updateUI {
    BOOL shown=self.overflow.shown;
    if(!self.closedStatusImage){self.closedStatusImage=[NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:@"MenuBarCompact"];self.closedStatusImage.template=YES;
        self.openStatusImage=[NSImage imageWithSystemSymbolName:@"ellipsis.circle.fill" accessibilityDescription:@"MenuBarCompact"];self.openStatusImage.template=YES;}
    NSImage *image=shown?self.openStatusImage:self.closedStatusImage;
    if(self.statusItem.button.image!=image)self.statusItem.button.image=image;
    NSString *tip=[NSString stringWithFormat:@"MenuBarCompact — %@\nClick for hidden icons below the menu bar. Right-click for settings. Option-click includes always-hidden icons.",self.stateMessage?:@""];
    if(![self.statusItem.button.toolTip isEqual:tip])self.statusItem.button.toolTip=tip;
    if(!self.window.visible)return;
    NSString *summary=self.stateMessage?:@"Starting…",*compatibility=self.compatibilityMessage?:@"Checking iStat…";
    if(![self.summaryLabel.stringValue isEqual:summary])self.summaryLabel.stringValue=summary;
    if(![self.compatibilityLabel.stringValue isEqual:compatibility])self.compatibilityLabel.stringValue=compatibility;
    self.takeOverButton.hidden=self.running[ThawID]==nil;
    NSString *toggle=shown?@"Close hidden panel":@"Open hidden panel";
    if(![self.toggleButton.title isEqual:toggle])self.toggleButton.title=toggle;
}
- (void)updateLoginUI {
    SMAppServiceStatus status=SMAppService.mainAppService.status;
    self.loginButton.state=(status==SMAppServiceStatusEnabled || status==SMAppServiceStatusRequiresApproval)?NSControlStateValueOn:NSControlStateValueOff;
    self.loginLabel.stringValue=status==SMAppServiceStatusEnabled?@"Starts automatically when you sign in":(status==SMAppServiceStatusRequiresApproval?@"Allow MenuBarCompact in System Settings → Login Items":@"Open MenuBarCompact when you want to use it");
}
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size secondary:(BOOL)secondary {
    NSTextField *label=[NSTextField labelWithString:text];label.frame=frame;label.font=[NSFont systemFontOfSize:size weight:NSFontWeightRegular];
    if(secondary)label.textColor=NSColor.secondaryLabelColor;[self.window.contentView addSubview:label];return label;
}
- (NSButton *)button:(NSString *)text action:(SEL)action frame:(NSRect)frame {
    NSButton *button=[NSButton buttonWithTitle:text target:self action:action];button.frame=frame;[self.window.contentView addSubview:button];return button;
}
- (void)buildWindow {
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,960,720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.delegate=self;self.window.contentMinSize=NSMakeSize(800,600);
    self.window.title=@"MenuBarCompact";self.window.releasedWhenClosed=NO;self.window.animationBehavior=NSWindowAnimationBehaviorNone;self.renderedLaneRows=[NSMutableDictionary new];
    NSTextField *title=[self label:@"A quieter menu bar." frame:NSMakeRect(28,655,900,35) size:26 secondary:NO];title.font=[NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    self.summaryLabel=[self label:@"Starting…" frame:NSMakeRect(28,625,900,24) size:14 secondary:YES];
    self.toggleButton=[self button:@"Open hidden panel" action:@selector(toggle:) frame:NSMakeRect(24,580,180,32)];
    [self button:@"All hidden icons" action:@selector(showAll:) frame:NSMakeRect(210,580,160,32)];
    self.takeOverButton=[self button:@"Quit Thaw and start" action:@selector(takeOver:) frame:NSMakeRect(725,580,210,32)];
    self.search=[[NSSearchField alloc] initWithFrame:NSMakeRect(28,533,670,30)];self.search.placeholderString=@"Find a configured item";self.search.delegate=self;[self.window.contentView addSubview:self.search];
    self.allAppsButton=[NSButton checkboxWithTitle:@"Show all running apps" target:self action:@selector(toggleAppScope:)];self.allAppsButton.frame=NSMakeRect(720,536,214,24);[self.window.contentView addSubview:self.allAppsButton];
    // Header stays at the top when wrapping makes the window taller. Footer
    // controls stay at the bottom; only the section viewport stretches.
    for(NSView *view in self.window.contentView.subviews)view.autoresizingMask=NSViewMinYMargin;
    title.autoresizingMask|=NSViewWidthSizable;self.summaryLabel.autoresizingMask|=NSViewWidthSizable;
    self.search.autoresizingMask|=NSViewWidthSizable;self.allAppsButton.autoresizingMask|=NSViewMinXMargin;
    self.takeOverButton.autoresizingMask|=NSViewMinXMargin;
    self.visibilityEditorScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(28,208,904,304)];
    self.visibilityEditorScroll.hasVerticalScroller=YES;self.visibilityEditorScroll.hasHorizontalScroller=NO;
    self.visibilityEditorScroll.scrollerStyle=NSScrollerStyleOverlay;self.visibilityEditorScroll.horizontalScrollElasticity=NSScrollElasticityNone;
    self.visibilityEditorScroll.autohidesScrollers=YES;self.visibilityEditorScroll.drawsBackground=NO;
    self.visibilityEditorScroll.autoresizingMask=NSViewHeightSizable|NSViewWidthSizable;
    MBVisibilityDocument *document=[[MBVisibilityDocument alloc] initWithFrame:NSMakeRect(0,0,self.visibilityEditorScroll.contentSize.width,304)];
    self.visibilityEditorScroll.documentView=document;[self.window.contentView addSubview:self.visibilityEditorScroll];
    NSMutableArray *lanes=[NSMutableArray new],*counts=[NSMutableArray new],*labels=[NSMutableArray new];
    NSArray *titles=@[@"Always Show",@"Hide",@"Always Hide"];
    NSArray *details=@[@"In the menu bar",@"In the second row",@"Option-click to reveal"];
    for(NSInteger rule=0;rule<3;rule++){
        NSTextField *heading=[NSTextField labelWithString:titles[rule]];heading.font=[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        NSTextField *detail=[NSTextField labelWithString:details[rule]];detail.font=[NSFont systemFontOfSize:10];detail.textColor=NSColor.secondaryLabelColor;
        NSTextField *count=[NSTextField labelWithString:@""];count.font=[NSFont systemFontOfSize:10];count.textColor=NSColor.secondaryLabelColor;
        for(NSView *label in @[heading,detail,count])[document addSubview:label];
        [labels addObject:@[heading,detail,count]];[counts addObject:count];
        MBVisibilityLane *lane=[[MBVisibilityLane alloc] initWithFrame:NSZeroRect];lane.rule=rule;lane.editorDelegate=self;lane.accessibilityLabel=[titles[rule] stringByAppendingString:@" drop area"];
        [document addSubview:lane];[lanes addObject:lane];
    }
    self.visibilityLanes=lanes;self.visibilityCounts=counts;self.visibilityLabels=labels;
    [self label:@"Drag icons between sections to change visibility. Icons wrap automatically." frame:NSMakeRect(28,166,905,21) size:12 secondary:YES];
    self.autoHideButton=[NSButton checkboxWithTitle:@"Close panel after 15 seconds" target:self action:@selector(toggleAutoHide:)];self.autoHideButton.frame=NSMakeRect(28,122,320,24);self.autoHideButton.state=[NSUserDefaults.standardUserDefaults boolForKey:@"AutoRehide"]?1:0;[self.window.contentView addSubview:self.autoHideButton];
    self.loginButton=[NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(toggleLogin:)];self.loginButton.frame=NSMakeRect(420,122,350,24);[self.window.contentView addSubview:self.loginButton];
    self.loginLabel=[self label:@"" frame:NSMakeRect(420,96,370,22) size:11 secondary:YES];
    self.compatibilityLabel=[self label:@"" frame:NSMakeRect(28,60,760,22) size:12 secondary:YES];
    [self button:@"Check iStat" action:@selector(checkCompatibility:) frame:NSMakeRect(23,18,120,30)];
    [self button:@"Diagnostics…" action:@selector(openDiagnostics:) frame:NSMakeRect(150,18,145,30)];
    [self button:@"Rescan system items" action:@selector(discoverSystemItems:) frame:NSMakeRect(300,18,180,30)];
    [self label:@"MenuBarCompact 0.6.7 · drag to organize" frame:NSMakeRect(525,23,270,22) size:11 secondary:YES];
    self.userResizedSettings=YES;
    self.userResizedSettings=[self.window setFrameUsingName:@"MenuBarCompact.Settings"];
    if(!self.userResizedSettings)[self.window center];
    [self.window setFrameAutosaveName:@"MenuBarCompact.Settings"];
}
- (void)windowWillStartLiveResize:(NSNotification *)notification {self.userResizedSettings=YES;}
- (BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)frame {self.userResizedSettings=YES;return YES;}
- (void)windowDidResize:(NSNotification *)notification {
    if(self.visibilityLanes.count && !self.layingOutSettings)[self renderVisibilityLanes];
}
- (void)showSettings:(id)sender {[self.overflow performClose:nil];if(!self.window)[self buildWindow];[self.window makeKeyAndOrderFront:nil];[self refreshApps];[self updateUI];[self updateLoginUI];[NSApp activateIgnoringOtherApps:YES];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {if(!self.overflow.shown)[self showSettings:nil];return YES;}
- (BOOL)canMoveVisibilityItem:(NSString *)identifier toRule:(NSInteger)rule {
    if(rule<0 || rule>2 || [self protectedID:identifier])return NO;
    if([identifier hasPrefix:@"system."] && !MBSystemItems()[identifier])return NO;
    return self.rules[identifier]!=nil || self.running[identifier]!=nil || MBSystemItems()[identifier]!=nil;
}
- (void)moveVisibilityItem:(NSString *)identifier toRule:(NSInteger)rule {
    if(![self canMoveVisibilityItem:identifier toRule:rule] || self.rules[identifier].integerValue==rule)return;
    [self finishInteraction];self.rules[identifier]=@(rule);
    [self saveRules];[self rebuildRows];[self applyVisibility];
}
- (void)renderVisibilityLanes {
    if(self.layingOutSettings)return;self.layingOutSettings=YES;
    NSArray *titles=@[@"Always Show",@"Hide",@"Always Hide"];
    NSMutableArray<NSMutableArray *> *groups=[NSMutableArray new];for(NSUInteger rule=0;rule<3;rule++)[groups addObject:[NSMutableArray new]];
    for(NSDictionary *row in self.rows){NSInteger rule=[self protectedID:row[@"id"]]?0:MIN(2,MAX(0,[row[@"rule"] integerValue]));[groups[rule] addObject:row];}
    CGFloat width=self.visibilityEditorScroll.contentSize.width-156,totalHeight=28;
    for(NSArray *items in groups)totalHeight+=MBVisibilityHeight(items.count,width);
    // Fit ordinary wrapped sections on screen; very large app lists scroll
    // vertically as one page. Filtering does not resize the window per keystroke.
    if(!self.userResizedSettings && !self.search.stringValue.length){
        NSRect screen=(self.window.screen?:NSScreen.mainScreen).visibleFrame;
        CGFloat maxHeight=[self.window contentRectForFrameRect:screen].size.height-16;
        CGFloat height=MIN(maxHeight,720+MAX(0,totalHeight-304));
        if(fabs(self.window.contentView.bounds.size.height-height)>0.5){
            NSRect frame=self.window.frame;CGFloat oldHeight=frame.size.height;
            frame.size.height=[self.window frameRectForContentRect:NSMakeRect(0,0,self.window.contentView.bounds.size.width,height)].size.height;
            frame.origin.y=MAX(NSMinY(screen),MIN(frame.origin.y+oldHeight-frame.size.height,NSMaxY(screen)-frame.size.height));
            [self.window setFrame:frame display:YES animate:NO];
        }
    }
    NSView *document=self.visibilityEditorScroll.documentView;
    document.frame=NSMakeRect(0,0,self.visibilityEditorScroll.contentSize.width,totalHeight);
    CGFloat y=0;
    for(NSUInteger rule=0;rule<self.visibilityLanes.count;rule++){
        NSArray *items=groups[rule];MBVisibilityLane *lane=self.visibilityLanes[rule];CGFloat height=MBVisibilityHeight(items.count,width);
        lane.frame=NSMakeRect(156,y,width,height);
        self.visibilityLabels[rule][0].frame=NSMakeRect(0,y+18,148,22);
        self.visibilityLabels[rule][1].frame=NSMakeRect(0,y+40,148,18);
        self.visibilityLabels[rule][2].frame=NSMakeRect(0,y+62,148,18);
        y+=height+14;
        NSArray *renderKey=@[[items copy],@(self.search.stringValue.length>0),@(MBVisibilityColumns(width))];
        if([renderKey isEqual:self.renderedLaneRows[@(rule)]])continue;
        self.renderedLaneRows[@(rule)]=renderKey;
        for(NSView *view in lane.subviews.copy)[view removeFromSuperview];
        self.visibilityCounts[rule].stringValue=[NSString stringWithFormat:@"%lu item%@",(unsigned long)items.count,items.count==1?@"":@"s"];
        NSUInteger index=0;
        for(NSDictionary *row in items){
            NSString *identifier=row[@"id"],*name=row[@"name"];BOOL locked=[self protectedID:identifier];
            MBVisibilityIcon *icon=[[MBVisibilityIcon alloc] initWithFrame:MBVisibilityIconFrame(index++,items.count,width)];
            icon.identifier=identifier;icon.title=name;icon.font=[NSFont systemFontOfSize:10];icon.bordered=NO;icon.imagePosition=NSImageAbove;
            NSImage *image=[[self rowIconForIdentifier:identifier name:name] copy];image.size=NSMakeSize(24,24);icon.image=image;icon.imageScaling=NSImageScaleProportionallyDown;
            icon.cell.lineBreakMode=NSLineBreakByTruncatingTail;icon.movable=!locked;
            icon.accessibilityLabel=[NSString stringWithFormat:@"%@ — %@%@",name,titles[rule],locked?@" (protected)":@""];
            icon.toolTip=[NSString stringWithFormat:@"%@\n%@",name,locked?@"Kept visible":@"Drag to another section to change visibility"];
            [lane addSubview:icon];
        }
        if(!items.count){NSTextField *empty=[NSTextField labelWithString:self.search.stringValue.length?@"No matching items in this section":@"Drop icons here"];empty.textColor=NSColor.tertiaryLabelColor;empty.font=[NSFont systemFontOfSize:12];empty.frame=NSMakeRect(20,32,400,20);[lane addSubview:empty];}
        lane.needsDisplay=YES;
    }
    NSClipView *clip=self.visibilityEditorScroll.contentView;
    [clip scrollToPoint:NSMakePoint(0,MIN(clip.bounds.origin.y,MAX(0,totalHeight-clip.bounds.size.height)))];
    [self.visibilityEditorScroll reflectScrolledClipView:clip];
    self.layingOutSettings=NO;
}
- (void)controlTextDidChange:(NSNotification *)notification {[self rebuildRows];}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    if(self.compatibilityTask.running){self.stateMessage=@"Finishing iStat check before quitting…";[self updateUI];return NSTerminateCancel;}
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {self.paused=YES;[self.maintenance invalidate];[self.rehideTimer invalidate];[self finishInteraction];[self releaseRestriction];[self saveRules];[self log:@"STOP — menu-bar restriction released"];}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {return NO;}
@end

int main(int argc,const char *argv[]) {
    @autoreleasepool {NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;MenuBarCompact *delegate=[MenuBarCompact new];app.delegate=delegate;[app run];}
    return 0;
}
