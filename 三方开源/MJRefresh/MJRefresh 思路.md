## MJRefresh 思路

1.给UITableView和UICollectionView的基类UIScrollView添加扩展分类，设置mj_header和mj_footer的setter和getter方法，同时采用associateObject关联对象进行存储访问。并替换reloadData方法，执行数据加载时的回调。

```
static const char MJRefreshHeaderKey = '\0';
- (void)setMj_header:(MJRefreshHeader *)mj_header
{
    if (mj_header != self.mj_header) {
        
        // 删除旧的，添加新的
        [self.mj_header removeFromSuperview];
        [self insertSubview:mj_header atIndex:0];
        
        //存储新的
        [self willChangeValueForKey:@"mj_header"]; // KVO
        objc_setAssociatedObject(self, &MJRefreshHeaderKey, mj_header, OBJC_ASSOCIATION_ASSIGN);
        [self didChangeValueForKey:@"mj_header"]; // KVO
    }
}

- (MJRefreshHeader *)mj_header
{
    return objc_getAssociatedObject(self, &MJRefreshHeaderKey);
}
```

在类加载时执行+ (void)load;方法，对reloadData方法进行method swizzling，在执行relaodData时附带执行加载数据时的回调。

```
@implementation UITableView (MJRefresh)

+ (void)load
{
    [self exchangeInstanceMethod1:@selector(reloadData) method2:@selector(mj_reloadData)];
}

- (void)mj_reloadData
{
    [self mj_reloadData];
    
    [self executeReloadDataBlock];
}
@end
```

2.使用继承UIView的基类MJRefreshComponent作为refreshHeader和refreshFooter的基类。
继承`- (void)willMoveToSuperview:(UIView *)newSuperview`方法进行组件的位置属性设置和scrollView的属性设置，并监听scrollView的属性变化和拖拉手势的状态变化。

```
- (void)willMoveToSuperview:(UIView *)newSuperview
{
    [super willMoveToSuperview:newSuperview];
    
    // 如果不是UIScrollView，不做任何事情
    if (newSuperview && ![newSuperview isKindOfClass:[UIScrollView class]]) return;
    
    // 旧的父控件移除监听
    [self removeObservers];
    
    if (newSuperview) { // 新的父控件
        // 设置宽度
        self.mj_w = newSuperview.mj_w;
        // 设置位置
        self.mj_x = -_scrollView.mj_insetL;
        
        // 记录UIScrollView
        _scrollView = (UIScrollView *)newSuperview;
        // 设置永远支持垂直弹簧效果
        _scrollView.alwaysBounceVertical = YES;
        // 记录UIScrollView最开始的contentInset
        _scrollViewOriginalInset = _scrollView.mj_inset;
        
        // 添加监听
        [self addObservers];
    }
}
```

注册观察者
```
/*
	NSString *const MJRefreshKeyPathContentOffset = @"contentOffset";
	NSString *const MJRefreshKeyPathContentInset = @"contentInset";
	NSString *const MJRefreshKeyPathContentSize = @"contentSize";
	NSString *const MJRefreshKeyPathPanState = @"state";
*/

- (void)addObservers
{
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
    [self.scrollView addObserver:self forKeyPath:MJRefreshKeyPathContentOffset options:options context:nil];
    [self.scrollView addObserver:self forKeyPath:MJRefreshKeyPathContentSize options:options context:nil];
    self.pan = self.scrollView.panGestureRecognizer;
    [self.pan addObserver:self forKeyPath:MJRefreshKeyPathPanState options:options context:nil];
}
```

KVO处理
```
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    // 遇到这些情况就直接返回
    if (!self.userInteractionEnabled) return;
    
    // 这个就算看不见也需要处理
    if ([keyPath isEqualToString:MJRefreshKeyPathContentSize]) {
        [self scrollViewContentSizeDidChange:change];
    }
    
    // 看不见
    if (self.hidden) return;
    if ([keyPath isEqualToString:MJRefreshKeyPathContentOffset]) {
        [self scrollViewContentOffsetDidChange:change];
    } else if ([keyPath isEqualToString:MJRefreshKeyPathPanState]) {
        [self scrollViewPanStateDidChange:change];
    }
}
```


3.

