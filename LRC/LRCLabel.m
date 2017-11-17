//
//  LRCLabel.m
//  BQReport
//
//  Created by 杨卡 on 2017/11/17.
//  Copyright © 2017年 yangka. All rights reserved.
//

#import "LRCLabel.h"

@interface LRCLabel ()

@end

@implementation LRCLabel

- (void)drawRect:(CGRect)rect{
    [super drawRect:rect];
    
    CGRect fillRect = CGRectMake(0, 0, self.width*_progress, self.height);
    
    [[UIColor greenColor] setFill];
    UIRectFillUsingBlendMode(fillRect, kCGBlendModeSourceIn);
}

- (void)setProgress:(CGFloat)progress{
    _progress = progress;
    [self setNeedsDisplay];
    
}

@end
