#import "../VisibilityPolicy.h"

static void Require(BOOL passed, NSString *message) {
    if(!passed){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}
}
int main(void) {
    @autoreleasepool {
        NSMutableArray *runtime=[NSMutableArray new];
        NSArray *tokens=@[@"battery",@"bluetooth",@"clock",@"displays",@"keyboard",@"volume",@"wifi",@"screenMirroring",@"primaryBentoBox"];
        for(NSUInteger i=0;i<tokens.count;i++)[runtime addObject:@{@"token":tokens[i],@"raw":@(i)}];
        NSDictionary *spotlight=@{@"key":@"system.spotlight",@"metadata":@{@"name":@"Spotlight",@"systems":@[],@"bundles":@[@"com.apple.Spotlight",@"com.apple.campo"]}};
        MBSetSystemItems(MBBuildSystemCatalog(runtime,@[],@[spotlight]));
        NSString *own=@"io.github.iamwrm.MenuBarCompact";
        NSArray *running=@[own,@"com.apple.TextInputMenuAgent",@"com.apple.campo",@"com.apple.Spotlight",@"com.bjango.istatmenus.status",@"example.hidden"];
        NSDictionary *baseline=MBVisibilityPlan(running,@{},own,0);
        NSDictionary *battery=MBVisibilityPlan(running,@{@"system.battery":@1},own,0);
        Require([battery[@"excluded"] integerValue]==1,@"A system-only rule must activate a restriction");
        Require([battery[@"bundles"] isEqual:baseline[@"bundles"]],@"Battery must not exclude any app");
        Require(![battery[@"systems"] containsObject:@0],@"Battery category must be removed");
        Require([battery[@"systems"] containsObject:@2] && [battery[@"systems"] containsObject:@8],@"Clock and Control Center must remain allowed");
        Require(![battery[@"systems"] isEqual:baseline[@"systems"]],@"Changing only Battery must invalidate the system allowlist");

        NSDictionary *rules=@{@"system.battery":@1,@"system.input-method":@1,@"system.spotlight":@2,@"example.hidden":@1,@"com.apple.MenuBarAgent":@2,@"com.bjango.istatmenus.status":@2,own:@2};
        NSDictionary *hidden=MBVisibilityPlan(running,rules,own,0);
        Require([hidden[@"excluded"] integerValue]==5,@"Requested system items, iStat, and the ordinary app should be excluded");
        Require(![hidden[@"systems"] containsObject:@4],@"Input Method keyboard category must be removed");
        for(NSString *identifier in @[@"com.apple.TextInputMenuAgent",@"com.apple.campo",@"com.apple.Spotlight",@"example.hidden",@"com.bjango.istatmenus.status"])
            Require(![hidden[@"bundles"] containsObject:identifier],[@"Unexpected allowed item: " stringByAppendingString:identifier]);
        for(NSString *identifier in @[own,@"com.apple.MenuBarAgent",@"com.apple.controlcenter"])
            Require([hidden[@"bundles"] containsObject:identifier],[@"Protected item removed: " stringByAppendingString:identifier]);
        for(NSString *identifier in MBSystemItems())
            Require(![hidden[@"bundles"] containsObject:identifier],@"Synthetic rule keys must not reach the app allowlist");

        NSDictionary *revealed=MBVisibilityPlan(running,rules,own,1);
        Require([revealed[@"systems"] isEqual:baseline[@"systems"]],@"Normal reveal must restore Battery and Input Method");
        Require([revealed[@"bundles"] containsObject:@"com.apple.TextInputMenuAgent"],@"Normal reveal must restore Input Method's agent");
        Require([revealed[@"bundles"] containsObject:@"example.hidden"],@"Normal reveal must restore ordinary hidden apps");
        Require(![revealed[@"bundles"] containsObject:@"com.apple.campo"] && [revealed[@"excluded"] integerValue]==2,@"Always-hidden Spotlight and iStat must stay hidden during normal reveal");

        NSDictionary *everything=MBVisibilityPlan(running,rules,own,2);
        Require([everything[@"excluded"] integerValue]==0,@"Show everything must release all configured exclusions");
        Require([everything[@"systems"] isEqual:baseline[@"systems"]],@"Show everything must restore all system categories");
        Require([everything[@"bundles"] containsObject:@"com.apple.campo"] && [everything[@"bundles"] containsObject:@"com.apple.Spotlight"],@"Show everything must restore both Spotlight identities");
        NSMutableDictionary *panelRules=[rules mutableCopy];panelRules[@"example.closed"]=@1;
        NSArray *panel=MBPanelItems(running,panelRules,own,NO);
        Require(panel.count==3 && [panel containsObject:@"example.hidden"] && [panel containsObject:@"system.battery"],@"Ordinary panel lists running hidden apps and system items only");
        NSArray *allPanel=MBPanelItems(running,panelRules,own,YES);
        Require(allPanel.count==5 && [allPanel containsObject:@"system.spotlight"] && [allPanel containsObject:@"com.bjango.istatmenus.status"],@"Expanded panel includes Always hide without protected or closed apps");
        Require([MBVisibilityPlan(running,panelRules,own,0) isEqual:MBVisibilityPlan(running,MBInteractionRules(panelRules,nil),own,0)],@"Opening the panel must not reveal anything");
        NSDictionary *one=MBVisibilityPlan(running,MBInteractionRules(rules,@"system.battery"),own,0);
        Require([one[@"systems"] containsObject:@0] && ![one[@"systems"] containsObject:@4],@"Opening Battery must not reveal Input Method");
        Require(![one[@"bundles"] containsObject:@"example.hidden"] && ![one[@"bundles"] containsObject:@"com.apple.campo"],@"Opening one system menu must keep other apps hidden");
        NSDictionary *appOne=MBVisibilityPlan(running,MBInteractionRules(rules,@"example.hidden"),own,0);
        Require([appOne[@"bundles"] containsObject:@"example.hidden"] && [appOne[@"systems"] isEqual:hidden[@"systems"]],@"Opening one app must preserve hidden system controls");
        Require([rules[@"example.hidden"] isEqual:@1] && [rules[@"system.battery"] isEqual:@1],@"Temporary activation must never change saved rules");
        NSString *istat=@"com.bjango.istatmenus.status";
        Require(!MBProtectedBundle(istat,own),@"iStat must accept all visibility choices");
        Require([baseline[@"bundles"] containsObject:istat],@"iStat remains visible by default");
        NSDictionary *istatRules=@{istat:@1,@"example.hidden":@1};
        Require(![MBVisibilityPlan(running,istatRules,own,0)[@"bundles"] containsObject:istat],@"Hide must exclude the iStat status helper");
        Require([MBPanelItems(running,istatRules,own,NO) containsObject:istat],@"Hidden iStat must appear in the normal second row");
        Require(![MBPanelItems(running,@{istat:@2},own,NO) containsObject:istat],@"Always-hidden iStat must stay out of the normal second row");
        Require([MBPanelItems(running,@{istat:@2},own,YES) containsObject:istat],@"Option-click must include always-hidden iStat");
        NSDictionary *istatActive=MBVisibilityPlan(running,MBInteractionRules(istatRules,istat),own,0);
        Require([istatActive[@"bundles"] containsObject:istat] && ![istatActive[@"bundles"] containsObject:@"example.hidden"],@"Opening iStat must only temporarily reveal its helper");
        Require([istatRules[istat] isEqual:@1],@"Opening iStat must preserve the saved Hide rule");
        Require([MBVisibilityPlan(running,@{istat:@0},own,0)[@"bundles"] containsObject:istat],@"Always Show must restore the iStat helper");
        [runtime addObject:@{@"token":@"futureWidget",@"raw":@42}];
        NSArray *plugins=@[@{@"bundle":@"com.apple.menuextra.TimeMachine",@"name":@"Time Machine",@"path":@"/fixture/TimeMachine.menu"},@{@"bundle":@"com.apple.menuextra.NewExtra",@"name":@"New Extra"}];
        MBSetSystemItems(MBBuildSystemCatalog(runtime,plugins,@[spotlight]));
        NSDictionary *autoBaseline=MBVisibilityPlan(running,@{},own,0);
        Require([autoBaseline[@"systems"] containsObject:@42],@"Unknown new runtime category must be allowed without a code change");
        Require([autoBaseline[@"bundles"] containsObject:@"com.apple.menuextra.TimeMachine"],@"Installed extras must be visible by default even without a separate running app");
        NSString *tm=@"system.extra.com.apple.menuextra.TimeMachine";
        NSDictionary *tmHidden=MBVisibilityPlan(running,@{tm:@1},own,0);
        Require(![tmHidden[@"bundles"] containsObject:@"com.apple.menuextra.TimeMachine"] && [tmHidden[@"systems"] isEqual:autoBaseline[@"systems"]],@"Hiding a discovered plug-in must remove only its bundle");
        Require([tmHidden[@"bundles"] containsObject:@"com.apple.menuextra.NewExtra"],@"Other discovered extras remain allowed");
        Require([MBPanelItems(running,@{tm:@1},own,NO) containsObject:tm],@"A hosted menu extra has no separate app PID but must be available in the second row");
        NSDictionary *future=MBVisibilityPlan(running,@{@"system.futureWidget":@1},own,0);
        Require(![future[@"systems"] containsObject:@42],@"New categories must be configurable without adding a numeric constant");
        NSDictionary *orphan=MBVisibilityPlan(running,@{@"system.retiredWidget":@1},own,0);
        Require(![orphan[@"bundles"] containsObject:@"system.retiredWidget"] && [orphan[@"excluded"] intValue]==0,@"Saved orphan synthetic IDs must never reach the host or hide unrelated items");
        NSDictionary *protected=MBVisibilityPlan(running,@{@"system.clock":@1,@"system.primaryBentoBox":@2},own,0);
        Require([protected[@"excluded"] intValue]==0,@"Clock and Control Center remain protected even under saved rules");
        Require([MBSystemItems()[@"system.input-method"][@"systems"] containsObject:@4],@"Existing Input Method preferences retain their stable key");
        // Plug-in identity and its live owner are different on macOS 27.
        NSArray *exclusivePlugins=@[@{@"bundle":@"com.apple.menuextra.TimeMachine",@"name":@"Time Machine",@"host":@"com.apple.systemuiserver"}];
        MBSetSystemItems(MBBuildSystemCatalog(runtime,exclusivePlugins,@[spotlight]));
        NSDictionary *hostHidden=MBVisibilityPlan(running,@{tm:@1,@"example.hidden":@1},own,0);
        Require(![hostHidden[@"bundles"] containsObject:@"com.apple.systemuiserver"],@"Hide must exclude the verified exclusive legacy host as well as the plug-in");
        Require([hostHidden[@"bundles"] containsObject:@"com.apple.MenuBarAgent"] && [hostHidden[@"bundles"] containsObject:@"com.apple.controlcenter"],@"Legacy hiding must preserve the modern system hosts");
        NSDictionary *hostRevealed=MBVisibilityPlan(running,MBInteractionRules(@{tm:@1,@"example.hidden":@1},tm),own,0);
        Require([hostRevealed[@"bundles"] containsObject:@"com.apple.systemuiserver"] && ![hostRevealed[@"bundles"] containsObject:@"example.hidden"],@"Opening Time Machine temporarily restores its exclusive host only");
        Require(![MBVisibilityPlan(running,@{tm:@2},own,0)[@"bundles"] containsObject:@"com.apple.systemuiserver"],@"Always Hide also excludes the verified host");
        Require([MBVisibilityPlan(running,@{tm:@0},own,0)[@"bundles"] containsObject:@"com.apple.systemuiserver"],@"Always Show permits the host again");
        MBSetSystemItems(MBBuildSystemCatalog(runtime,plugins,@[spotlight]));
        Require([MBVisibilityPlan(running,@{tm:@1},own,0)[@"bundles"] containsObject:@"com.apple.systemuiserver"],@"A shared or unknown legacy host must remain visible");
        puts("Visibility policy tests passed, including panel filtering and isolated menu activation.");
    }
    return 0;
}
