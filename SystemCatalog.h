#import <Foundation/Foundation.h>

static NSDictionary *MBCurrentSystemCatalog;
static NSDictionary<NSString *,NSDictionary *> *MBSystemItems(void) {return MBCurrentSystemCatalog?:@{};}
static void MBSetSystemItems(NSDictionary *items) {MBCurrentSystemCatalog=[items copy];}
static NSString *MBReadableItemName(NSString *token) {
    NSUInteger capitals=0;for(NSUInteger i=0;i<token.length;i++)if([NSCharacterSet.uppercaseLetterCharacterSet characterIsMember:[token characterAtIndex:i]])capitals++;
    if(capitals>token.length/2)return token;
    NSRegularExpression *acronyms=[NSRegularExpression regularExpressionWithPattern:@"([A-Z]+)([A-Z][a-z])" options:0 error:nil];
    token=[acronyms stringByReplacingMatchesInString:token options:0 range:NSMakeRange(0,token.length) withTemplate:@"$1 $2"];
    NSRegularExpression *words=[NSRegularExpression regularExpressionWithPattern:@"([a-z0-9])([A-Z])" options:0 error:nil];
    NSString *name=[words stringByReplacingMatchesInString:token options:0 range:NSMakeRange(0,token.length) withTemplate:@"$1 $2"];
    return [name stringByReplacingCharactersInRange:NSMakeRange(0,MIN(1,name.length)) withString:[[name substringToIndex:MIN(1,name.length)] uppercaseString]];
}
// Aliases preserve pre-discovery preferences; names/icons only affect presentation.
// Category membership and numeric IDs come from macOS, never this map.
static NSDictionary *MBBuildSystemCatalog(NSArray<NSDictionary *> *runtime,NSArray<NSDictionary *> *plugins,NSArray<NSDictionary *> *specials) {
    NSDictionary *names=@{@"keyboard":@"Input Method",@"volume":@"Sound",@"wifi":@"Wi-Fi",@"primaryBentoBox":@"Control Center"};
    NSDictionary *symbols=@{@"battery":@"battery.100percent",@"bluetooth":@"antenna.radiowaves.left.and.right",@"clock":@"clock",@"displays":@"display",@"keyboard":@"character",@"volume":@"speaker.wave.2",@"wifi":@"wifi",@"screenMirroring":@"rectangle.on.rectangle",@"primaryBentoBox":@"switch.2"};
    NSMutableDictionary *catalog=[NSMutableDictionary new];
    for(NSDictionary *item in runtime){
        NSString *token=item[@"token"];NSNumber *raw=item[@"raw"];
        if(![token isKindOfClass:NSString.class] || !token.length || ![raw isKindOfClass:NSNumber.class])continue;
        NSString *key=[@"system." stringByAppendingString:[token isEqual:@"keyboard"]?@"input-method":token];
        NSString *ax=[@"com.apple.menuextra." stringByAppendingString:[token isEqual:@"primaryBentoBox"]?@"controlcenter":token.lowercaseString];
        BOOL protected=[token isEqual:@"clock"] || [token isEqual:@"primaryBentoBox"];
        catalog[key]=@{@"name":names[token]?:MBReadableItemName(token),@"symbol":symbols[token]?:@"menubar.rectangle",@"systems":@[raw],@"bundles":[token isEqual:@"keyboard"]?@[@"com.apple.TextInputMenuAgent"]:@[],@"axIdentifiers":@[ax],@"protected":@(protected),@"source":@"macOS category"};
    }
    for(NSDictionary *plugin in plugins){
        NSString *bundle=plugin[@"bundle"],*name=plugin[@"name"];
        if(![bundle hasPrefix:@"com.apple.menuextra."] || !name.length)continue;
        // AirPort is a legacy plug-in for the separately published Wi-Fi category.
        if([bundle isEqual:@"com.apple.menuextra.airport"] && catalog[@"system.wifi"])continue;
        NSString *key=[@"system.extra." stringByAppendingString:bundle];
        NSString *symbol=@{@"com.apple.menuextra.TimeMachine":@"clock.arrow.circlepath",@"com.apple.menuextra.eject":@"eject",@"com.apple.menuextra.vpn":@"network"}[bundle]?:@"menubar.rectangle";
        catalog[key]=@{@"name":name,@"symbol":symbol,@"systems":@[],@"bundles":@[bundle],@"axIdentifiers":@[bundle],@"axName":name,@"bundlePath":plugin[@"path"]?:@"",@"hostBundle":plugin[@"host"]?:@"",@"protected":@NO,@"source":@"Installed menu extra"};
    }
    for(NSDictionary *item in specials)if(item[@"key"] && item[@"metadata"])catalog[item[@"key"]]=item[@"metadata"];
    return catalog;
}
static NSArray *MBSystemCategoryIDs(void) {
    NSMutableSet *ids=[NSMutableSet new];for(NSDictionary *item in MBSystemItems().allValues)[ids addObjectsFromArray:item[@"systems"]?:@[]];
    return [ids.allObjects sortedArrayUsingSelector:@selector(compare:)];
}
