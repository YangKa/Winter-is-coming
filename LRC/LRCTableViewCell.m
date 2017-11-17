//
//  LRCTableViewCell.m
//  BQReport
//
//  Created by 杨卡 on 2017/11/17.
//  Copyright © 2017年 yangka. All rights reserved.
//

#import "LRCTableViewCell.h"
#import "LRCLabel.h"

@interface LRCTableViewCell (){
    LRCLabel *label;
}

@end

@implementation LRCTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        [self layoutUI];
    }
    return self;
}

- (void)layoutUI{
    
    label = [[LRCLabel alloc] init];
    label.progress = 0;
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = [UIColor blackColor];
    label.textAlignment = NSTextAlignmentCenter;
    
    
    [self.contentView addSubview:label];
}

- (void)layoutSubviews{
    [super layoutSubviews];
    label.center = CGPointMake(self.width/2, self.height/2);
}

- (void)setLRCText:(NSString *)text{
    label.text = text;
    [label sizeToFit];
}

- (void)setProgress:(CGFloat)prgress{
    label.progress = prgress;
}

@end
