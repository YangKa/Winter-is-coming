//
//  TextViewController.m
//  BQReport
//
//  Created by 杨卡 on 2017/11/17.
//  Copyright © 2017年 yangka. All rights reserved.
//

#import "TextViewController.h"
#import "LRCLabel.h"
#import "LRCTableViewCell.h"
#import "LRCFilePaser.h"

@interface TextViewController ()<UITableViewDelegate, UITableViewDataSource>{
    NSArray *_lrclist;
    UITableView *tableView;
    
    CADisplayLink *playLink;
    NSDate *beginTime;
    
    NSInteger _curRow;
    float _totalTime;
}

@end

static CGFloat CellHeight = 50;
@implementation TextViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor lightGrayColor];

    _curRow = 0;
    _totalTime = 0;
    LRCFilePaser *lrcPaser = [[LRCFilePaser alloc] init];
    _lrclist = [lrcPaser paserLRCFileWithFileName:@"111.lrc"];
    
    [self layoutUI];
    [self beginPlay];
}

- (void)layoutUI{
    CGFloat paddding = (self.view.height - CellHeight)/2;
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    imageView.image = [UIImage imageNamed:@"bg@2x.png"];
    [self.view addSubview:imageView];
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    effectView.frame = imageView.bounds;
    effectView.alpha = 0.9;
    [self.view addSubview:effectView];
    
    UIView *backView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.width, paddding)];
    [self.view addSubview:backView];
    
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = backView.bounds;
    gradientLayer.colors = @[[UIColor colorWithWhite:0 alpha:0], [UIColor colorWithWhite:0 alpha:0.3]];
    gradientLayer.locations = @[@0, @1.0];
    
    backView.layer.mask = gradientLayer;
    
    
    tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    tableView.backgroundColor = [UIColor clearColor];
    tableView.contentInset = UIEdgeInsetsMake(paddding , 0, paddding, 0);
    tableView.delegate = self;
    tableView.dataSource = self;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [tableView registerClass:[LRCTableViewCell class] forCellReuseIdentifier:@"LRCTableViewCell"];
    [self.view addSubview:tableView];
    
    if (@available(iOS 11.0, *)) {
        tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } else {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    
    UIView *upLine = [[UIView alloc] initWithFrame:CGRectMake(0, paddding, tableView.width, 1)];
    upLine.backgroundColor = [UIColor greenColor];
    [self.view addSubview:upLine];
    
    UIView *downLine = [[UIView alloc] initWithFrame:CGRectMake(0, paddding + CellHeight, tableView.width, 1)];
    downLine.backgroundColor = [UIColor greenColor];
    [self.view addSubview:downLine];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return _lrclist.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    return CellHeight;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    LRCTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LRCTableViewCell"];
    
    LRCModel *model = _lrclist[indexPath.row];
    [cell setLRCText:model.text];
    
    if (indexPath.row > _curRow ){
        [cell setProgress:0.0];
    }
    if (indexPath.row < _curRow) {
        [cell setProgress:1.0];
    }
    
    return cell;
}

- (void)beginPlay{
    beginTime = [NSDate date];
    playLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(refreshLRCList)];
    [playLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)refreshLRCList{
    
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:beginTime];
    
    LRCModel *model = _lrclist[_curRow];
    CGFloat progress = interval/model.totalTime;

    if (progress >=1) {
        
        if (_curRow == _lrclist.count -1 ) {
            [playLink invalidate];
        }else{
            
            LRCTableViewCell *oldCell = [tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:_curRow inSection:0]];
            oldCell.layer.transform = CATransform3DIdentity;
            [oldCell setProgress:1.0];
            _curRow++;
            
            NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:_curRow inSection:0];
            LRCTableViewCell *newCell = [tableView cellForRowAtIndexPath:newIndexPath];
            [newCell setProgress:0.0];
            
            beginTime = [NSDate date];
            [tableView scrollToRowAtIndexPath:newIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        }
        
    }else{
        LRCTableViewCell *cell = [tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:_curRow inSection:0]];
        [cell setProgress:progress];
    }
}



@end
