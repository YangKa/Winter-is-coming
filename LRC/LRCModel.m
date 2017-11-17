//
//  LRCModel.m
//  BQReport
//
//  Created by 杨卡 on 2017/11/17.
//  Copyright © 2017年 yangka. All rights reserved.
//

#import "LRCModel.h"

@interface LRCModel ()

//歌词
@property (nonatomic, copy) NSString *text;

//总时长
@property (nonatomic, assign) NSTimeInterval totalTime;

//分段时长
@property (nonatomic, copy) NSArray *segementTimes;

@end

@implementation LRCModel

+ (instancetype)LRCWithContent:(NSString*)content totalTime:(NSTimeInterval)time segementTimes:(NSArray*)times{
    LRCModel *model = [[LRCModel alloc] init];
    
    model.text = content;
    model.totalTime = time;
    model.segementTimes = times;
    
    return model;
}

@end
