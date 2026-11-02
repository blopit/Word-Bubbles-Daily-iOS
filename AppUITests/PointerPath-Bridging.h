// Declarations for XCTest's multi-point touch paths, used only by the UI test runner.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface XCPointerEventPath : NSObject
- (instancetype)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(double)offset;
- (void)liftUpAtOffset:(double)offset;
@end

@interface XCSynthesizedEventRecord : NSObject
- (instancetype)initWithName:(NSString *)name interfaceOrientation:(long long)orientation;
- (void)addPointerEventPath:(XCPointerEventPath *)path;
@end

@protocol WBEventSynthesizing <NSObject>
- (void)synthesizeEvent:(XCSynthesizedEventRecord *)event completion:(void (^)(BOOL, NSError * _Nullable))completion;
@end

@interface XCUIDevice (WBEventSynthesis)
- (id<WBEventSynthesizing>)eventSynthesizer;
@end

NS_ASSUME_NONNULL_END
