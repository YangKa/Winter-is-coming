//
//  LRCFilePaser.m
//  BQReport
//
//  Created by 杨卡 on 2017/11/17.
//  Copyright © 2017年 yangka. All rights reserved.
//

#import "LRCFilePaser.h"


@interface LRCFilePaser ()

@end

@implementation LRCFilePaser

- (NSArray *)paserLRCFileWithFileName:(NSString*)fileName{
    
    NSArray *list = [self lrcStringListForFileName:fileName];
    
    
    
    NSMutableArray *lrcList = [NSMutableArray array];
    for (int i = 0; i < list.count - 1; i++) {

        LRCModel *model = [self paserSingleLrcText:list[i] nextLine:list[i+1]];
        if (model) {
            [lrcList addObject:model];
        }
    }
    
    return lrcList.copy;
}


- (NSArray*)lrcStringListForFileName:(NSString*)fileName{
    
    NSString *path;
    if ([fileName containsString:@"."]) {
        NSArray *fileList = [fileName componentsSeparatedByString:@"."];
        path = [[NSBundle mainBundle] pathForResource:fileList.firstObject ofType:fileList.lastObject];
    }else{
        path = [[NSBundle mainBundle] pathForResource:fileName ofType:@"lrc"];
    }

    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    
    return [content componentsSeparatedByString:@"\n"];
}


- (LRCModel*)paserSingleLrcText:(NSString*)lrcText nextLine:(NSString*)nextLine{
    
    lrcText = [lrcText stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    lrcText = [lrcText stringByReplacingOccurrencesOfString:@"\t" withString:@""];
    NSMutableArray *list = [[lrcText componentsSeparatedByString:@"]"] mutableCopy];
    if (list.count < 2 || [list.lastObject length] == 0) {
        return nil;
    }
    
    //lrc
    NSString *text = list.lastObject;
    [list removeLastObject];
    
    //time
    NSTimeInterval totalTimeInterval = 0;
    NSMutableArray *timeList = [NSMutableArray array];
    for (int i =0; i < list.count; i++) {
        
        NSTimeInterval segementInterval = [self timeIntervalForTimeText:list[i]];
        totalTimeInterval += segementInterval;
        [timeList addObject:[NSNumber numberWithDouble:segementInterval]];
    }
    
    //next line time
    nextLine = [nextLine stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    nextLine = [nextLine stringByReplacingOccurrencesOfString:@"\t" withString:@""];
    if ( [nextLine containsString:@"]"] && [nextLine containsString:@"["] ) {
        NSArray *nextLineList =  [nextLine componentsSeparatedByString:@"]"];
        NSTimeInterval nextTime = [self timeIntervalForTimeText:nextLineList.firstObject];
        
        totalTimeInterval = nextTime - totalTimeInterval;
    }

    return [LRCModel LRCWithContent:text totalTime:totalTimeInterval  segementTimes:timeList];
}

//[00:50.37]
- (NSTimeInterval)timeIntervalForTimeText:(NSString*)timeText{
    
    timeText = [timeText stringByReplacingOccurrencesOfString:@"[" withString:@""];
    timeText = [timeText stringByReplacingOccurrencesOfString:@"]" withString:@""];
    
    NSTimeInterval segementInterval;
    if ([timeText containsString:@"."]) {
        NSString *minString = [timeText substringWithRange:NSMakeRange(0, 2)];
        NSString *secString = [timeText substringWithRange:NSMakeRange(3, 2)];
        NSString *mseString = [timeText substringWithRange:NSMakeRange(6, 2)];

        segementInterval = [minString integerValue]*60 + [secString integerValue] + [mseString integerValue]*0.001;
    }else{
        NSArray *array = [timeText componentsSeparatedByString:@":"];
        segementInterval = [array[0] integerValue]*60 + [array[1] integerValue];
    }
    
    return segementInterval;
}

@end
