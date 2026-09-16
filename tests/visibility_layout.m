#import "../VisibilityEditor.h"
static void Require(BOOL passed,const char *message){if(!passed){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
int main(void){@autoreleasepool{
    Require(MBVisibilityColumns(748)==13,"Standard width fits thirteen columns");
    Require(MBVisibilityHeight(13,748)==92 && MBVisibilityHeight(14,748)==160,"Overflow starts a second row");
    Require(MBVisibilityHeight(26,748)==160 && MBVisibilityHeight(27,748)==228,"Large sections continue wrapping without clipping");
    Require(MBVisibilityHeight(0,748)==92,"Empty sections remain usable drop targets");
    Require(MBVisibilityColumns(588)<13 && MBVisibilityColumns(1000)>13,"Columns adapt to narrower and wider windows");
    for(NSNumber *widthValue in @[@588,@748,@1000]){
        CGFloat width=widthValue.doubleValue;
        for(NSUInteger count=1;count<=100;count++){
            NSRect bounds=NSMakeRect(0,0,width,MBVisibilityHeight(count,width));
            for(NSUInteger i=0;i<count;i++){
                NSRect frame=MBVisibilityIconFrame(i,count,width);
                Require(NSContainsRect(bounds,frame),"Every icon fits inside its section");
                for(NSUInteger j=0;j<i;j++)Require(!NSIntersectsRect(frame,MBVisibilityIconFrame(j,count,width)),"Wrapped drag targets never overlap");
            }
        }
    }
    NSRect first=MBVisibilityIconFrame(0,17,748),next=MBVisibilityIconFrame(13,17,748);
    Require(first.origin.x==next.origin.x && next.origin.y<first.origin.y,"Wrapping proceeds left to right, then down");
    puts("Visibility layout tests passed: wrapping, resizing, empty sections, bounds, and non-overlapping targets.");
}return 0;}
