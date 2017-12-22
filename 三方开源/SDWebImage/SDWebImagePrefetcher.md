## SDWebImagePrefetcher

图片预下载器，借助SDWebImageManager中的下载器SDWebImageDownloader进行下载
下载任务都是低优先级执行 `SDWebImageLowPriority`
在主线程中进行，默认最大并发数为3。
只能一个队列一个队列的下载，不能任务叠加。
记录请求数、请求跳过数、完成数、队列启动时间

### 协议SDWebImagePrefetcherDelegate

```
//当一张图片加载结束时
- (void)imagePrefetcher:(nonnull SDWebImagePrefetcher *)imagePrefetcher didPrefetchURL:(nullable NSURL *)imageURL finishedCount:(NSUInteger)finishedCount totalCount:(NSUInteger)totalCount;
//当所有图片加载结束
- (void)imagePrefetcher:(nonnull SDWebImagePrefetcher *)imagePrefetcher didFinishWithTotalCount:(NSUInteger)totalCount skippedCount:(NSUInteger)skippedCount;
```

#### 启动下载

取消之前的全部请求，然后一次开启最大并发请求数。
对于正在执行的请求是无法结束的，可能产生无法预料的结果。

```
- (void)prefetchURLs:(nullable NSArray<NSURL *> *)urls
            progress:(nullable SDWebImagePrefetcherProgressBlock)progressBlock
           completed:(nullable SDWebImagePrefetcherCompletionBlock)completionBlock {
    //取消之前的预加载请求
    [self cancelPrefetching]; // Prevent duplicate prefetch request
    //记录开始时间
    self.startedTime = CFAbsoluteTimeGetCurrent();
    self.prefetchURLs = urls;
    self.completionBlock = completionBlock;
    self.progressBlock = progressBlock;

    //没有请求则执行完成回调
    if (urls.count == 0) {
        if (completionBlock) {
            completionBlock(0,0);
        }
    } else {
        //一次开启最大并发请求数
        NSUInteger listCount = self.prefetchURLs.count;
        for (NSUInteger i = 0; i < self.maxConcurrentDownloads && self.requestedCount < listCount; i++) {
            [self startPrefetchingAtIndex:i];
        }
    }
}
```

#### 下载过程

一开始开启了最大并发数，后面结束一个启动一个，类似窗口机制。

```
- (void)startPrefetchingAtIndex:(NSUInteger)index {
    
    //越界检查，防止请求过程中prefetchURLs被重置导致越界
    if (index >= self.prefetchURLs.count) return;
    //增加请求数
    self.requestedCount++;
    //开启请求
    [self.manager loadImageWithURL:self.prefetchURLs[index] options:self.options progress:nil completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        //请求完成则新增完成数
        if (!finished) return;
        self.finishedCount++;
        //请求失败数
        if (!image) self.skippedCount++;
        
        //回调进度
        if (self.progressBlock) {
            self.progressBlock(self.finishedCount,(self.prefetchURLs).count);
        }
        //代理返回进度
        if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didPrefetchURL:finishedCount:totalCount:)]) {
            [self.delegate imagePrefetcher:self
                            didPrefetchURL:self.prefetchURLs[index]
                             finishedCount:self.finishedCount
                                totalCount:self.prefetchURLs.count
             ];
        }
        
        //队列中有任务则执行下一个请求
        if (self.prefetchURLs.count > self.requestedCount) {
            dispatch_async(self.prefetcherQueue, ^{
                [self startPrefetchingAtIndex:self.requestedCount];
            });
        }
        //全部请求完成则报告状态，并置空completionBlock和progressBlock。
        //一是可以防止错误的循环引用，一了可以释放内存
        else if (self.finishedCount == self.requestedCount) {
            [self reportStatus];
            if (self.completionBlock) {
                self.completionBlock(self.finishedCount, self.skippedCount);
                self.completionBlock = nil;
            }
            self.progressBlock = nil;
        }
    }];
}
```

#### 所有任务结束时报告状态

```
- (void)reportStatus {
    NSUInteger total = (self.prefetchURLs).count;
    if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didFinishWithTotalCount:skippedCount:)]) {
        [self.delegate imagePrefetcher:self
               didFinishWithTotalCount:(total - self.skippedCount)
                          skippedCount:self.skippedCount
         ];
    }
}
```
