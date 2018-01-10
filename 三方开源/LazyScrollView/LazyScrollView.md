## LazyScrollView


LazyScrollView是天猫团队为了解决主页view样式多元、数量膨胀、性能影响严重提出的滚动视图构建方案。支持跨View层的复用的一个高性能的滚动视图。

参考UITableView实现了一套复用回收机制以提高性能。相对UITableView只能解决同类Cell的展示、UICollectionView本身布局和复用机制不够灵活且使用繁琐来说，是相对使用灵活、轻量、高性能的。


LazyScrollView和UITableView很像，通过代理对象提供dataSource并反馈delegate事件。这里dataSource需要返回对应view相对LazyScrollView的绝对地址。也就是说必须提前计算好每个view在scrollView中的位置信息。

### LazyScrollViewDatasource

```
@protocol TMMuiLazyScrollViewDataSource <NSObject>

@required

//展示item数量
- (NSUInteger)numberOfItemInScrollView:(TMMuiLazyScrollView *)scrollView;

//返回持有相对对应index的view相对LazyScrollView的位置信息TMMuiRectModel
- (TMMuiRectModel *)scrollView:(TMMuiLazyScrollView *)scrollView rectModelAtIndex:(NSUInteger)index;

//返回下标所对应的view，这里会启动复用机制
- (UIView *)scrollView:(TMMuiLazyScrollView *)scrollView itemByMuiID:(NSString *)muiID;
@end
```

### 设计原理

参考TableView使用继承UIScrollView的LazyScrollView，让外部提供数据和响应操作事件。需要提供view集合和对应的位置集合，进而计算scrollView的contentSize。注册重用对象类，并使用identifer绑定。在scrollView滚动过程中触发`- (void)layoutSubviews `，然后查找可视区域需要显示的view集合，回收不在可视区域的view集合，用于下次获取对应index位置的重用。

使用category让每一个view对象都持有一个唯一标志muiID和一个重用标志reuseIdentifier。view相对LazyScrollView的相对位置信息由LSVRectModel保存，通过muiID与view对应。

```
@interface UIView (LSV)
// 索引过的标识，在LazyScrollView范围内唯一
@property (nonatomic, copy) NSString  *lsvId;
// 重用的ID
@property (nonatomic, copy) NSString *reuseIdentifier;
@end

@interface LSVRectModel : NSObject
// 转换后的绝对值rect
@property (nonatomic, assign) CGRect absRect;
// 业务下标
@property (nonatomic, copy) NSString *lsvId;
+ (instancetype)modelWithRect:(CGRect)rect lsvId:(NSString *)lsvId;
@end
```

### 重用机制

- 提供一个字典用于保存可重用的类对象：
`@property (nonatomic, strong) NSMutableDictionary<NSString *, Class> *registerClass;`

- 提供一个字典保存可重用的view
`@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet *> *reuseViews;`


#### 注册重用类
```
- (void)registerClass:(Class)viewClass forViewReuseIdentifier:(NSString *)identifier {
    [self.registerClass setValue:viewClass forKey:identifier];
}
```

#### 保存view到重用池
```
- (void)enqueueReusableView:(UIView *)view {
    if (!view.reuseIdentifier) {
        return;
    }
    NSString *identifier = view.reuseIdentifier;
    NSMutableSet *reuseSet = self.reuseViews[identifier];
    if (!reuseSet) {
        reuseSet = [NSMutableSet set];
        [self.reuseViews setValue:reuseSet forKey:identifier];
    }
    [reuseSet addObject:view];
}
```

#### 从重用池获取view

```
- (UIView *)dequeueReusableItemWithIdentifier:(NSString *)identifier {
    if (!identifier) {
        return nil;
    }
    NSMutableSet *reuseSet = self.reuseViews[identifier];
    UIView *view = [reuseSet anyObject];
    if (view) {
        [reuseSet removeObject:view];
        return view;
    }
    else {
        Class viewClass = [self.registerClass objectForKey:identifier];
        view = [viewClass new];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapItemAction:)];
        [view addGestureRecognizer:tap];
        view.userInteractionEnabled = YES;
        
        view.reuseIdentifier = identifier;
        return view;
    }
}
```

### 内部实现

##### 1.根据dataSource获取所有view的位置信息，即LSVRectModel集合

使用`@property (nonatomic, strong) NSMutableArray *allRects;`保存。


##### 2.排序

分别对rectModel集合按顶部(y)升序排序和底部(y)进行降序排序

##### 3.查找可视区域需要显示的view集合

为了更好的体验，会给visible region添加缓冲区高度bufferHeight，将查找区域放大为bufferHeigth + scrollViewHeight + bufferHeigth。

```
- (CGFloat)minEdgeOffset {
    CGFloat min = self.contentOffset.y;
    return MAX(min - kBufferSize, 0);
}
- (CGFloat)maxEdgeOffset {
    CGFloat max = self.contentOffset.y + CGRectGetHeight(self.bounds);
    return MIN(max + kBufferSize, self.contentSize.height);
}
```

###### 顶部(y)升序排序集合查找

查找临界点：contentOffset.y - bufferHeight
二分法查找小于该临界值的index

```
- (NSMutableSet *)findSetWithMinEdge:(CGFloat)minEdge {
    //排序
    NSArray *ascendingEdgeArray =
    [self.allRects sortedArrayUsingComparator:^NSComparisonResult(LSVRectModel *obj1, LSVRectModel *obj2) {
        return CGRectGetMinY(obj1.absRect) > CGRectGetMinY(obj2.absRect) ? NSOrderedDescending : NSOrderedAscending;
    }];
    
    // TOOD: 此处待优化
    // 二分法
    NSInteger minIndex = 0;
    NSInteger maxIndex = ascendingEdgeArray.count - 1;
    NSInteger midIndex = (minIndex + maxIndex) / 2;
    LSVRectModel *model = ascendingEdgeArray[midIndex];
    while (minIndex < maxIndex - 1) {
        if (CGRectGetMinY(model.absRect) > minEdge) {
            maxIndex = midIndex;
        }
        else {
            minIndex = midIndex;
        }
        midIndex = (minIndex + maxIndex) / 2;
        model = ascendingEdgeArray[midIndex];
    }
    midIndex = MAX(midIndex - 1, 0);
    NSArray *array = [ascendingEdgeArray subarrayWithRange:NSMakeRange(midIndex, ascendingEdgeArray.count - midIndex)];
    return [NSMutableSet setWithArray:array];
}
```

###### 底部(y)进行降序排序查找

查找临界点：contentOffset.y + scrollViewHeight + bufferHeight
二分法查找大于该临界值的index

```
- (NSMutableSet *)findSetWithMaxEdge:(CGFloat)maxEdge {
    
    NSArray *descendingEdgeArray =
    [self.allRects sortedArrayUsingComparator:^NSComparisonResult(LSVRectModel *obj1, LSVRectModel *obj2) {
        return CGRectGetMaxY(obj1.absRect) < CGRectGetMaxY(obj2.absRect) ? NSOrderedDescending : NSOrderedAscending;
    }];
    // TOOD: 此处待优化
    // 二分法
    NSInteger minIndex = 0;
    NSInteger maxIndex = descendingEdgeArray.count - 1;
    NSInteger midIndex = (minIndex + maxIndex) / 2;
    LSVRectModel *model = descendingEdgeArray[midIndex];
    while (minIndex < maxIndex - 1) {
        if (CGRectGetMaxY(model.absRect) < maxEdge) {
            maxIndex = midIndex;
        }
        else {
            minIndex = midIndex;
        }
        midIndex = (minIndex + maxIndex) / 2;
        model = descendingEdgeArray[midIndex];
    }
    midIndex = MAX(midIndex - 1, 0);
    NSArray *array = [descendingEdgeArray subarrayWithRange:NSMakeRange(midIndex, descendingEdgeArray.count - midIndex)];
    return [NSMutableSet setWithArray:array];
}
```

###### 可视区域视图集合

```
- (NSArray *)visiableViewModels {
    NSMutableSet *ascendSet = [self findSetWithMinEdge:[self minEdgeOffset]];
    NSMutableSet *descendSet = [self findSetWithMaxEdge:[self maxEdgeOffset]];
    [ascendSet intersectSet:descendSet];
    NSMutableArray *result = [NSMutableArray arrayWithArray:ascendSet.allObjects];
    return result;
}
```

##### 4.回收、复用、生成


### 更新滚动区域

```
- (void)updateAllRects {
    [self.allRects removeAllObjects];
    _numberOfItems = [self.dataSource numberOfItemInScrollView:self];
    
    for (NSInteger index = 0; index < _numberOfItems; ++ index) {
        LSVRectModel *model = [self.dataSource scrollView:self rectModelAtIndex:index];
        [self.allRects addObject:model];
    }
    //
    LSVRectModel *model = self.allRects.lastObject;
    self.contentSize = CGSizeMake(CGRectGetWidth(self.bounds), CGRectGetMaxY(model.absRect));
}
```

### 显示可视区域view

```
- (void)layoutSubviews {
    [super layoutSubviews];

    //可视区域需展示的view
    NSMutableArray *newVisibleViews = [self visiableViewModels].mutableCopy;
    NSMutableArray *newVisibleLsvIds = [newVisibleViews valueForKey:@"lsvId"];
    
    //回收入缓存池
    NSMutableArray *removeViews = [NSMutableArray array];
    for (UIView *view in self.visibleViews) {
        if (![newVisibleLsvIds containsObject:view.lsvId]) {
            [removeViews addObject:view];
        }
    }
    for (UIView *view in removeViews) {
        [self.visibleViews removeObject:view];
        [self enqueueReusableView:view];
        [view removeFromSuperview];
    }
    //获取需要显示view的id集合
    NSMutableArray *alreadyVisibles = [self.visibleViews valueForKey:@"lsvId"];
    //显示view
    for (LSVRectModel *model in newVisibleViews) {
        if ([alreadyVisibles containsObject:model.lsvId]) {
            continue;
        }
        UIView *view = [self.dataSource scrollView:self itemByLsvId:model.lsvId];
        view.frame = model.absRect;
        view.lsvId = model.lsvId;
        
        [self.visibleViews addObject:view];
        [self addSubview:view];
    }
}
```

### 重新加载

```
- (void)reloadData {

[self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
[self.visibleViews removeAllObjects];

[self updateAllRects];
}
```

### 总结

使用复用和回收机制，解决了view数量增多导致性能下降、内存占用大的问题。布局方式更加动态化、高性能化。
唯一的缺点是需要提供view相对scrollView的相对位置。


参考：

![iOS 高性能异构滚动视图构建方案 - LazyScrollView 详细用法](http://pingguohe.net/2017/03/02/lazyScrollView-demo.html)

![iOS 高性能异构滚动视图构建方案 —— LazyScrollView](http://pingguohe.net/2016/01/31/lazyscroll.html)
