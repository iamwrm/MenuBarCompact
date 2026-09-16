#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Objective-C is isolated here: Swift cannot catch exceptions from a private API.
@interface MBRestrictionHandle : NSObject
- (nullable instancetype)initWithSystems:(NSArray<NSNumber *> *)systems bundles:(NSArray<NSString *> *)bundles error:(NSError **)error;
- (void)activate:(void (^)(NSError * _Nullable))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
