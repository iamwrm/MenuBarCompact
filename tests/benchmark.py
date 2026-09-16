#!/usr/bin/env python3
"""Optional, local Release comparison against the pinned Objective-C baseline."""
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
from generate_parity_fixture import BASELINE

LEGACY_BENCHMARK = r'''
#import "VisibilityPolicy.h"
int main(void){@autoreleasepool{
NSMutableArray *runtime=[NSMutableArray new],*running=[NSMutableArray new];NSMutableDictionary *rules=[NSMutableDictionary new];
for(int i=0;i<12;i++)[runtime addObject:@{@"token":[NSString stringWithFormat:@"category%d",i],@"raw":@(i)}];
MBSetSystemItems(MBBuildSystemCatalog(runtime,@[],@[]));
for(int i=0;i<100;i++)[running addObject:[NSString stringWithFormat:@"example.app%d",i]];
for(int i=0;i<40;i++)rules[[NSString stringWithFormat:@"example.app%d",i]]=@(i%3);
for(int i=0;i<12;i++)rules[[NSString stringWithFormat:@"system.category%d",i]]=@(i%3);
NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;NSUInteger checksum=0;
for(int i=0;i<10000;i++){@autoreleasepool{NSDictionary *plan=MBVisibilityPlan(running,rules,@"test.own",i%3);checksum+=[plan[@"bundles"] count]+[plan[@"systems"] count]+[plan[@"excluded"] unsignedIntegerValue];}}
printf("%.3f ms; checksum %lu\n",(NSProcessInfo.processInfo.systemUptime-start)*1000,(unsigned long)checksum);
}return 0;}
'''

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    for filename in ('VisibilityPolicy.h', 'SystemCatalog.h'):
        (root / filename).write_bytes(subprocess.check_output(['git', 'show', f'{BASELINE}:{filename}']))
    (root / 'main.m').write_text(LEGACY_BENCHMARK)
    subprocess.run(['xcrun', 'clang', '-Os', '-fobjc-arc', '-framework', 'Foundation', str(root / 'main.m'), '-o', str(root / 'objc')], check=True)
    subprocess.run(['xcrun', 'swiftc', '-O', '-whole-module-optimization', 'SystemDiscovery.swift', 'SystemCatalog.swift', 'VisibilityPolicy.swift', 'tests/PolicyBenchmark.swift', '-o', str(root / 'swift')], check=True)
    result = {}
    for language in ('objc', 'swift'):
        samples = [subprocess.check_output([str(root / language)], text=True).strip() for _ in range(5)]
        result[language] = {'samples': samples, 'median_ms': statistics.median(float(s.split()[0]) for s in samples)}
    print(json.dumps(result, indent=2))
