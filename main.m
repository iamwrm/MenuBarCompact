#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dlfcn.h>

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

@interface MenuBarCompact : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate>
@property NSStatusItem *statusItem;
@property NSWindow *window;
@property NSTextField *summaryLabel, *compatibilityLabel, *loginLabel;
@property NSButton *loginButton, *autoHideButton, *takeOverButton, *toggleButton, *allAppsButton;
@property NSSearchField *search;
@property NSTableView *table;
@property NSMutableDictionary<NSString *,NSNumber *> *rules;
@property NSMutableDictionary<NSString *,NSString *> *names;
@property NSArray<NSDictionary *> *rows;
@property NSDictionary<NSString *,NSRunningApplication *> *running;
@property id assertion;
@property NSArray *lastAllowlist;
@property NSTimer *rehideTimer, *maintenance, *processWatch;
@property NSTask *compatibilityTask;
@property NSUInteger generation, refreshGeneration;
@property VisibilityMode mode;
@property BOOL ready, menuOpen, paused, activationPending;
@property NSString *stateMessage, *compatibilityMessage;
@property NSURL *logURL;
@end

@implementation MenuBarCompact
- (void)log:(NSString *)message {
    NSString *line=[NSString stringWithFormat:@"%@ %@\n",NSDate.date,message];
    NSLog(@"%@",message);
    NSFileHandle *file=[NSFileHandle fileHandleForWritingToURL:self.logURL error:nil];
    if(file){[file seekToEndOfFile];[file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[file closeFile];}
}
- (BOOL)protectedID:(NSString *)identifier {
    return [identifier hasPrefix:@"com.apple."] || [identifier isEqual:OwnID] || [identifier hasPrefix:@"com.bjango.istatmenus"] || [identifier isEqual:ThawID];
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
    [self log:@"START MenuBarCompact 0.1.0"];
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
- (void)maintain:(id)sender {[self refreshApps];[self checkCompatibility:nil];}
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
- (void)rebuildRows {
    NSMutableSet *ids=[NSMutableSet setWithArray:self.rules.allKeys];
    [ids addObject:IStatID];
    for(NSRunningApplication *app in self.running.allValues){
        if(self.allAppsButton.state==NSControlStateValueOn && ![self protectedID:app.bundleIdentifier] && (app.activationPolicy!=NSApplicationActivationPolicyProhibited || self.rules[app.bundleIdentifier]))[ids addObject:app.bundleIdentifier];
    }
    NSString *query=self.search.stringValue?:@"";
    NSMutableArray *rows=[NSMutableArray new];
    for(NSString *identifier in ids){
        NSString *name=self.names[identifier];
        if(!name){NSURL *url=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];name=url?[[NSFileManager.defaultManager displayNameAtPath:url.path] stringByDeletingPathExtension]:identifier;}
        if([identifier isEqual:IStatID])name=@"iStat Menus";
        if(query.length && [name rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound && [identifier rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound)continue;
        [rows addObject:@{@"id":identifier,@"name":name?:identifier}];
    }
    self.rows=[rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
    [self.table reloadData];
}
- (void)releaseRestriction {
    self.generation++;self.activationPending=NO;
    if(self.assertion){[self.assertion invalidate];self.assertion=nil;[self log:@"RELEASE visibility restriction"];}
    self.lastAllowlist=nil;
}
- (void)applyVisibility {
    if(self.paused)return;
    if(self.running[ThawID]){[self releaseRestriction];self.stateMessage=@"Paused while Thaw is running";[self updateUI];return;}
    if(!self.ready){[self releaseRestriction];self.stateMessage=@"Waiting for iStat compatibility";[self updateUI];return;}
    NSMutableSet *allowed=[NSMutableSet setWithArray:self.running.allKeys];
    [allowed addObjectsFromArray:self.rules.allKeys];
    [allowed addObjectsFromArray:@[OwnID,IStatID,@"com.bjango.istatmenus",@"com.apple.controlcenter",@"com.apple.systemuiserver",@"com.apple.MenuBarAgent",@"com.apple.Spotlight",@"com.apple.campo",@"com.apple.TextInputMenuAgent"]];
    NSUInteger excluded=0;
    for(NSString *identifier in self.rules){
        NSInteger rule=self.rules[identifier].integerValue;
        if(![self protectedID:identifier] && ((rule==1 && self.mode==Collapsed) || (rule==2 && self.mode!=Everything))){[allowed removeObject:identifier];excluded++;}
    }
    if(self.mode==Everything || excluded==0){[self releaseRestriction];self.stateMessage=self.mode==Everything?@"Showing all apps":@"All configured apps are visible";[self updateUI];return;}
    NSArray *bundles=[allowed.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if(self.assertion && [bundles isEqual:self.lastAllowlist]){
        if(!self.activationPending)self.stateMessage=self.mode==Collapsed?@"Hidden apps are tucked away":@"Showing hidden apps";
        [self updateUI];return;
    }
    [self releaseRestriction];
    Class configuration=NSClassFromString(@"MBAssessmentModeConfiguration"), assertion=NSClassFromString(@"MBAssessmentModeAssertion");
    if(!configuration || !assertion || ![configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)] || ![assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)] || ![assertion instancesRespondToSelector:@selector(invalidate)]){
        self.stateMessage=@"Hiding is unavailable on this macOS version";[self updateUI];return;
    }
    @try {
        id config=[[configuration alloc] initWithAllowedSystemItems:@[@0,@1,@2,@3,@4,@5,@6,@7,@8] allowedBundleIdentifiers:bundles];
        self.assertion=[assertion new];
        if(!config || !self.assertion){[self releaseRestriction];self.stateMessage=@"Could not start hiding; all apps remain visible";[self updateUI];return;}
        self.lastAllowlist=bundles;self.activationPending=YES;
        NSUInteger revision=self.generation;
        self.stateMessage=@"Updating menu bar…";
        [self.assertion activateWithConfiguration:config completionHandler:^(NSError *error){
            dispatch_async(dispatch_get_main_queue(),^{
                if(revision!=self.generation)return;
                self.activationPending=NO;
                if(error){[self releaseRestriction];self.stateMessage=@"Could not hide apps; all apps remain visible";[self log:[NSString stringWithFormat:@"ACTIVATE failed: %@",error]];}
                else {self.stateMessage=self.mode==Collapsed?@"Hidden apps are tucked away":@"Showing hidden apps";[self log:[NSString stringWithFormat:@"ACTIVATE success mode=%ld excluded=%lu iStat=allowed",(long)self.mode,(unsigned long)excluded]];}
                [self updateUI];
            });
        }];
        // Do not retain an uncertain assertion indefinitely if the private host stops replying.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(revision==self.generation && self.activationPending){[self releaseRestriction];self.stateMessage=@"Menu bar did not respond; hiding is paused";[self updateUI];}
        });
    } @catch(NSException *exception){[self releaseRestriction];self.stateMessage=@"Hiding is unavailable; all apps remain visible";[self log:exception.reason];}
    [self updateUI];
}
- (void)setModeAndApply:(VisibilityMode)mode {
    self.mode=mode;[self.rehideTimer invalidate];self.rehideTimer=nil;
    if(mode!=Collapsed && [NSUserDefaults.standardUserDefaults boolForKey:@"AutoRehide"]){
        self.rehideTimer=[NSTimer timerWithTimeInterval:15 target:self selector:@selector(autoRehide:) userInfo:nil repeats:NO];
        [NSRunLoop.mainRunLoop addTimer:self.rehideTimer forMode:NSRunLoopCommonModes];
    }
    [self applyVisibility];
}
- (void)autoRehide:(id)sender {
    if(self.menuOpen){self.rehideTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(autoRehide:) userInfo:nil repeats:NO];return;}
    [self setModeAndApply:Collapsed];
}
- (void)toggle:(id)sender {[self setModeAndApply:self.mode==Collapsed?Revealed:Collapsed];}
- (void)showAll:(id)sender {[self setModeAndApply:Everything];}
- (void)hide:(id)sender {[self setModeAndApply:Collapsed];}
- (void)statusClick:(id)sender {
    NSEvent *event=NSApp.currentEvent;
    if(event.type==NSEventTypeRightMouseUp){
        NSMenu *menu=[NSMenu new];menu.delegate=self;
        NSMenuItem *state=[menu addItemWithTitle:self.stateMessage?:@"MenuBarCompact" action:nil keyEquivalent:@""];state.enabled=NO;
        [menu addItem:NSMenuItem.separatorItem];
        for(NSArray *entry in @[@[self.mode==Collapsed?@"Show hidden apps":@"Hide apps again",NSStringFromSelector(@selector(toggle:))],@[@"Show everything",NSStringFromSelector(@selector(showAll:))],@[@"Settings…",NSStringFromSelector(@selector(showSettings:))]]){
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
    [self setModeAndApply:self.mode];
}
- (void)takeOver:(id)sender {
    [self.running[ThawID] terminate];self.stateMessage=@"Waiting for Thaw to quit…";[self updateUI];
}
- (void)openDiagnostics:(id)sender {[NSWorkspace.sharedWorkspace openURL:self.logURL];}
- (void)toggleAppScope:(id)sender {self.search.placeholderString=self.allAppsButton.state==NSControlStateValueOn?@"Find an app":@"Find a configured app";[self rebuildRows];}
- (void)updateUI {
    self.summaryLabel.stringValue=self.stateMessage?:@"Starting…";
    self.compatibilityLabel.stringValue=self.compatibilityMessage?:@"Checking iStat…";
    self.takeOverButton.hidden=self.running[ThawID]==nil;
    self.toggleButton.title=self.mode==Collapsed?@"Show hidden apps":@"Hide apps again";
    NSImage *image=[NSImage imageWithSystemSymbolName:self.mode==Collapsed?@"ellipsis.circle":@"chevron.left.circle" accessibilityDescription:@"MenuBarCompact"];
    image.template=YES;self.statusItem.button.image=image;
    self.statusItem.button.toolTip=[NSString stringWithFormat:@"MenuBarCompact — %@\nClick to reveal/hide. Right-click for settings. Option-click shows everything.",self.stateMessage?:@""];
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
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,820,680) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"MenuBarCompact";self.window.releasedWhenClosed=NO;
    NSTextField *title=[self label:@"A quieter menu bar." frame:NSMakeRect(28,615,740,35) size:26 secondary:NO];title.font=[NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    self.summaryLabel=[self label:@"Starting…" frame:NSMakeRect(28,585,740,24) size:14 secondary:YES];
    self.toggleButton=[self button:@"Show hidden apps" action:@selector(toggle:) frame:NSMakeRect(24,540,180,32)];
    [self button:@"Show everything" action:@selector(showAll:) frame:NSMakeRect(210,540,160,32)];
    self.takeOverButton=[self button:@"Quit Thaw and start" action:@selector(takeOver:) frame:NSMakeRect(585,540,210,32)];
    self.search=[[NSSearchField alloc] initWithFrame:NSMakeRect(28,493,530,30)];self.search.placeholderString=@"Find a configured app";self.search.delegate=self;[self.window.contentView addSubview:self.search];
    self.allAppsButton=[NSButton checkboxWithTitle:@"Show all running apps" target:self action:@selector(toggleAppScope:)];self.allAppsButton.frame=NSMakeRect(580,496,214,24);[self.window.contentView addSubview:self.allAppsButton];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(28,188,764,294)];scroll.hasVerticalScroller=YES;scroll.borderType=NSBezelBorder;
    self.table=[[NSTableView alloc] initWithFrame:scroll.bounds];self.table.delegate=self;self.table.dataSource=self;self.table.rowHeight=54;self.table.usesAlternatingRowBackgroundColors=YES;self.table.selectionHighlightStyle=NSTableViewSelectionHighlightStyleNone;
    for(NSArray *spec in @[@[@"app",@"App",@450],@[@"running",@"Status",@85],@[@"rule",@"Visibility",@205]]){NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:spec[0]];column.title=spec[1];column.width=[spec[2] doubleValue];[self.table addTableColumn:column];}
    scroll.documentView=self.table;[self.window.contentView addSubview:scroll];
    [self label:@"Click reveals apps marked Hide. Show everything also reveals Always hide." frame:NSMakeRect(28,156,765,21) size:12 secondary:YES];
    self.autoHideButton=[NSButton checkboxWithTitle:@"Hide again after 15 seconds" target:self action:@selector(toggleAutoHide:)];self.autoHideButton.frame=NSMakeRect(28,122,320,24);self.autoHideButton.state=[NSUserDefaults.standardUserDefaults boolForKey:@"AutoRehide"]?1:0;[self.window.contentView addSubview:self.autoHideButton];
    self.loginButton=[NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(toggleLogin:)];self.loginButton.frame=NSMakeRect(420,122,350,24);[self.window.contentView addSubview:self.loginButton];
    self.loginLabel=[self label:@"" frame:NSMakeRect(420,96,370,22) size:11 secondary:YES];
    self.compatibilityLabel=[self label:@"" frame:NSMakeRect(28,60,760,22) size:12 secondary:YES];
    [self button:@"Check iStat" action:@selector(checkCompatibility:) frame:NSMakeRect(23,18,120,30)];
    [self button:@"Diagnostics…" action:@selector(openDiagnostics:) frame:NSMakeRect(150,18,145,30)];
    [self label:@"MenuBarCompact 0.1 · per-app visibility" frame:NSMakeRect(525,23,270,22) size:11 secondary:YES];
    [self.window center];[self rebuildRows];[self updateUI];
}
- (void)showSettings:(id)sender {if(!self.window)[self buildWindow];[self refreshApps];[self updateUI];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {[self showSettings:nil];return YES;}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {return self.rows.count;}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)index {
    NSDictionary *row=self.rows[index];NSString *identifier=row[@"id"];
    if([column.identifier isEqual:@"rule"]){
        NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,10,195,30) pullsDown:NO];
        [popup addItemsWithTitles:@[@"Always show",@"Hide",@"Always hide"]];[popup selectItemAtIndex:MIN(2,MAX(0,self.rules[identifier].integerValue))];
        popup.identifier=identifier;popup.target=self;popup.action=@selector(ruleChanged:);popup.enabled=![self protectedID:identifier];popup.accessibilityLabel=[@"Visibility for " stringByAppendingString:row[@"name"]];return popup;
    }
    if([column.identifier isEqual:@"running"]){NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,80,54)];NSTextField *state=[NSTextField labelWithString:self.running[identifier]?@"Running":@"Closed"];state.frame=NSMakeRect(0,18,80,18);state.textColor=NSColor.secondaryLabelColor;state.font=[NSFont systemFontOfSize:11];[view addSubview:state];return view;}
    NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,440,54)];
    NSImageView *icon=[[NSImageView alloc] initWithFrame:NSMakeRect(8,11,30,30)];icon.image=self.running[identifier].icon?:[NSImage imageWithSystemSymbolName:@"app" accessibilityDescription:nil];[view addSubview:icon];
    NSTextField *name=[NSTextField labelWithString:row[@"name"]];name.frame=NSMakeRect(48,28,385,20);name.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];[view addSubview:name];
    NSTextField *bundle=[NSTextField labelWithString:identifier];bundle.frame=NSMakeRect(48,8,385,18);bundle.font=[NSFont systemFontOfSize:10];bundle.textColor=NSColor.secondaryLabelColor;bundle.lineBreakMode=NSLineBreakByTruncatingMiddle;[view addSubview:bundle];return view;
}
- (void)ruleChanged:(NSPopUpButton *)sender {
    if([self protectedID:sender.identifier])return;
    self.rules[sender.identifier]=@(sender.indexOfSelectedItem);[self saveRules];[self applyVisibility];
}
- (void)controlTextDidChange:(NSNotification *)notification {[self rebuildRows];}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    if(self.compatibilityTask.running){self.stateMessage=@"Finishing iStat check before quitting…";[self updateUI];return NSTerminateCancel;}
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {[self releaseRestriction];[self saveRules];[self log:@"STOP — menu-bar restriction released"];}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {return NO;}
@end

int main(int argc,const char *argv[]) {
    @autoreleasepool {NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;MenuBarCompact *delegate=[MenuBarCompact new];app.delegate=delegate;[app run];}
    return 0;
}
