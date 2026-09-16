#import <Foundation/Foundation.h>
#import <sys/stat.h>

// Cheap metadata checks gate the expensive signed-helper audit. The periodic
// full audit still verifies sealed resources even when these files are unchanged.
static NSArray *MBFileFingerprint(NSArray<NSString *> *paths) {
    NSMutableArray *result=[NSMutableArray new];
    for(NSString *path in paths){
        struct stat info;
        if(stat(path.fileSystemRepresentation,&info)!=0){[result addObject:@[path,@NO]];continue;}
        [result addObject:@[path,@YES,@(info.st_dev),@(info.st_ino),@(info.st_size),@(info.st_mtimespec.tv_sec),@(info.st_mtimespec.tv_nsec),@(info.st_ctimespec.tv_sec),@(info.st_ctimespec.tv_nsec)]];
    }
    return result;
}
static BOOL MBNeedsCompatibilityAudit(NSArray *current,NSArray *verified,BOOL ready,NSTimeInterval elapsed,NSTimeInterval sinceAttempt,BOOL force) {
    if(force)return YES;
    if(!ready)return sinceAttempt>=60;
    return ![current isEqual:verified] || elapsed>=3600;
}
