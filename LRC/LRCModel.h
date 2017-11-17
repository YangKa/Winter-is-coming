//
//  LRCModel.h
//  BQReport
//
//  Created by 杨卡 on 2017/11/17.
//  Copyright © 2017年 yangka. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LRCModel : NSObject

//歌词
@property (nonatomic, readonly, copy) NSString *text;

//开始时间
@property (nonatomic, readonly, assign) NSTimeInterval beginTime;

//总时长
@property (nonatomic, readonly, assign) NSTimeInterval totalTime;

//分段时长
@property (nonatomic, readonly, copy) NSArray *segementTimes;

+ (instancetype)LRCWithContent:(NSString*)content totalTime:(NSTimeInterval)time segementTimes:(NSArray*)times;

@end
