#import "../MenuActivation.h"
static void Require(BOOL condition,const char *message){if(!condition){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
int main(void){@autoreleasepool{
    NSArray *screens=@[[NSValue valueWithRect:NSMakeRect(0,0,1440,900)],[NSValue valueWithRect:NSMakeRect(-1920,-200,1920,1080)]];
    CGPoint point;
    Require(MBMenuClickPoint(CGPointMake(1200,0),CGSizeMake(24,24),screens,&point) && point.x==1212 && point.y==12,"Resolve visible status control center");
    Require(MBMenuClickPoint(CGPointMake(-500,-200),CGSizeMake(30,30),screens,&point),"Support a secondary display above and left of the main display");
    Require(!MBMenuClickPoint(CGPointMake(1200,70),CGSizeMake(24,24),screens,&point),"Never click below the menu bar");
    Require(!MBMenuClickPoint(CGPointMake(1430,0),CGSizeMake(24,24),screens,&point),"Reject partially off-screen controls");
    Require(!MBMenuClickPoint(CGPointMake(1200,50),CGSizeMake(24,24),screens,&point),"Require the whole control to fit the menu strip");
    Require(!MBMenuClickPoint(CGPointMake(0,0),CGSizeMake(0,24),screens,&point),"Reject empty controls");
    Require(!MBMenuClickPoint(CGPointMake(0,0),CGSizeMake(500,24),screens,&point),"Reject implausible status control widths");
    Require(!MBMenuClickPoint(CGPointMake(NAN,0),CGSizeMake(24,24),screens,&point),"Reject nonfinite positions");
    Require(!MBMenuClickPoint(CGPointMake(0,0),CGSizeMake(24,INFINITY),screens,&point),"Reject nonfinite dimensions");
    Require(!MBMenuClickPoint(CGPointMake(0,0),CGSizeMake(24,24),@[],&point),"Do not click without an active display");
    puts("Menu click geometry tests passed.");
}return 0;}
