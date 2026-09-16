#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dlfcn.h>
#import "VisibilityPolicy.h"
#import "MenuActivation.h"
#import "SystemDiscovery.h"
#import "VisibilityEditor.h"

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

@interface MenuBarCompact : NSObject <NSApplicationDelegate, MBVisibilityEditorDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSPopoverDelegate>
@property NSStatusItem *statusItem;
@property NSWindow *window;
@property NSTextField *summaryLabel, *compatibilityLabel, *loginLabel;
@property NSButton *loginButton, *autoHideButton, *takeOverButton, *toggleButton, *allAppsButton;
@property NSSearchField *search;
@property NSArray<NSScrollView *> *visibilityScrolls;
@property NSArray<NSTextField *> *visibilityCounts;
@property NSMutableDictionary<NSString *,NSNumber *> *rules;
@property NSMutableDictionary<NSString *,NSString *> *names;
@property NSArray<NSDictionary *> *rows;
@property NSDictionary<NSString *,NSRunningApplication *> *running;
@property id assertion;
@property NSArray *lastAllowlist, *lastSystemAllowlist;
@property NSTimer *rehideTimer, *maintenance, *processWatch;
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
    self.maintenance=[NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(maintain:) userInfo:nil repeats:YES];
    // NSWorkspace can miss helper/agent exits on the current macOS beta.
    // Compare process identities cheaply; rebuild only when the set changes.
    self.processWatch=[NSTimer timerWithTimeInterval:3 target:self selector:@selector(pollApps:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.processWatch forMode:NSRunLoopCommonModes];
    if([NSProcessInfo.processInfo.arguments containsObject:@"--enable-login"])[self setLoginEnabled:YES];
    if(first || [NSProcessInfo.processInfo.arguments containsObject:@"--settings"])[self showSettings:nil];
    [self log:@"START MenuBarCompact 0.6.2"];
}
- (void)workspaceChanged:(NSNotification *)note {
    if([note.name isEqual:NSWorkspaceDidWakeNotification] || [note.name isEqual:NSWorkspaceSessionDidBecomeActiveNotification]){
        self.paused=NO;[self releaseRestriction];
    }
    NSUInteger revision=++self.refreshGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(revision!=self.refreshGeneration)return;
        [self refreshApps];[self applyVisibility];
    });
}
- (void)suspend:(NSNotification *)note {self.paused=YES;[self releaseRestriction];}
- (void)maintain:(id)sender {[self discoverSystemItems:nil];[self refreshApps];[self checkCompatibility:nil];}
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
    NSDictionary *catalog=MBDiscoverSystemItems();self.discoveryReady=catalog.count>0;
    if(!catalog){[self log:@"DISCOVERY unavailable — hiding paused"];[self applyVisibility];return;}
    if(![catalog isEqual:MBSystemItems()]){
        MBSetSystemItems(catalog);
        [self log:[NSString stringWithFormat:@"DISCOVERY %lu system items (%lu runtime categories)",(unsigned long)catalog.count,(unsigned long)MBSystemCategoryIDs().count]];
    }
    if(self.rules)[self rebuildRows];if(self.ready)[self applyVisibility];
}
- (void)rebuildRows {
    NSMutableSet *ids=[NSMutableSet setWithArray:self.rules.allKeys];
    [ids addObject:IStatID];
    [ids addObjectsFromArray:MBSystemItems().allKeys];
    for(NSRunningApplication *app in self.running.allValues){
        if(self.allAppsButton.state==NSControlStateValueOn && ![self protectedID:app.bundleIdentifier] && (app.activationPolicy!=NSApplicationActivationPolicyProhibited || self.rules[app.bundleIdentifier]))[ids addObject:app.bundleIdentifier];
    }
    NSString *query=self.search.stringValue?:@"";
    NSMutableArray *rows=[NSMutableArray new];
    for(NSString *identifier in ids){
        NSString *name=self.names[identifier];
        if(!name){NSURL *url=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];name=url?[[NSFileManager.defaultManager displayNameAtPath:url.path] stringByDeletingPathExtension]:identifier;}
        if([identifier isEqual:IStatID])name=@"iStat Menus";
        if(MBSystemItems()[identifier])name=MBSystemItems()[identifier][@"name"];
        if(query.length && [name rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound && [identifier rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound)continue;
        [rows addObject:@{@"id":identifier,@"name":name?:identifier,@"running":@(self.running[identifier]!=nil),@"rule":self.rules[identifier]?:@0,@"system":MBSystemItems()[identifier]?:@{}}];
    }
    NSArray *sorted=[rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
    if([sorted isEqual:self.rows])return;self.rows=sorted;
    [self renderVisibilityLanes];
}
- (void)releaseRestriction {
    self.generation++;self.activationPending=NO;
    if(self.assertion){[self.assertion invalidate];self.assertion=nil;[self log:@"RELEASE visibility restriction"];}
    self.lastAllowlist=nil;self.lastSystemAllowlist=nil;
}
- (void)applyVisibility {
    if(self.paused)return;
    if(!self.discoveryReady){[self releaseRestriction];self.stateMessage=@"System item discovery unavailable; hiding is paused";[self updateUI];return;}
    if(self.running[ThawID]){[self releaseRestriction];self.stateMessage=@"Paused while Thaw is running";[self updateUI];return;}
    if(!self.ready){[self releaseRestriction];self.stateMessage=@"Waiting for iStat compatibility";[self updateUI];return;}
    NSDictionary *effectiveRules=MBInteractionRules(self.rules,self.activeItem);
    NSDictionary *plan=MBVisibilityPlan(self.running.allKeys,effectiveRules,OwnID,Collapsed);
    NSUInteger excluded=[plan[@"excluded"] unsignedIntegerValue];
    NSArray *systems=plan[@"systems"];
    if(self.mode==Everything || excluded==0){[self releaseRestriction];self.stateMessage=self.mode==Everything?@"Showing all items":@"All configured items are visible";[self updateUI];return;}
    NSArray *bundles=plan[@"bundles"];
    if(self.assertion && [bundles isEqual:self.lastAllowlist] && [systems isEqual:self.lastSystemAllowlist]){
        if(!self.activationPending)self.stateMessage=self.mode==Collapsed?@"Hidden items are tucked away":@"Showing hidden items";
        [self updateUI];return;
    }
    [self releaseRestriction];
    Class configuration=NSClassFromString(@"MBAssessmentModeConfiguration"), assertion=NSClassFromString(@"MBAssessmentModeAssertion");
    if(!configuration || !assertion || ![configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)] || ![assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)] || ![assertion instancesRespondToSelector:@selector(invalidate)]){
        self.stateMessage=@"Hiding is unavailable on this macOS version";[self updateUI];return;
    }
    @try {
        id config=[[configuration alloc] initWithAllowedSystemItems:systems allowedBundleIdentifiers:bundles];
        self.assertion=[assertion new];
        if(!config || !self.assertion){[self releaseRestriction];self.stateMessage=@"Could not start hiding; all items remain visible";[self updateUI];return;}
        self.lastAllowlist=bundles;self.lastSystemAllowlist=systems;self.activationPending=YES;
        NSUInteger revision=self.generation;
        self.stateMessage=@"Updating menu bar…";
        [self.assertion activateWithConfiguration:config completionHandler:^(NSError *error){
            dispatch_async(dispatch_get_main_queue(),^{
                if(revision!=self.generation)return;
                self.activationPending=NO;
                if(error){[self releaseRestriction];self.stateMessage=@"Could not hide apps; all items remain visible";[self log:[NSString stringWithFormat:@"ACTIVATE failed: %@",error]];}
                else {self.stateMessage=self.mode==Collapsed?@"Hidden items are tucked away":@"Showing hidden items";[self log:[NSString stringWithFormat:@"ACTIVATE success mode=%ld excluded=%lu iStat=%@",(long)self.mode,(unsigned long)excluded,[bundles containsObject:IStatID]?@"allowed":@"hidden"]];}
                [self updateUI];
            });
        }];
        // Do not retain an uncertain assertion indefinitely if the private host stops replying.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(revision==self.generation && self.activationPending){[self releaseRestriction];self.stateMessage=@"Menu bar did not respond; hiding is paused";[self updateUI];}
        });
    } @catch(NSException *exception){[self releaseRestriction];self.stateMessage=@"Hiding is unavailable; all items remain visible";[self log:exception.reason];}
    [self updateUI];
}
- (void)finishInteraction {
    self.interactionGeneration++;
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
    [self finishInteraction];
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
    if(!self.overflow){self.overflow=[NSPopover new];self.overflow.behavior=NSPopoverBehaviorTransient;self.overflow.delegate=self;}
    self.overflow.contentViewController=controller;self.overflow.contentSize=NSMakeSize(width,height);
    if(!self.overflow.shown)[self.overflow showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
    [NSApp activateIgnoringOtherApps:YES];[self.overflow.contentViewController.view.window makeKeyWindow];
    [self schedulePanelClose];[self updateUI];[self log:[NSString stringWithFormat:@"PANEL open items=%lu; main bar remains collapsed; Accessibility=%@",(unsigned long)items.count,AXIsProcessTrusted()?@"allowed":@"needed"]];
}
- (void)showMenuError:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert=[NSAlert new];alert.messageText=title;alert.informativeText=detail;[alert addButtonWithTitle:@"OK"];
    [NSApp activateIgnoringOtherApps:YES];[alert runModal];
}
- (void)openHiddenMenu:(NSButton *)sender {
    if(!AXIsProcessTrusted()){
        [self.overflow performClose:nil];[self requestMenuAccess:nil];
        [self showMenuError:@"macOS has not granted this build access" detail:@"If MenuBarCompact is already enabled in Device Control and Data Access, remove its old entry and add /Applications/MenuBarCompact.app again. This update uses a consistent developer signature so later builds can retain the grant."];
        return;
    }
    NSString *identifier=sender.identifier;
    NSDictionary *systemMetadata=[identifier isEqual:IStatID]?@{@"preferHost":@YES}:MBSystemItems()[identifier];
    [self finishInteraction];[self.rehideTimer invalidate];
    NSUInteger revision=self.interactionGeneration;
    pid_t pid=self.running[identifier].processIdentifier;
    if([systemMetadata[@"hostBundle"] length])pid=self.running[systemMetadata[@"hostBundle"]].processIdentifier;
    if([identifier isEqual:@"system.input-method"])pid=self.running[@"com.apple.TextInputMenuAgent"].processIdentifier;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSArray *before=MBHostButtons();
        dispatch_async(dispatch_get_main_queue(),^{
            if(revision!=self.interactionGeneration)return;
            self.activeItem=identifier;[self applyVisibility];
            [self.overflow performClose:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                NSArray *targets=MBMenuTargets(pid,before,systemMetadata);
                // Hosted controls can arrive after the allowlist completion.
                // Retry discovery only; never repeat a press that may succeed.
                for(NSUInteger attempt=0;!targets.count && attempt<10;attempt++){
                    [NSThread sleepForTimeInterval:0.15];
                    targets=MBMenuTargets(pid,before,systemMetadata);
                }
                if(!targets.count){NSMutableArray *identities=[NSMutableArray new];for(id item in MBHostButtons())[identities addObject:MBAXIdentity(item)];[self log:[NSString stringWithFormat:@"MENU discovery %@ host=%@",identifier,identities]];}
                dispatch_async(dispatch_get_main_queue(),^{
                    if(revision!=self.interactionGeneration)return;
                    if(targets.count!=1){
                        [self finishInteraction];[self openOverflowIncludingAlwaysHidden:self.includeAlwaysHidden];
                        [self.overflow performClose:nil];[self showMenuError:@"Could not open this menu" detail:targets.count?@"This app exposes multiple menu controls. Direct selection is not available yet.":@"The menu-bar host did not expose a matching control. The item has been hidden again."];
                        [self.rehideTimer invalidate];[self log:[NSString stringWithFormat:@"MENU unresolved %@ candidates=%lu",identifier,(unsigned long)targets.count]];return;
                    }
                    [self log:[NSString stringWithFormat:@"MENU activating %@; only this item is temporarily visible",identifier]];
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                        // iStat rejects AXPress even on the host; activate its verified
                        // status-item geometry directly, without first issuing an AX press.
                        AXError result=[identifier isEqual:IStatID]?MBClickMenuTarget((__bridge AXUIElementRef)targets.firstObject):MBPressMenuTarget(targets.firstObject);
                        dispatch_async(dispatch_get_main_queue(),^{
                            if(revision!=self.interactionGeneration)return;
                            [self log:[NSString stringWithFormat:@"MENU activation result=%d for %@",result,identifier]];
                            if(result!=kAXErrorSuccess && result!=kAXErrorCannotComplete){
                                [self finishInteraction];[self openOverflowIncludingAlwaysHidden:self.includeAlwaysHidden];[self.overflow performClose:nil];[self showMenuError:@"Could not open this menu" detail:@"The app declined the Accessibility menu request."];return;
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
- (void)checkCompatibility:(id)sender {
    if(self.compatibilityTask.running)return;
    NSString *script=[NSBundle.mainBundle pathForResource:@"istat_workaround" ofType:@"py"];
    if(!script){self.ready=NO;self.compatibilityMessage=@"Compatibility helper is missing; reinstall MenuBarCompact";[self applyVisibility];return;}
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/python3"];task.arguments=@[script,@"ensure"];
    NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=pipe;self.compatibilityTask=task;
    NSError *error;
    if(![task launchAndReturnError:&error]){self.compatibilityTask=nil;self.ready=NO;self.compatibilityMessage=@"Could not check iStat; open diagnostics for details";[self log:error.description];[self applyVisibility];return;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];
        dispatch_async(dispatch_get_main_queue(),^{
            self.compatibilityTask=nil;self.ready=task.terminationStatus==0;
            self.compatibilityMessage=self.ready?@"iStat compatibility is ready · checked automatically":@"iStat compatibility needs attention · hiding is paused";
            if(!self.ready || sender)[self log:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]?:@"Compatibility check returned no output"];
            [self refreshApps];[self applyVisibility];
        });
    });
}
- (void)setLoginEnabled:(BOOL)enabled {
    NSError *error=nil;SMAppService *service=SMAppService.mainAppService;
    BOOL success=YES;
    if(enabled && service.status!=SMAppServiceStatusEnabled)success=[service registerAndReturnError:&error];
    else if(!enabled && service.status!=SMAppServiceStatusNotRegistered)success=[service unregisterAndReturnError:&error];
    if(!success)[self log:[NSString stringWithFormat:@"LOGIN: %@",error]];
    [self updateUI];
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
    self.summaryLabel.stringValue=self.stateMessage?:@"Starting…";
    self.compatibilityLabel.stringValue=self.compatibilityMessage?:@"Checking iStat…";
    self.takeOverButton.hidden=self.running[ThawID]==nil;
    self.toggleButton.title=self.overflow.shown?@"Close hidden panel":@"Open hidden panel";
    NSImage *image=[NSImage imageWithSystemSymbolName:self.overflow.shown?@"ellipsis.circle.fill":@"ellipsis.circle" accessibilityDescription:@"MenuBarCompact"];
    image.template=YES;self.statusItem.button.image=image;
    self.statusItem.button.toolTip=[NSString stringWithFormat:@"MenuBarCompact — %@\nClick for hidden icons below the menu bar. Right-click for settings. Option-click includes always-hidden icons.",self.stateMessage?:@""];
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
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,960,720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"MenuBarCompact";self.window.releasedWhenClosed=NO;
    NSTextField *title=[self label:@"A quieter menu bar." frame:NSMakeRect(28,655,900,35) size:26 secondary:NO];title.font=[NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    self.summaryLabel=[self label:@"Starting…" frame:NSMakeRect(28,625,900,24) size:14 secondary:YES];
    self.toggleButton=[self button:@"Open hidden panel" action:@selector(toggle:) frame:NSMakeRect(24,580,180,32)];
    [self button:@"All hidden icons" action:@selector(showAll:) frame:NSMakeRect(210,580,160,32)];
    self.takeOverButton=[self button:@"Quit Thaw and start" action:@selector(takeOver:) frame:NSMakeRect(725,580,210,32)];
    self.search=[[NSSearchField alloc] initWithFrame:NSMakeRect(28,533,670,30)];self.search.placeholderString=@"Find a configured item";self.search.delegate=self;[self.window.contentView addSubview:self.search];
    self.allAppsButton=[NSButton checkboxWithTitle:@"Show all running apps" target:self action:@selector(toggleAppScope:)];self.allAppsButton.frame=NSMakeRect(720,536,214,24);[self.window.contentView addSubview:self.allAppsButton];
    NSMutableArray *scrolls=[NSMutableArray new],*counts=[NSMutableArray new];
    NSArray *titles=@[@"Always Show",@"Hide",@"Always Hide"];
    NSArray *details=@[@"In the menu bar",@"In the second row",@"Option-click to reveal"];
    for(NSInteger rule=0;rule<3;rule++){
        CGFloat y=420-rule*106;
        NSTextField *heading=[self label:titles[rule] frame:NSMakeRect(28,y+56,148,22) size:14 secondary:NO];heading.font=[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        [self label:details[rule] frame:NSMakeRect(28,y+34,148,18) size:10 secondary:YES];
        [counts addObject:[self label:@"" frame:NSMakeRect(28,y+12,148,18) size:10 secondary:YES]];
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(184,y,748,92)];scroll.hasHorizontalScroller=YES;scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;
        MBVisibilityLane *lane=[[MBVisibilityLane alloc] initWithFrame:NSMakeRect(0,0,748,92)];lane.rule=rule;lane.editorDelegate=self;lane.accessibilityLabel=[titles[rule] stringByAppendingString:@" drop area"];
        scroll.documentView=lane;[self.window.contentView addSubview:scroll];[scrolls addObject:scroll];
    }
    self.visibilityScrolls=scrolls;self.visibilityCounts=counts;
    [self label:@"Drag icons between rows to change visibility. Scroll sideways to see more." frame:NSMakeRect(28,166,905,21) size:12 secondary:YES];
    self.autoHideButton=[NSButton checkboxWithTitle:@"Close panel after 15 seconds" target:self action:@selector(toggleAutoHide:)];self.autoHideButton.frame=NSMakeRect(28,122,320,24);self.autoHideButton.state=[NSUserDefaults.standardUserDefaults boolForKey:@"AutoRehide"]?1:0;[self.window.contentView addSubview:self.autoHideButton];
    self.loginButton=[NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(toggleLogin:)];self.loginButton.frame=NSMakeRect(420,122,350,24);[self.window.contentView addSubview:self.loginButton];
    self.loginLabel=[self label:@"" frame:NSMakeRect(420,96,370,22) size:11 secondary:YES];
    self.compatibilityLabel=[self label:@"" frame:NSMakeRect(28,60,760,22) size:12 secondary:YES];
    [self button:@"Check iStat" action:@selector(checkCompatibility:) frame:NSMakeRect(23,18,120,30)];
    [self button:@"Diagnostics…" action:@selector(openDiagnostics:) frame:NSMakeRect(150,18,145,30)];
    [self button:@"Rescan system items" action:@selector(discoverSystemItems:) frame:NSMakeRect(300,18,180,30)];
    [self label:@"MenuBarCompact 0.6.2 · drag to organize" frame:NSMakeRect(525,23,270,22) size:11 secondary:YES];
    [self.window center];[self rebuildRows];[self renderVisibilityLanes];[self updateUI];
}
- (void)showSettings:(id)sender {[self.overflow performClose:nil];if(!self.window)[self buildWindow];[self refreshApps];[self updateUI];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {if(!self.overflow.shown)[self showSettings:nil];return YES;}
- (BOOL)canMoveVisibilityItem:(NSString *)identifier toRule:(NSInteger)rule {
    if(rule<0 || rule>2 || [self protectedID:identifier])return NO;
    if([identifier hasPrefix:@"system."] && !MBSystemItems()[identifier])return NO;
    return self.rules[identifier]!=nil || self.running[identifier]!=nil || MBSystemItems()[identifier]!=nil;
}
- (void)moveVisibilityItem:(NSString *)identifier toRule:(NSInteger)rule {
    if(![self canMoveVisibilityItem:identifier toRule:rule])return;
    [self finishInteraction];self.rules[identifier]=@(rule);
    [self saveRules];[self rebuildRows];[self applyVisibility];
}
- (void)renderVisibilityLanes {
    NSArray *titles=@[@"Always Show",@"Hide",@"Always Hide"];
    for(NSUInteger rule=0;rule<self.visibilityScrolls.count;rule++){
        NSScrollView *scroll=self.visibilityScrolls[rule];MBVisibilityLane *lane=(MBVisibilityLane *)scroll.documentView;
        CGFloat previousX=scroll.contentView.bounds.origin.x;
        for(NSView *view in lane.subviews.copy)[view removeFromSuperview];
        NSMutableArray *items=[NSMutableArray new];
        for(NSDictionary *row in self.rows){NSInteger value=[self protectedID:row[@"id"]]?0:MIN(2,MAX(0,[row[@"rule"] integerValue]));if(value==(NSInteger)rule)[items addObject:row];}
        self.visibilityCounts[rule].stringValue=[NSString stringWithFormat:@"%lu item%@",(unsigned long)items.count,items.count==1?@"":@"s"];
        lane.frame=NSMakeRect(0,0,MAX(scroll.contentSize.width,items.count*76+16),scroll.contentSize.height);
        CGFloat x=8;
        for(NSDictionary *row in items){
            NSString *identifier=row[@"id"],*name=row[@"name"];BOOL locked=[self protectedID:identifier];
            MBVisibilityIcon *icon=[[MBVisibilityIcon alloc] initWithFrame:NSMakeRect(x,10,72,64)];
            icon.identifier=identifier;icon.title=name;icon.font=[NSFont systemFontOfSize:10];icon.bordered=NO;icon.imagePosition=NSImageAbove;
            NSImage *image=[[self rowIconForIdentifier:identifier name:name] copy];image.size=NSMakeSize(24,24);icon.image=image;icon.imageScaling=NSImageScaleProportionallyDown;
            icon.cell.lineBreakMode=NSLineBreakByTruncatingTail;icon.movable=!locked;
            icon.accessibilityLabel=[NSString stringWithFormat:@"%@ — %@%@",name,titles[rule],locked?@" (protected)":@""];
            icon.toolTip=[NSString stringWithFormat:@"%@\n%@",name,locked?@"Kept visible":@"Drag to another row to change visibility"];
            [lane addSubview:icon];x+=76;
        }
        if(!items.count){NSTextField *empty=[NSTextField labelWithString:self.search.stringValue.length?@"No matching items in this row":@"Drop icons here"];empty.textColor=NSColor.tertiaryLabelColor;empty.font=[NSFont systemFontOfSize:12];empty.frame=NSMakeRect(20,32,400,20);[lane addSubview:empty];}
        [scroll.contentView scrollToPoint:NSMakePoint(MIN(previousX,MAX(0,lane.frame.size.width-scroll.contentSize.width)),0)];[scroll reflectScrolledClipView:scroll.contentView];lane.needsDisplay=YES;
    }
}
- (void)controlTextDidChange:(NSNotification *)notification {[self rebuildRows];}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    if(self.compatibilityTask.running){self.stateMessage=@"Finishing iStat check before quitting…";[self updateUI];return NSTerminateCancel;}
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {[self finishInteraction];[self releaseRestriction];[self saveRules];[self log:@"STOP — menu-bar restriction released"];}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {return NO;}
@end

int main(int argc,const char *argv[]) {
    @autoreleasepool {NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;MenuBarCompact *delegate=[MenuBarCompact new];app.delegate=delegate;[app run];}
    return 0;
}
