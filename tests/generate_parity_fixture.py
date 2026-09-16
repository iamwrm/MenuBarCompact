#!/usr/bin/env python3
"""Rebuild the Swift regression oracle from the immutable pre-migration source.
Run from the repository root. The legacy implementation is never linked into the app.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

BASELINE = '66eabab47f917d16c966edfde720ac5656ff4ecd'
GENERATOR = r'''
#import "VisibilityPolicy.h"
int main(void) {@autoreleasepool {
NSArray *tokens=@[@"battery",@"bluetooth",@"clock",@"displays",@"keyboard",@"volume",@"wifi",@"screenMirroring",@"primaryBentoBox",@"futureWidget"];
NSMutableArray *runtime=[NSMutableArray new];for(NSUInteger i=0;i<tokens.count;i++)[runtime addObject:@{@"token":tokens[i],@"raw":@(i==9?42:i)}];
NSArray *plugins=@[@{@"bundle":@"com.apple.menuextra.TimeMachine",@"name":@"Time Machine",@"path":@"/fixture/TimeMachine.menu",@"host":@"com.apple.systemuiserver"},@{@"bundle":@"com.apple.menuextra.NewExtra",@"name":@"New Extra"}];
NSDictionary *special=@{@"key":@"system.spotlight",@"metadata":@{@"name":@"Spotlight",@"systems":@[],@"bundles":@[@"com.apple.Spotlight",@"com.apple.campo"]}};
MBSetSystemItems(MBBuildSystemCatalog(runtime,plugins,@[special]));
NSString *own=@"io.github.iamwrm.MenuBarCompact";
NSArray *running=@[own,@"example.hidden",@"example.other",@"com.bjango.istatmenus.status",@"com.apple.MenuBarAgent",@"com.apple.campo",@"com.apple.TextInputMenuAgent"];
NSArray *ids=@[@"example.hidden",@"example.other",@"example.closed",@"com.bjango.istatmenus.status",@"com.apple.MenuBarAgent",own,@"system.battery",@"system.input-method",@"system.spotlight",@"system.clock",@"system.primaryBentoBox",@"system.futureWidget",@"system.retiredWidget",@"system.extra.com.apple.menuextra.TimeMachine"];
uint64_t state=0x4D4243;
for(NSUInteger index=0;index<512;index++){
    NSMutableDictionary *rules=[NSMutableDictionary new];
    for(NSString *identifier in ids){state=state*6364136223846793005ULL+1442695040888963407ULL;NSUInteger value=(state>>32)%6;if(value)rules[identifier]=@((NSInteger)value-2);}
    for(NSInteger mode=0;mode<3;mode++){
        NSArray *output=@[MBVisibilityPlan(running,rules,own,mode),[MBPanelItems(running,rules,own,NO) sortedArrayUsingSelector:@selector(compare:)],[MBPanelItems(running,rules,own,YES) sortedArrayUsingSelector:@selector(compare:)],MBVisibilityPlan(running,MBInteractionRules(rules,ids[index%ids.count]),own,mode)];
        NSData *json=[NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingSortedKeys error:nil];fwrite(json.bytes,1,json.length,stdout);putchar('\n');
    }
}
}return 0;}
'''
if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for filename in ('VisibilityPolicy.h', 'SystemCatalog.h'):
            (root / filename).write_bytes(subprocess.check_output(['git', 'show', f'{BASELINE}:{filename}']))
        (root / 'main.m').write_text(GENERATOR)
        subprocess.run(['xcrun', 'clang', '-O2', '-fobjc-arc', '-framework', 'Foundation', str(root / 'main.m'), '-o', str(root / 'oracle')], check=True)
        output = subprocess.check_output([str(root / 'oracle')])
        fixture = {'baseline': BASELINE, 'seed': '0x4D4243', 'cases': 1536, 'sha256': hashlib.sha256(output).hexdigest()}
        Path('tests/fixtures/visibility-parity.json').write_text(json.dumps(fixture, indent=2) + '\n')
        print(fixture)
