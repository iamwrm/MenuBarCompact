#import "../VisibilityPolicy.h"

static void Require(BOOL passed, NSString *message) {
    if(!passed){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}
}
int main(void) {
    @autoreleasepool {
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
        Require([hidden[@"excluded"] integerValue]==4,@"Only requested items and the ordinary app should be excluded");
        Require(![hidden[@"systems"] containsObject:@4],@"Input Method keyboard category must be removed");
        for(NSString *identifier in @[@"com.apple.TextInputMenuAgent",@"com.apple.campo",@"com.apple.Spotlight",@"example.hidden"])
            Require(![hidden[@"bundles"] containsObject:identifier],[@"Unexpected allowed item: " stringByAppendingString:identifier]);
        for(NSString *identifier in @[own,@"com.bjango.istatmenus.status",@"com.apple.MenuBarAgent",@"com.apple.controlcenter"])
            Require([hidden[@"bundles"] containsObject:identifier],[@"Protected item removed: " stringByAppendingString:identifier]);
        for(NSString *identifier in MBSystemItems())
            Require(![hidden[@"bundles"] containsObject:identifier],@"Synthetic rule keys must not reach the app allowlist");

        NSDictionary *revealed=MBVisibilityPlan(running,rules,own,1);
        Require([revealed[@"systems"] isEqual:baseline[@"systems"]],@"Normal reveal must restore Battery and Input Method");
        Require([revealed[@"bundles"] containsObject:@"com.apple.TextInputMenuAgent"],@"Normal reveal must restore Input Method's agent");
        Require([revealed[@"bundles"] containsObject:@"example.hidden"],@"Normal reveal must restore ordinary hidden apps");
        Require(![revealed[@"bundles"] containsObject:@"com.apple.campo"] && [revealed[@"excluded"] integerValue]==1,@"Always-hidden Spotlight must stay hidden during normal reveal");

        NSDictionary *everything=MBVisibilityPlan(running,rules,own,2);
        Require([everything[@"excluded"] integerValue]==0,@"Show everything must release all configured exclusions");
        Require([everything[@"systems"] isEqual:baseline[@"systems"]],@"Show everything must restore all system categories");
        Require([everything[@"bundles"] containsObject:@"com.apple.campo"] && [everything[@"bundles"] containsObject:@"com.apple.Spotlight"],@"Show everything must restore both Spotlight identities");
        puts("Visibility policy tests passed: system-only activation, app isolation, protected items, reveal modes, and synthetic IDs.");
    }
    return 0;
}
