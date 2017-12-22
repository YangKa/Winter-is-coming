## SDWebImageCodersManger

- 一个全局对象持有多个编码器，方面集中管理
- 使用协议来去类型化，不关心编码器的具体类型，只关心它的协议特性
- 使用一个优先级队列，编码器添加的越晚优先级越高
- 当需要编解码摸个对象时，遍历编码器列表，询问是否可以操作该数据来进行操作
- 可以添加自定义的遵守`SDWebImageCoder`或`SDWebImageProgressiveCoder`协议的编码器
- coderManager是一个持有一个编码器队列，可以进行编码器的添加移除。它遵守SDWebImageCoder协议，可以提供编解码功能。

1. 编码器集合采用数组，添加的越早使用优先级越高

`@property (nonatomic, strong, nonnull) NSMutableArray<SDWebImageCoder>* mutableCoders;`

2. 默认添加IO编码器，如果支持weP格式则追击一个webP编码器。创建一个并行队列，用于编码器集的并行访问和栏栅修改

```
- (instancetype)init {
    if (self = [super init]) {
        // initialize with default coders
        _mutableCoders = [@[[SDWebImageImageIOCoder sharedCoder]] mutableCopy];
#ifdef SD_WEBP
        [_mutableCoders addObject:[SDWebImageWebPCoder sharedCoder]];
#endif
        _mutableCodersAccessQueue = dispatch_queue_create("com.hackemist.SDWebImageCodersManager", DISPATCH_QUEUE_CONCURRENT);//
    }
    return self;
}
```

3. 但返回的编码器队列会被反序处理，添加的越早反而优先级越低。

```
- (NSArray<SDWebImageCoder> *)coders {
    __block NSArray<SDWebImageCoder> *sortedCoders = nil;
    dispatch_sync(self.mutableCodersAccessQueue, ^{
        sortedCoders = (NSArray<SDWebImageCoder> *)[[[self.mutableCoders copy] reverseObjectEnumerator] allObjects];
    });
    return sortedCoders;
}

```

4. 通过对已有编码器进遍历，检测该coder是否可以对当前数据对象进行处理，可以就采用当前coder进行处理并返回处理后的数据对象

```
for (id<SDWebImageCoder> coder in self.coders) {
    if (/*编码器是否可以处理对象*/) {
        return /*用编码器对对象进行处理*/;
    }
}
```