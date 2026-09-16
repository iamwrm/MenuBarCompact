#import <Cocoa/Cocoa.h>

static NSPasteboardType const MBVisibilityDragType = @"io.github.iamwrm.MenuBarCompact.visibility-item";
@protocol MBVisibilityEditorDelegate <NSObject>
- (BOOL)canMoveVisibilityItem:(NSString *)identifier toRule:(NSInteger)rule;
- (void)moveVisibilityItem:(NSString *)identifier toRule:(NSInteger)rule;
@end

@interface MBVisibilityIcon : NSButton <NSDraggingSource>
@property BOOL movable, dragStarted;
@property NSEvent *dragStartEvent;
@end
@implementation MBVisibilityIcon
- (void)drawRect:(NSRect)dirtyRect {
    if(self.highlighted || self.window.firstResponder==self){
        [[NSColor.controlAccentColor colorWithAlphaComponent:0.12] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,2,2) xRadius:8 yRadius:8] fill];
    }
    [self.image drawInRect:NSMakeRect((self.bounds.size.width-24)/2,8,24,24) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.alignment=NSTextAlignmentCenter;style.lineBreakMode=NSLineBreakByTruncatingTail;
    [self.title drawInRect:NSMakeRect(2,43,self.bounds.size.width-4,16) withAttributes:@{NSFontAttributeName:self.font,NSForegroundColorAttributeName:NSColor.labelColor,NSParagraphStyleAttributeName:style}];
    if(!self.movable){NSImage *lock=[NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:nil];[lock drawInRect:NSMakeRect(self.bounds.size.width-15,5,9,10) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.5 respectFlipped:YES hints:nil];}
}
- (void)mouseDown:(NSEvent *)event {self.dragStartEvent=event;self.dragStarted=NO;self.highlighted=YES;self.needsDisplay=YES;}
- (void)mouseUp:(NSEvent *)event {
    self.highlighted=NO;self.needsDisplay=YES;
    self.dragStartEvent=nil;
}
- (void)mouseDragged:(NSEvent *)event {
    if(!self.movable || self.dragStarted || !self.dragStartEvent)return;
    NSPoint start=self.dragStartEvent.locationInWindow;
    if(hypot(event.locationInWindow.x-start.x,event.locationInWindow.y-start.y)<4)return;
    self.dragStarted=YES;self.highlighted=NO;self.needsDisplay=YES;
    NSPasteboardItem *payload=[NSPasteboardItem new];[payload setString:self.identifier forType:MBVisibilityDragType];
    NSDraggingItem *item=[[NSDraggingItem alloc] initWithPasteboardWriter:payload];
    NSBitmapImageRep *bitmap=[self bitmapImageRepForCachingDisplayInRect:self.bounds];
    [self cacheDisplayInRect:self.bounds toBitmapImageRep:bitmap];
    NSImage *preview=[[NSImage alloc] initWithSize:self.bounds.size];[preview addRepresentation:bitmap];
    [item setDraggingFrame:self.bounds contents:preview];
    NSDraggingSession *session=[self beginDraggingSessionWithItems:@[item] event:self.dragStartEvent source:self];
    session.animatesToStartingPositionsOnCancelOrFail=YES;
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation {self.dragStartEvent=nil;self.dragStarted=NO;self.highlighted=NO;self.needsDisplay=YES;}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {return context==NSDraggingContextWithinApplication?NSDragOperationMove:NSDragOperationNone;}
- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session {return YES;}
@end

@interface MBVisibilityLane : NSView
@property NSInteger rule;
@property BOOL dropHighlighted;
@property (weak) id<MBVisibilityEditorDelegate> editorDelegate;
@end
@implementation MBVisibilityLane
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])){[self registerForDraggedTypes:@[MBVisibilityDragType]];self.accessibilityElement=YES;self.accessibilityRole=NSAccessibilityGroupRole;}
    return self;
}
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:14 yRadius:14];
    [(self.dropHighlighted?[NSColor.controlAccentColor colorWithAlphaComponent:0.13]:NSColor.controlBackgroundColor) setFill];[path fill];
    [(self.dropHighlighted?NSColor.controlAccentColor:NSColor.separatorColor) setStroke];path.lineWidth=self.dropHighlighted?2:0.5;[path stroke];
}
- (NSString *)acceptedIdentifier:(id<NSDraggingInfo>)sender {
    if(![sender.draggingSource isKindOfClass:MBVisibilityIcon.class])return nil;
    MBVisibilityIcon *source=sender.draggingSource;
    NSString *identifier=[sender.draggingPasteboard stringForType:MBVisibilityDragType];
    if(!source.movable || source.window!=self.window || ![source.identifier isEqual:identifier])return nil;
    return [self.editorDelegate canMoveVisibilityItem:identifier toRule:self.rule]?identifier:nil;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    self.dropHighlighted=[self acceptedIdentifier:sender]!=nil;self.needsDisplay=YES;
    return self.dropHighlighted?NSDragOperationMove:NSDragOperationNone;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {return [self draggingEntered:sender];}
- (void)draggingExited:(id<NSDraggingInfo>)sender {self.dropHighlighted=NO;self.needsDisplay=YES;}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {return [self acceptedIdentifier:sender]!=nil;}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSString *identifier=[self acceptedIdentifier:sender];self.dropHighlighted=NO;self.needsDisplay=YES;
    if(!identifier)return NO;
    // Defer rebuilding views until AppKit has finished delivering the drop.
    id<MBVisibilityEditorDelegate> delegate=self.editorDelegate;NSInteger rule=self.rule;
    dispatch_async(dispatch_get_main_queue(),^{[delegate moveVisibilityItem:identifier toRule:rule];});return YES;
}
- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {self.dropHighlighted=NO;self.needsDisplay=YES;}
@end
