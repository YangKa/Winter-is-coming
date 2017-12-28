## UIGestureRecognizer+YYAdd

借用其他对象持有action，本对象持有该target和调用action的selector。同时使用runtime对象关联保存多个target，达到一处操作，多处响应的效果。

代理类

```
@interface _YYUIGestureRecognizerBlockTarget : NSObject

@property (nonatomic, copy) void (^block)(id sender);

- (id)initWithBlock:(void (^)(id sender))block;
- (void)invoke:(id)sender;

@end

@implementation _YYUIGestureRecognizerBlockTarget

- (id)initWithBlock:(void (^)(id sender))block{
    self = [super init];
    if (self) {
        _block = [block copy];
    }
    return self;
}

- (void)invoke:(id)sender {
    if (_block) _block(sender);
}
```

分类

```
static const int block_key;
@implementation UIGestureRecognizer (YYAdd)

- (instancetype)initWithActionBlock:(void (^)(id sender))block {
    self = [self init];
    [self addActionBlock:block];
    return self;
}

- (void)addActionBlock:(void (^)(id sender))block {
    _YYUIGestureRecognizerBlockTarget *target = [[_YYUIGestureRecognizerBlockTarget alloc] initWithBlock:block];
    [self addTarget:target action:@selector(invoke:)];
    NSMutableArray *targets = [self _yy_allUIGestureRecognizerBlockTargets];
    [targets addObject:target];
}

- (void)removeAllActionBlocks{
    NSMutableArray *targets = [self _yy_allUIGestureRecognizerBlockTargets];
    [targets enumerateObjectsUsingBlock:^(id target, NSUInteger idx, BOOL *stop) {
        [self removeTarget:target action:@selector(invoke:)];
    }];
    [targets removeAllObjects];
}

- (NSMutableArray *)_yy_allUIGestureRecognizerBlockTargets {
    NSMutableArray *targets = objc_getAssociatedObject(self, &block_key);
    if (!targets) {
        targets = [NSMutableArray array];
        objc_setAssociatedObject(self, &block_key, targets, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return targets;
}

@end
```
