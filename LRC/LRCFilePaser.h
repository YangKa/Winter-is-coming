//
//  LRCFilePaser.h
//  BQReport
//
//  Created by 杨卡 on 2017/11/17.
//  Copyright © 2017年 yangka. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LRCModel.h"


@interface LRCFilePaser : NSObject

- (NSArray *)paserLRCFileWithFileName:(NSString*)fileName;

@end
