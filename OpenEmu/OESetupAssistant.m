//
//  OESetupAssistant.m
//  OpenEmu
//
//  Created by Anton Marini on 9/25/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "OESetupAssistant.h"

@implementation OESetupAssistant

@synthesize replaceView;
@synthesize step1;
@synthesize step2;
@synthesize step3;

- (id)init
{
    self = [super init];
    if (self) 
    {
        step = 0;
    }
    
    return self;
}

- (void) awakeFromNib
{    
    transition = [CATransition animation];
    transition.type = kCATransitionFade;
    transition.subtype = kCATransitionFromRight;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
    transition.duration = 1.0;

	CGColorRef colorRef = CGColorCreateGenericGray(0.129, 1.0);
    [[[replaceView superview] layer] setBackgroundColor:colorRef];

	
    [[replaceView layer] setBackgroundColor:colorRef];
	CGColorRelease(colorRef);
    
    [replaceView setWantsLayer:YES];
    
    [replaceView setAnimations: [NSDictionary dictionaryWithObject:transition forKey:@"subviews"]];
    
    [[replaceView animator] addSubview:step1];

}

- (IBAction) backToStep1:(id)sender
{
    transition.type = kCATransitionPush;
    transition.subtype = kCATransitionFromLeft;
    
    NSView* subview  = [[replaceView subviews] objectAtIndex:0];
    
    [[replaceView animator] replaceSubview:subview with:step1];


}
- (IBAction) toStep2:(id)sender
{
    transition.type = kCATransitionPush;
    transition.subtype = kCATransitionFromRight;

    NSView* subview  = [[replaceView subviews] objectAtIndex:0];

    [[replaceView animator] replaceSubview:subview with:step2];

}

- (IBAction) backToStep2:(id)sender
{
    transition.type = kCATransitionPush;
    transition.subtype = kCATransitionFromLeft;

    NSView* subview  = [[replaceView subviews] objectAtIndex:0];
    
    [[replaceView animator] replaceSubview:subview with:step2];
}

- (IBAction) toStep3:(id)sender
{
    transition.type = kCATransitionPush;
    transition.subtype = kCATransitionFromRight;
    
    NSView* subview  = [[replaceView subviews] objectAtIndex:0];
    
    [[replaceView animator] replaceSubview:subview with:step3];
}

@end
