# YYAnimatedImageView

- 继承UIImageView，用于显示图片和动态图。
- 动态图UIImage对象通过遵守YYAnimatedImage协议，为YYAnimatedImageView容器提供显示需要的图片信息。

##### buffer容器大小

```
//buffer 大小
#define BUFFER_SIZE (10 * 1024 * 1024) // 10MB (minimum memory buffer size)
```

##### 使用信号量机制

```
//使用信号量机制
#define LOCK(...) dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER); \
__VA_ARGS__; \
dispatch_semaphore_signal(self->_lock);

//使用view对应的信号锁
#define LOCK_VIEW(...) dispatch_semaphore_wait(view->_lock, DISPATCH_TIME_FOREVER); \
__VA_ARGS__; \
dispatch_semaphore_signal(view->_lock);
```

##### 设备内存总大小

```
//设备物理内存大小
static int64_t _YYDeviceMemoryTotal() {
    int64_t mem = [[NSProcessInfo processInfo] physicalMemory];
    if (mem < -1) mem = -1;
        return mem;
}
```

##### 设备可用总大小

```
static int64_t _YYDeviceMemoryFree() {
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t page_size;
    vm_statistics_data_t vm_stat;
    kern_return_t kern;
    
    kern = host_page_size(host_port, &page_size);
    if (kern != KERN_SUCCESS) return -1;
    kern = host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size);
    if (kern != KERN_SUCCESS) return -1;
    
    return vm_stat.free_count * page_size;
}
```

##### 当前帧

可以KVO观察，当前显示帧index的动态变化
`@property (nonatomic) NSUInteger currentAnimatedImageIndex;`

##### runLoopMode

动态图的动画显示需要定时器的调用，为了不被UI操作干扰，这里默认使用NSRunLoopCommonModes
`@property (nonatomic, copy) NSString *runloopMode;`

##### 帧缓存容器buffer

当收到系统内存警告或APP进入后台，临时缓存对象buffer会被直接释放掉
`@property (nonatomic) NSUInteger maxBufferSize;`


## _YYImageWeakProxy : NSProxy

- 弱对象持有，作为该弱对象的代理对象，可以防止循环引用。该代理为弱对象封装了一个壳子，消息实质流向了weak对象。
- 使用代理，可以在执行方法中使用self实例变量不用担心循环引用。

//使用一个weak指针指向需要被持有的对象
`@property (nonatomic, weak, readonly) id target;`

#### 消息代理

```
//消息转发代理
- (id)forwardingTargetForSelector:(SEL)selector {
    return _target;
}
//方法找不到时返回NULL
- (void)forwardInvocation:(NSInvocation *)invocation {
    void *null = NULL;
    [invocation setReturnValue:&null];
}

//方法签名代理
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [NSObject instanceMethodSignatureForSelector:@selector(init)];
}

//响应验证代理
- (BOOL)respondsToSelector:(SEL)aSelector {
    return [_target respondsToSelector:aSelector];
}
```

#### 等同性判断代理

```
- (BOOL)isEqual:(id)object {
    return [_target isEqual:object];
}
- (NSUInteger)hash {
    return [_target hash];
}
```

#### 类型和遵守协议代理

```
- (Class)superclass {
    return [_target superclass];
}
- (Class)class {
    return [_target class];
}
- (BOOL)isKindOfClass:(Class)aClass {
    return [_target isKindOfClass:aClass];
}
- (BOOL)isMemberOfClass:(Class)aClass {
    return [_target isMemberOfClass:aClass];
}
- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    return [_target conformsToProtocol:aProtocol];
}
- (BOOL)isProxy {
    return YES;
}
```

#### 描述性代理

```
- (NSString *)description {
    return [_target description];
}
- (NSString *)debugDescription {
    return [_target debugDescription];
}
```


## @protocol YYAnimatedImage <NSObject>

为YYAnimatedImageView动态图的显示提供信息

```
@protocol YYAnimatedImage <NSObject>

@required
- (NSUInteger)animatedImageFrameCount;

- (NSUInteger)animatedImageLoopCount;

- (NSUInteger)animatedImageBytesPerFrame;

- (nullable UIImage *)animatedImageFrameAtIndex:(NSUInteger)index;

- (NSTimeInterval)animatedImageDurationAtIndex:(NSUInteger)index;

@optional
- (CGRect)animatedImageContentsRectAtIndex:(NSUInteger)index;
- 
@end
```

## _YYAnimatedImageViewFetchOperation : NSOperation


- 获取图片操作，weak引用当前YYAnimatedImageView，持有当前显示帧图片和下一帧索引值。
- 使用animatedImageView对象持有的字典容器buffer，在信号量机制保护下，循环保存持有的curImage对应的帧图片到buffer中。达到预先加载提高渲染效率的作用。

```
@property (nonatomic, weak) YYAnimatedImageView *view;
@property (nonatomic, assign) NSUInteger nextIndex;
@property (nonatomic, strong) UIImage <YYAnimatedImage> *curImage;
```

继承NSOperation，需要重载- (void)main方法，执行该操作需要执行的动作。

```
- (void)main {
    
    __strong YYAnimatedImageView *view = _view;
    if (!view) return;
    
    if ([self isCancelled]) return;
    
    //更新animatedImageView的缓存计数_incrBufferCount
    view->_incrBufferCount++;
    if (view->_incrBufferCount == 0) [view calcMaxBufferCount];
    if (view->_incrBufferCount > (NSInteger)view->_maxBufferCount) {
        view->_incrBufferCount = view->_maxBufferCount;
    }
    
    //获取需要获取的帧索引、最大可存入缓存容器buffer大小、总图片帧数
    NSUInteger idx = _nextIndex;
    NSUInteger max = view->_incrBufferCount < 1 ? 1 : view->_incrBufferCount;
    NSUInteger total = view->_totalFrameCount;
    view = nil;
    
    //使用一个可变字典buffer来循环保存帧图片
    for (int i = 0; i < max; i++, idx++) {
        
        //使用自动释放池释放临时图片对象
        @autoreleasepool {
            //加载完则重新开始加载
            if (idx >= total) idx = 0;
            
            if ([self isCancelled]) break;
            
            __strong YYAnimatedImageView *view = _view;
            if (!view) break;
            
            //在信号锁下安全访问buffer字典的idx对应的对象是否为空，为空则可以保存数据
            LOCK_VIEW(BOOL miss = (view->_buffer[@(idx)] == nil));
            
            if (miss) {
                //帧图片
                UIImage *img = [_curImage animatedImageFrameAtIndex:idx];
                //解码
                img = img.yy_imageByDecoded;
                
                if ([self isCancelled]) break;
                
                //保存图片到buffer字典中， 以帧索引值为key
                LOCK_VIEW(view->_buffer[@(idx)] = img ? img : [NSNull null]);
                
                view = nil;
            }
        }
    }
}
```

## YYAnimatedImageView

#### 显示图片分为normal和highlight状态的图片，通过设置高亮属性来切换不同图片的显示。

```
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    //重置图片
    if (_link) [self resetAnimated];
    //开启图片动画
    [self imageChanged];
}
```

#### 为属性添加手动KVO

- 1.重载+ (BOOL)automaticallyNotifiesObserversForKey:(NSString*)key，返回BOOL值是否支持自动支持key的KVO。

```
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    if ([key isEqualToString:@"currentAnimatedImageIndex"]) {
        return NO;
    }
    return [super automaticallyNotifiesObserversForKey:key];
}
```

- 2.然后为currentAnimatedImageIndex的setter方法中添加手动KVO通知

```
- (void)setCurrentAnimatedImageIndex:(NSUInteger)currentAnimatedImageIndex {
    
    if (!_curAnimatedImage) return;
    if (currentAnimatedImageIndex >= _curAnimatedImage.animatedImageFrameCount) return;
    if (_curIndex == currentAnimatedImageIndex) return;
    
    //创建一个执行块
    void (^block)() = ^{
        //使用信号机制进行修改
        LOCK(
             //取消操作和移除缓存
             [_requestQueue cancelAllOperations];
             [_buffer removeAllObjects];
             //KVO
             [self willChangeValueForKey:@"currentAnimatedImageIndex"];
             _curIndex = currentAnimatedImageIndex;
             [self didChangeValueForKey:@"currentAnimatedImageIndex"];
             //获取需要显示的帧图片
             _curFrame = [_curAnimatedImage animatedImageFrameAtIndex:_curIndex];
             if (_curImageHasContentsRect) {
                 _curContentsRect = [_curAnimatedImage animatedImageContentsRectAtIndex:_curIndex];
             }
             _time = 0;
             _loopEnd = NO;
             _bufferMiss = NO;
             //显示当前帧图片
             [self.layer setNeedsDisplay];
        )//LOCK
    };
    //在主线程中执行
    if (pthread_main_np()) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}
```

#### 修改CADisplayLink的runLoop模式

```
- (void)setRunloopMode:(NSString *)runloopMode {
    if ([_runloopMode isEqual:runloopMode]) return;
    
    if (_link) {
        if (_runloopMode) {
            [_link removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:_runloopMode];
        }
        if (runloopMode.length) {
            [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:runloopMode];
        }
    }
    _runloopMode = runloopMode.copy;
}
```

#### 显示局部区域图片

```
- (void)setContentsRect:(CGRect)rect forImage:(UIImage *)image{
    CGRect layerRect = CGRectMake(0, 0, 1, 1);
    if (image) {
        CGSize imageSize = image.size;
        if (imageSize.width > 0.01 && imageSize.height > 0.01) {
            layerRect.origin.x = rect.origin.x / imageSize.width;
            layerRect.origin.y = rect.origin.y / imageSize.height;
            layerRect.size.width = rect.size.width / imageSize.width;
            layerRect.size.height = rect.size.height / imageSize.height;
            layerRect = CGRectIntersection(layerRect, CGRectMake(0, 0, 1, 1));
            if (CGRectIsNull(layerRect) || CGRectIsEmpty(layerRect)) {
                layerRect = CGRectMake(0, 0, 1, 1);
            }
        }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.contentsRect = layerRect;
    [CATransaction commit];
}
```

#### 内存警告创建移除_buffer内图片缓存operation，添加到队列中

```
- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    [_requestQueue cancelAllOperations];
    
    [_requestQueue addOperationWithBlock: ^{
        _incrBufferCount = -60 - (int)(arc4random() % 120); // about 1~3 seconds to grow back..
        NSNumber *next = @((_curIndex + 1) % _totalFrameCount);
        LOCK(
             NSArray * keys = _buffer.allKeys;
             for (NSNumber * key in keys) {
                 if (![key isEqualToNumber:next]) { // keep the next frame for smoothly animation
                     [_buffer removeObjectForKey:key];
                 }
             }
        )//LOCK
    }];
}
```

#### 进入后台移除_buffer内图片缓存

```
- (void)didEnterBackground:(NSNotification *)notification {
    [_requestQueue cancelAllOperations];
    NSNumber *next = @((_curIndex + 1) % _totalFrameCount);
    LOCK(
         NSArray * keys = _buffer.allKeys;
         for (NSNumber * key in keys) {
             if (![key isEqualToNumber:next]) { // keep the next frame for smoothly animation
                 [_buffer removeObjectForKey:key];
             }
         }
     )//LOCK
}
```

#### 设置图片

```
//设置图片
- (void)setImage:(id)image withType:(YYAnimatedImageType)type {
    //停止动画
    [self stopAnimating];
    //开启了定时器，则重置动画
    if (_link) [self resetAnimated];
    //置空当前帧
    _curFrame = nil;
    switch (type) {
        case YYAnimatedImageTypeNone: break;
        case YYAnimatedImageTypeImage: super.image = image; break;
        case YYAnimatedImageTypeHighlightedImage: super.highlightedImage = image; break;
        case YYAnimatedImageTypeImages: super.animationImages = image; break;
        case YYAnimatedImageTypeHighlightedImages: super.highlightedAnimationImages = image; break;
    }
    //开启图片动画
    [self imageChanged];
}
```

#### 图片变化

```
- (void)imageChanged {
    //获取当前图片
    YYAnimatedImageType newType = [self currentImageType];
    id newVisibleImage = [self imageForType:newType];
    
    //获取图片帧数，并判断图片是否是SpritSheet类型
    NSUInteger newImageFrameCount = 0;
    BOOL hasContentsRect = NO;
    if ([newVisibleImage isKindOfClass:[UIImage class]] &&
        [newVisibleImage conformsToProtocol:@protocol(YYAnimatedImage)]) {
        
        newImageFrameCount = ((UIImage<YYAnimatedImage> *) newVisibleImage).animatedImageFrameCount;
        if (newImageFrameCount > 1) {
            hasContentsRect = [((UIImage<YYAnimatedImage> *) newVisibleImage) respondsToSelector:@selector(animatedImageContentsRectAtIndex:)];
        }
    }
    //当前图片是spritSheet图片，但没有实现animatedImageContentsRectAtIndex：方法
    if (!hasContentsRect && _curImageHasContentsRect) {
        //当前只是显示部分图片内容，则让显示全部图片区域
        if (!CGRectEqualToRect(self.layer.contentsRect, CGRectMake(0, 0, 1, 1)) ) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.layer.contentsRect = CGRectMake(0, 0, 1, 1);
            [CATransaction commit];
        }
    }
    //显示第一张图片
    _curImageHasContentsRect = hasContentsRect;
    if (hasContentsRect) {
        CGRect rect = [((UIImage<YYAnimatedImage> *) newVisibleImage) animatedImageContentsRectAtIndex:0];
        [self setContentsRect:rect forImage:newVisibleImage];
    }
    //动化图片则保存初始参数值
    if (newImageFrameCount > 1) {
        [self resetAnimated];
        _curAnimatedImage = newVisibleImage;
        _curFrame = newVisibleImage;
        _totalLoop = _curAnimatedImage.animatedImageLoopCount;
        _totalFrameCount = _curAnimatedImage.animatedImageFrameCount;
        [self calcMaxBufferCount];
    }
    //重新绘制
    [self setNeedsDisplay];
    //开启动画
    [self didMoved];
}
```

#### 根据当前内存动态调整存放帧熟练_maxBufferCount的大小

```
- (void)calcMaxBufferCount {
    
    int64_t bytes = (int64_t)_curAnimatedImage.animatedImageBytesPerFrame;
    if (bytes == 0) bytes = 1024;
    
    int64_t total = _YYDeviceMemoryTotal();
    int64_t free = _YYDeviceMemoryFree();
    int64_t max = MIN(total * 0.2, free * 0.6);
    max = MAX(max, BUFFER_SIZE);
    if (_maxBufferSize) max = max > _maxBufferSize ? _maxBufferSize : max;
    
    double maxBufferCount = (double)max / (double)bytes;
    if (maxBufferCount < 1) maxBufferCount = 1;
    else if (maxBufferCount > 512) maxBufferCount = 512;
    
    _maxBufferCount = maxBufferCount;
}
```

#### 销毁dealloc

```
- (void)dealloc {
    //取消队列操作
    [_requestQueue cancelAllOperations];
    //移除通知
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    //销毁定时器
    [_link invalidate];
}
```


#### 使用CADisplayLink进行轮询显示动态图

```
- (void)step:(CADisplayLink *)link {
    //
    UIImage <YYAnimatedImage> *image = _curAnimatedImage;
    NSMutableDictionary *buffer = _buffer;
    UIImage *bufferedImage = nil;
    NSUInteger nextIndex = (_curIndex + 1) % _totalFrameCount;
    BOOL bufferIsFull = NO;
    //动画图片为空，则不进行动画
    if (!image) return;
    //循环结束
    if (_loopEnd) { // view will keep in last frame
        [self stopAnimating];
        return;
    }
    
    NSTimeInterval delay = 0;
    if (!_bufferMiss) {
        _time += link.duration;
        delay = [image animatedImageDurationAtIndex:_curIndex];
        
        //当前帧图片持续时间还未结束
        if (_time < delay) return;
        
        _time -= delay;
        //新一轮轮询结束，检测轮询是否结束
        if (nextIndex == 0) {
            _curLoop++;
            if (_curLoop >= _totalLoop && _totalLoop != 0) {
                _loopEnd = YES;
                [self stopAnimating];
                [self.layer setNeedsDisplay]; // let system call `displayLayer:` before runloop sleep
                return; // stop at last frame
            }
        }
        delay = [image animatedImageDurationAtIndex:nextIndex];
        if (_time > delay) _time = delay; // do not jump over frame
    }
    
    LOCK(
         bufferedImage = buffer[@(nextIndex)];
         if (bufferedImage) {
             if ((int)_incrBufferCount < _totalFrameCount) {
                 [buffer removeObjectForKey:@(nextIndex)];
             }
             
             [self willChangeValueForKey:@"currentAnimatedImageIndex"];
             _curIndex = nextIndex;
             [self didChangeValueForKey:@"currentAnimatedImageIndex"];
             
             _curFrame = bufferedImage == (id)[NSNull null] ? nil : bufferedImage;
             if (_curImageHasContentsRect) {
                 _curContentsRect = [image animatedImageContentsRectAtIndex:_curIndex];
                 [self setContentsRect:_curContentsRect forImage:_curFrame];
             }
             nextIndex = (_curIndex + 1) % _totalFrameCount;
             _bufferMiss = NO;
             if (buffer.count == _totalFrameCount) {
                 bufferIsFull = YES;
             }
         } else {
             _bufferMiss = YES;
         }
    )//LOCK
    
    if (!_bufferMiss) {
        [self.layer setNeedsDisplay]; // let system call `displayLayer:` before runloop sleep
    }
    
    if (!bufferIsFull && _requestQueue.operationCount == 0) { // if some work not finished, wait for next opportunity
        _YYAnimatedImageViewFetchOperation *operation = [_YYAnimatedImageViewFetchOperation new];
        operation.view = self;
        operation.nextIndex = nextIndex;
        operation.curImage = image;
        [_requestQueue addOperation:operation];
    }
}
```

#### 重置

- 高亮状态切换
- 重新加载图片，一是在停止动画时进行重置，而是加载的图片时动态图时再次重置

```
- (void)resetAnimated {
    
    //初始化
    dispatch_once(&_onceToken, ^{
        
        _lock = dispatch_semaphore_create(1);
        
        _buffer = [NSMutableDictionary new];
        
        _requestQueue = [[NSOperationQueue alloc] init];
        _requestQueue.maxConcurrentOperationCount = 1;
        
        _link = [CADisplayLink displayLinkWithTarget:[_YYImageWeakProxy proxyWithTarget:self] selector:@selector(step:)];
        if (_runloopMode) {
            [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:_runloopMode];
        }
        _link.paused = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    });
    //取消所有操作
    [_requestQueue cancelAllOperations];
    
    //在后台队列释放_buffer持有的图片数据
    LOCK(
         if (_buffer.count) {
             NSMutableDictionary *holder = _buffer;
             _buffer = [NSMutableDictionary new];
             dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                 // Capture the dictionary to global queue,
                 // release these images in background to avoid blocking UI thread.
                 [holder class];
             });
         }
    );
    
    //初始化变量值
    _link.paused = YES;
    _time = 0;
    if (_curIndex != 0) {
        [self willChangeValueForKey:@"currentAnimatedImageIndex"];
        _curIndex = 0;
        [self didChangeValueForKey:@"currentAnimatedImageIndex"];
    }
    _curAnimatedImage = nil;
    _curFrame = nil;
    _curLoop = 0;
    _totalLoop = 0;
    _totalFrameCount = 1;
    _loopEnd = NO;
    _bufferMiss = NO;
    _incrBufferCount = 0;
}
```