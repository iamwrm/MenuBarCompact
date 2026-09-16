#import <Foundation/Foundation.h>

#import "SystemCatalog.h"

static BOOL MBProtectedBundle(NSString *identifier, NSString *ownID) {
    return [identifier hasPrefix:@"com.apple."] || [identifier isEqual:ownID] || [identifier isEqual:@"com.stonerl.Thaw"];
}

// mode: 0 = collapsed, 1 = reveal ordinary hidden items, 2 = show everything.
static NSDictionary *MBVisibilityPlan(NSArray<NSString *> *runningIDs, NSDictionary<NSString *,NSNumber *> *rules, NSString *ownID, NSInteger mode) {
    NSDictionary *systemItems=MBSystemItems();
    NSMutableSet *allowed=[NSMutableSet setWithArray:runningIDs];
    for(NSString *identifier in rules)if(![identifier hasPrefix:@"system."])[allowed addObject:identifier];
    [allowed addObjectsFromArray:@[ownID,@"com.bjango.istatmenus.status",@"com.bjango.istatmenus",@"com.apple.controlcenter",@"com.apple.systemuiserver",@"com.apple.MenuBarAgent",@"com.apple.Spotlight",@"com.apple.campo",@"com.apple.TextInputMenuAgent"]];
    for(NSDictionary *item in systemItems.allValues)[allowed addObjectsFromArray:item[@"bundles"]?:@[]];
    NSMutableArray *systems=[MBSystemCategoryIDs() mutableCopy];
    NSUInteger excluded=0;
    for(NSString *identifier in rules){
        NSInteger rule=rules[identifier].integerValue;
        BOOL hide=(rule==1 && mode==0) || (rule==2 && mode!=2);
        if(!hide)continue;
        NSDictionary *system=systemItems[identifier];
        if(system){
            if([system[@"protected"] boolValue])continue;
            [systems removeObjectsInArray:system[@"systems"]];
            [allowed minusSet:[NSSet setWithArray:system[@"bundles"]]];
            excluded++;
        }else if(![identifier hasPrefix:@"system."] && !MBProtectedBundle(identifier,ownID)){
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
        if([identifier hasPrefix:@"system."] && (!system || [MBSystemItems()[identifier][@"protected"] boolValue]))continue;
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
