#import "../MaintenancePolicy.h"
static void Require(BOOL passed,NSString *message){if(!passed){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(void){@autoreleasepool{
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[directory stringByAppendingPathComponent:@"helper"];
    NSArray *missing=MBFileFingerprint(@[path]);
    [@"version1" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray *initial=MBFileFingerprint(@[path]);
    Require(![missing isEqual:initial],@"Installing a previously absent helper must invalidate the fingerprint");
    for(NSUInteger elapsed=60;elapsed<3600;elapsed+=60)Require(!MBNeedsCompatibilityAudit(initial,initial,YES,elapsed,elapsed,NO),@"Unchanged idle sweeps must not launch a full audit");
    Require(MBNeedsCompatibilityAudit(initial,initial,YES,3600,3600,NO),@"Unchanged files still receive an hourly full audit");
    Require(MBNeedsCompatibilityAudit(initial,initial,YES,1,1,YES),@"A manual check must bypass caching");
    Require(!MBNeedsCompatibilityAudit(initial,missing,NO,120,5,NO),@"Failed checks must not form a subprocess retry loop");
    Require(MBNeedsCompatibilityAudit(initial,missing,NO,120,60,NO),@"Failed checks retry after the backoff");
    Require(MBNeedsCompatibilityAudit(initial,nil,NO,0,60,NO),@"The first check must run");
    [@"version2" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray *replacement=MBFileFingerprint(@[path]);
    Require(![initial isEqual:replacement],@"Same-sized atomic replacements must be detected");
    Require(MBNeedsCompatibilityAudit(replacement,initial,YES,10,10,NO),@"A changed helper must be audited before the hourly interval");
    Require(MBNeedsCompatibilityAudit(@[initial,@2],@[initial,@1],YES,10,10,NO),@"A restarted helper must be audited");
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    Require(![MBFileFingerprint(@[path]) isEqual:replacement],@"Removing the helper must invalidate the fingerprint");
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    puts("Maintenance tests passed: idle gating, update detection, audit interval, and retry backoff.");
}return 0;}
