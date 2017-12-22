## SDWebImageDownloaderOperation : NSOperation

继承NSOperation，持有一个NSURLSessionTask用于请求图片。
对应一个SDWebImageDownloadToken对象，与该操作绑定，用于取消操作。
拥有一个block回调字典，保存progress和complete的回调。

`downloadOperation`继承NSOperation，需要重载`- (void)start`来初始化操作，在start方法中不能调用父类的start方法。应该在操作的executing和finish的状态改变时手动开启KVO通知。

##### 通知

返回下载操作的进行状态

```
FOUNDATION_EXPORT NSString * _Nonnull const SDWebImageDownloadStartNotification;
FOUNDATION_EXPORT NSString * _Nonnull const SDWebImageDownloadReceiveResponseNotification;
FOUNDATION_EXPORT NSString * _Nonnull const SDWebImageDownloadStopNotification;
FOUNDATION_EXPORT NSString * _Nonnull const SDWebImageDownloadFinishNotification;
```

##### 协议SDWebImageDownloaderOperationInterface

自定义一个下载操作子类，必须继承该协议。

```
@protocol SDWebImageDownloaderOperationInterface<NSObject>

- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options;

- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

- (BOOL)shouldDecompressImages;
- (void)setShouldDecompressImages:(BOOL)value;

- (nullable NSURLCredential *)credential;
- (void)setCredential:(nullable NSURLCredential *)value;

@end

```

##### 请求回调

```
//回调block对应的key
static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

typedef NSMutableDictionary<NSString *, id> SDCallbacksDictionary;
```

一个请求被重复请求则会对应多个progress和complete回调
`@property (strong, nonatomic, nonnull) NSMutableArray<SDCallbacksDictionary *> *callbackBlocks;`

##### 属性

```
//用于进入后台时向系统申请一段处理事件。
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;

//图片解码器
@property (strong, nonatomic, nullable) id<SDWebImageProgressiveCoder> progressiveCoder;

//弱引用外部session，防止循环引用
@property (weak, nonatomic, nullable) NSURLSession *unownedSession;

//内部任务自己的session
@property (strong, nonatomic, nullable) NSURLSession *ownedSession;

//请求任务
@property (strong, nonatomic, readwrite, nullable) NSURLSessionTask *dataTask;

//栏栅队列
@property (SDDispatchQueueSetterSementics, nonatomic, nullable) dispatch_queue_t barrierQueue;
```

##### 初始化设置

```
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options {
    if ((self = [super init])) {
        _request = [request copy];
        _shouldDecompressImages = YES;
        _options = options;
        _callbackBlocks = [NSMutableArray new];
        _executing = NO;
        _finished = NO;
        _expectedSize = 0;
        _unownedSession = session;
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderOperationBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}
```
##### 请求回调管理

- 保存

```
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock {
    
    SDCallbacksDictionary *callbacks = [NSMutableDictionary new];
    if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
    if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
    //安全添加
    dispatch_barrier_async(self.barrierQueue, ^{
        [self.callbackBlocks addObject:callbacks];
    });
    return callbacks;
}

```

- 获取

对于集合类型， `valueForKey:`返回的元素对象只会包含对应属性的对象，对于没有该属性的会返回NSNull对象

```
- (nullable NSArray<id> *)callbacksForKey:(NSString *)key {
    __block NSMutableArray<id> *callbacks = nil;
    dispatch_sync(self.barrierQueue, ^{
        //从所有回调集合中获取对应回调
        callbacks = [[self.callbackBlocks valueForKey:key] mutableCopy];
        //移除空回调
        [callbacks removeObjectIdenticalTo:[NSNull null]];
    });
    return [callbacks copy];    //返回不可变对象
}
```

##### 外部发起取消

一个请求对应多个资源请求，先查看所有回调集合，一个URL对应请求数大于1则移除对应的回调。没有则取消自己。

```
- (BOOL)cancel:(nullable id)token {
    __block BOOL shouldCancel = NO;
    dispatch_barrier_sync(self.barrierQueue, ^{
        [self.callbackBlocks removeObjectIdenticalTo:token];
        if (self.callbackBlocks.count == 0) {
            //该资源只有一个请求
            shouldCancel = YES;
        }
    });
    //没有重复请求时，取消自己
    if (shouldCancel) {
        [self cancel];
    }
    return shouldCancel;
}
```

##### 内部取消

内部取消

```
- (void)cancelInternal {
    //已经执行完，则返回
    if (self.isFinished) return;
    
    [super cancel];
    if (self.dataTask) {
        [self.dataTask cancel];
        
        //发送下载停止通知
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:weakSelf];
        });

        //由于会触发KVO机制，所以对于还没有执行或者执行未结束的操作不用修改
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }

    [self reset];
}
```

内部取消需要保证线程安全，在同步块@synchronize中进行

```
- (void)cancel {
    @synchronized (self) {
        [self cancelInternal];
    }
}
```

##### 请求结束

1.修改状态

```
- (void)done {
    self.finished = YES;
    self.executing = NO;
    [self reset];
}
```

2.重置

```
- (void)reset {
    
    //移除所有管理的请求回调
    __weak typeof(self) weakSelf = self;
    dispatch_barrier_async(self.barrierQueue, ^{
        [weakSelf.callbackBlocks removeAllObjects];
    });
    //置空task
    self.dataTask = nil;
    
    //获取弱session代理队列
    NSOperationQueue *delegateQueue;
    if (self.unownedSession) {
        delegateQueue = self.unownedSession.delegateQueue;
    } else {
        delegateQueue = self.ownedSession.delegateQueue;
    }
    //给外部session添加置空图片数据的操作
    if (delegateQueue) {
        NSAssert(delegateQueue.maxConcurrentOperationCount == 1, @"NSURLSession delegate queue should be a serial queue");
        [delegateQueue addOperationWithBlock:^{
            weakSelf.imageData = nil;
        }];
    }
    //销毁强session
    if (self.ownedSession) {
        [self.ownedSession invalidateAndCancel];
        self.ownedSession = nil;
    }
}
```

##### 任务状态改变KVO

```
- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}
```

#### 启动任务 - (void)start；方法

##### 在同步块中申请后台时间，创建任务

```
@synchronized (self) {
	//检测是否可以启动
	//是否需要申请后台时间
	//是否使用响应缓存
	//获取session
	//创建任务
};
```

###### 1.检测任务是否已经取消，取消则设置成完成状态并重置

```
if (self.isCancelled) {
    self.finished = YES;
    [self reset];
    return;
}
```

###### 2.是否是iOS平台，查看是否需要向后台申请时间

```
Class UIApplicationClass = NSClassFromString(@"UIApplication");
BOOL hasApplication = UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)];
//是否允许后台继续执行任务，是则向系统申请执行时间，将当前操作执行完
if (hasApplication && [self shouldContinueWhenAppEntersBackground]) {
    __weak __typeof__ (self) wself = self;
    
    UIApplication * app = [UIApplicationClass performSelector:@selector(sharedApplication)];
    self.backgroundTaskId = [app beginBackgroundTaskWithExpirationHandler:^{
        __strong __typeof (wself) sself = wself;
        //系统分配时间已到
        if (sself) {
            //取消任务
            [sself cancel];
            //结束后台申请
            [app endBackgroundTask:sself.backgroundTaskId];
            sself.backgroundTaskId = UIBackgroundTaskInvalid;
        }
    }];
}
```

###### 3.是否需要忽略响应缓存

```
if (self.options & SDWebImageDownloaderIgnoreCachedResponse) {
    // 获取缓存响应数据
    NSCachedURLResponse *cachedResponse = [[NSURLCache sharedURLCache] cachedResponseForRequest:self.request];
    if (cachedResponse) {
        self.cachedData = cachedResponse.data;
    }
}
```
        
###### 4.强持有回话session，外部弱session被取消则使用内部新建的session

```
NSURLSession *session = self.unownedSession;
if (!self.unownedSession) {
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.timeoutIntervalForRequest = 15;
    self.ownedSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                      delegate:self
                                                 delegateQueue:nil];
    session = self.ownedSession;
}
```
       
###### 5.使用session创建任务

```
self.dataTask = [session dataTaskWithRequest:self.request];
        self.executing = YES;
```     

##### 启动任务并发送启动通知，关闭后台时间申请

###### 6.请求启动

```
[self.dataTask resume];
```

###### 7.开启报告进度

```
if (self.dataTask) {
    //循环调用所有请求的进度回调
    for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
        progressBlock(0, NSURLResponseUnknownLength, self.request.URL);
    }
    //发送请求开始通知
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStartNotification object:weakSelf];
    });
} else {
    //任务创建失败，调用完成回调返回错误
    [self callCompletionBlocksWithError:[NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Connection can't be initialized"}]];
}
```

###### 8.结束后台时间申请

```
Class UIApplicationClass = NSClassFromString(@"UIApplication");
if(!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
    return;
}
if (self.backgroundTaskId != UIBackgroundTaskInvalid) {
    UIApplication * app = [UIApplication performSelector:@selector(sharedApplication)];
    [app endBackgroundTask:self.backgroundTaskId];
    self.backgroundTaskId = UIBackgroundTaskInvalid;
}
```

##### 调用完成回调

```
- (void)callCompletionBlocksWithImage:(nullable UIImage *)image
                            imageData:(nullable NSData *)imageData
                                error:(nullable NSError *)error
                             finished:(BOOL)finished {
                             
    NSArray<id> *completionBlocks = [self callbacksForKey:kCompletedCallbackKey];
    dispatch_main_async_safe(^{
        for (SDWebImageDownloaderCompletedBlock completedBlock in completionBlocks) {
            completedBlock(image, imageData, error, finished);
        }
    });
    
}
```

#### NSURLSessionTaskDelegate

##### 1.任务完成

###### 1.同步块置空dataTask，并发送任务停止通知。如果没有报错也发送任务完成通知。

```
@synchronized(self) {
    self.dataTask = nil;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:weakSelf];
        if (!error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadFinishNotification object:weakSelf];
        }
    });
}
```

###### 2.任务报错则回调所有completeBlock，否则进行解压缩后回调

```
if (error) {
    [self callCompletionBlocksWithError:error];
} else {
    //含有completeBlock回调
    if ([self callbacksForKey:kCompletedCallbackKey].count > 0) {

        NSData *imageData = [self.imageData copy];
        if (imageData) {
    
            //设置为忽视缓存数据，如果接收图片数据与缓存数据相同则直接结束，调用完成回调
            if (self.options & SDWebImageDownloaderIgnoreCachedResponse && [self.cachedData isEqualToData:imageData]) {
                [self callCompletionBlocksWithImage:nil imageData:nil error:nil finished:YES];
            } else {
                
                //对图片进行解码、scale放大
                UIImage *image = [[SDWebImageCodersManager sharedInstance] decodedImageWithData:imageData];
                NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:self.request.URL];
                image = [self scaledImageForKey:key image:image];
                
                BOOL shouldDecode = self.shouldDecompressImages;
                
                //不要强制解码gif和webP图片
                if (shouldDecode){
                    SDImageFormat imageFormat = [NSData sd_imageFormatForImageData:imageData];
                    if (imageFormat == SDImageFormatWebP || imageFormat == SDImageFormatGIF) {
                        shouldDecode = NO;
                    }
                }

                //加压缩图片
                if (shouldDecode) {
                    BOOL shouldScaleDown = self.options & SDWebImageDownloaderScaleDownLargeImages;
                    image = [[SDWebImageCodersManager sharedInstance] decompressedImageWithImage:image data:&imageData options:@{SDWebImageCoderScaleDownLargeImagesKey: @(shouldScaleDown)}];
                }
                
                //图片尺寸大小为0则返回错误，否则返回图片和数据
                if (CGSizeEqualToSize(image.size, CGSizeZero)) {
                    [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image has 0 pixels"}]];
                } else {
                    [self callCompletionBlocksWithImage:image imageData:imageData error:nil finished:YES];
                }
            }
            
        } else {
            //接收数据为空，则发送错误完成回调
            [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Image data is nil"}]];
        }
    }
}
```

###### 3.修改操作状态到完成状态

```
[self done];
```

##### 2.证书验证

```
	- (void)URLSession:(NSURLSession *)session 
					 task:(NSURLSessionTask *)task 
   didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
	 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
```

`NSURLSessionAuthChallengeDisposition`处理证书的方式，有以下类型：

- NSURLSessionAuthChallengeUseCredential = 0,                     使用证书
- NSURLSessionAuthChallengePerformDefaultHandling = 1,            忽略证书(默认的处理方式)
- NSURLSessionAuthChallengeCancelAuthenticationChallenge = 2,     忽略书证, 并取消这次请求
- NSURLSessionAuthChallengeRejectProtectionSpace = 3,            拒绝当前这一次, 下一次再询问

```
//默认响应
NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
__block NSURLCredential *credential = nil;
    
//查看服务器的证书类型是否是受信任的
if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    
    //不允许无效的证书，则采用默认的处理证书方式
    if (!(self.options & SDWebImageDownloaderAllowInvalidSSLCertificates)) {
        
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    } else {//根据服务器的serverTrust创建NSURLCreadential，并使用证书
        
        credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        disposition = NSURLSessionAuthChallengeUseCredential;
    }
}
//使用自定义的证书验证
else {
    //挑战失败次数为0，尝试使用本地证书
    if (challenge.previousFailureCount == 0) {
        //如果有本地证书则使用本地证书，否则忽略证书并取消当前请求
        if (self.credential) {
            credential = self.credential;
            disposition = NSURLSessionAuthChallengeUseCredential;
        } else {
            disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
        }
    } else {
        //已经失败过则直接忽略证书并取消当前请求
        disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
    }
}
    
//向服务器返回
if (completionHandler) {
    completionHandler(disposition, credential);
}
```

#### NSURLSessionDataDelegate

##### 1. 连接建立时，第一次收到收到服务器响应头

`- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
 `
 
 - 这里会考虑两种情况：
 1.连接未报错并且返回statusCode不为304（资源未修改），则保存文件长度信息，并调用进度回调和发送通知
 2.连接报错，如果是304则直接取消任务并重置，否则取消任务。然后发送完成回调和通知。
 
 ```
//statusCode小于400说明不是客户端或服务器错误，不等于304说明文件已修改
//response对象的status code不存在，或者statusCode小于400且不为304，则记录将接收文件大小、发送进度回调和通知等操作
if (![response respondsToSelector:@selector(statusCode)] || (((NSHTTPURLResponse *)response).statusCode < 400 && ((NSHTTPURLResponse *)response).statusCode != 304)) {
    
    //文件大小长度
    NSInteger expected = (NSInteger)response.expectedContentLength;
    expected = expected > 0 ? expected : 0;
    self.expectedSize = expected;
    
    //调用所有进度回调
    for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
        progressBlock(0, expected, self.request.URL);
    }
    
    //初始化数据容器
    self.imageData = [[NSMutableData alloc] initWithCapacity:expected];
    //服务器第一次返回的响应数据
    self.response = response;
    
    //发送接收服务器响应通知
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadReceiveResponseNotification object:weakSelf];
    });
} else {
    NSUInteger code = ((NSHTTPURLResponse *)response).statusCode;
    
    //文件图片未改变则取消
    if (code == 304) {
        //完全取消该操作并重置
        [self cancelInternal];
    } else {
        //只是任务取消
        [self.dataTask cancel];
    }
    //发送下载停止通知
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:weakSelf];
    });
    //发送完成block
    [self callCompletionBlocksWithError:[NSError errorWithDomain:NSURLErrorDomain code:((NSHTTPURLResponse *)response).statusCode userInfo:nil]];
    //修改操作状态，主动触发KVO
    [self done];
}
    
//允许连接继续
if (completionHandler) {
    completionHandler(NSURLSessionResponseAllow);
}
 ```
 
##### 2.持续接收图片数据

`- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data`

###### 1.添加数据到容器中

```
[self.imageData appendData:data];
```
    
###### 2.返回以接收图片数据的展示图片

```
if ((self.options & SDWebImageDownloaderProgressiveDownload) && self.expectedSize > 0) {
    
    //接收总大小是否达到最大接收值
    NSData *imageData = [self.imageData copy];
    const NSInteger totalSize = imageData.length;
    BOOL finished = (totalSize >= self.expectedSize);
    
    //创建一个解码器
    if (!self.progressiveCoder) {
        // We need to create a new instance for progressive decoding to avoid conflicts
        for (id<SDWebImageCoder>coder in [SDWebImageCodersManager sharedInstance].coders) {
            if ([coder conformsToProtocol:@protocol(SDWebImageProgressiveCoder)] &&
                [((id<SDWebImageProgressiveCoder>)coder) canIncrementallyDecodeFromData:imageData]) {
                self.progressiveCoder = [[[coder class] alloc] init];
                break;
            }
        }
    }
    
    //递增解码图片数据
    UIImage *image = [self.progressiveCoder incrementallyDecodedImageWithData:imageData finished:finished];
    if (image) {
        //根据URL获取缓存存储的URL
        NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:self.request.URL];
        //根据scale缩放图片大小
        image = [self scaledImageForKey:key image:image];
        //解压缩图片
        if (self.shouldDecompressImages) {
            image = [[SDWebImageCodersManager sharedInstance] decompressedImageWithImage:image data:&data options:@{SDWebImageCoderScaleDownLargeImagesKey: @(NO)}];
        }
        //返回图片数据给所有完成回调
        [self callCompletionBlocksWithImage:image imageData:nil error:nil finished:NO];
    }
}
```

###### 3.调用进度回调

```
for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
    progressBlock(self.imageData.length, self.expectedSize, self.request.URL);
}
```


##### 3.服务器响应回调缓存

```
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
    
    //不缓存则将缓存置空
    NSCachedURLResponse *cachedResponse = proposedResponse;
    if (self.request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData) {
        // Prevents caching of responses
        cachedResponse = nil;
    }
    
    if (completionHandler) {
        completionHandler(cachedResponse);
    }
}
```