#import <Foundation/Foundation.h>

// macOS 27 MBSystemItemIdentifier: battery=0, keyboard=4. These are
// synthetic rule keys, never application IDs passed to the menu-bar host.
static NSDictionary<NSString *,NSDictionary *> *MBSystemItems(void) {
    return @{
        @"system.battery":@{@"name":@"Battery", @"symbol":@"battery.100percent", @"systems":@[@0], @"bundles":@[]},
        @"system.input-method":@{@"name":@"Input Method", @"symbol":@"keyboard", @"systems":@[@4], @"bundles":@[@"com.apple.TextInputMenuAgent"]},
        @"system.spotlight":@{@"name":@"Spotlight", @"symbol":@"magnifyingglass", @"systems":@[], @"bundles":@[@"com.apple.Spotlight",@"com.apple.campo"]}
    };
}

static BOOL MBProtectedBundle(NSString *identifier, NSString *ownID) {
    return [identifier hasPrefix:@"com.apple."] || [identifier isEqual:ownID] || [identifier hasPrefix:@"com.bjango.istatmenus"] || [identifier isEqual:@"com.stonerl.Thaw"];
}

// mode: 0 = collapsed, 1 = reveal ordinary hidden items, 2 = show everything.
static NSDictionary *MBVisibilityPlan(NSArray<NSString *> *runningIDs, NSDictionary<NSString *,NSNumber *> *rules, NSString *ownID, NSInteger mode) {
    NSDictionary *systemItems=MBSystemItems();
    NSMutableSet *allowed=[NSMutableSet setWithArray:runningIDs];
    for(NSString *identifier in rules)if(!systemItems[identifier])[allowed addObject:identifier];
    [allowed addObjectsFromArray:@[ownID,@"com.bjango.istatmenus.status",@"com.bjango.istatmenus",@"com.apple.controlcenter",@"com.apple.systemuiserver",@"com.apple.MenuBarAgent",@"com.apple.Spotlight",@"com.apple.campo",@"com.apple.TextInputMenuAgent"]];
    NSMutableArray *systems=[@[@0,@1,@2,@3,@4,@5,@6,@7,@8] mutableCopy];
    NSUInteger excluded=0;
    for(NSString *identifier in rules){
        NSInteger rule=rules[identifier].integerValue;
        BOOL hide=(rule==1 && mode==0) || (rule==2 && mode!=2);
        if(!hide)continue;
        NSDictionary *system=systemItems[identifier];
        if(system){
            [systems removeObjectsInArray:system[@"systems"]];
            [allowed minusSet:[NSSet setWithArray:system[@"bundles"]]];
            excluded++;
        }else if(!MBProtectedBundle(identifier,ownID)){
            [allowed removeObject:identifier];excluded++;
        }
    }
    return @{@"bundles":[allowed.allObjects sortedArrayUsingSelector:@selector(compare:)],@"systems":systems,@"excluded":@(excluded)};
}

// Listing hidden items is separate from the host visibility policy. Merely
// opening the panel never grants additional menu-bar visibility.
static NSArray<NSString *> *MBPanelItems(NSArray<NSString *> *runningIDs, NSDictionary<NSString *,NSNumber *> *rules, NSString *ownID, BOOL includeAlwaysHidden) {
    NSMutableArray *items=[NSMutableArray new];
    for(NSString *identifier in rules){
        NSInteger rule=rules[identifier].integerValue;
        if(rule!=1 && !(includeAlwaysHidden && rule==2))continue;
        BOOL system=MBSystemItems()[identifier]!=nil;
        if(!system && (MBProtectedBundle(identifier,ownID) || ![runningIDs containsObject:identifier]))continue;
        [items addObject:identifier];
    }
    return items;
}
static NSDictionary *MBInteractionRules(NSDictionary *rules, NSString *selectedItem) {
    if(!selectedItem)return rules;
    NSMutableDictionary *effective=[rules mutableCopy];
    effective[selectedItem]=@0;
    return effective;
}
