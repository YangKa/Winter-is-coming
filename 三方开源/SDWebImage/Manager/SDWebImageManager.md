## SDWebImageManager

#### 图片选项 SDWebImageOptions

```
typedef NS_OPTIONS(NSUInteger, SDWebImageOptions) {

	//默认情况下请求失败后该url会被添加到黑名单不在重试连接。这个flag会禁止添加到黑名单
    SDWebImageRetryFailed = 1 << 0,
    
    //低优先级加载，将原来在UI操作时就开始加载延迟到UIScrollView滚动减速时进行加载
    SDWebImageLowPriority = 1 << 1,
    
    //只进行memory的缓存策略
    SDWebImageCacheMemoryOnly = 1 << 2,
    
    //允许图片进渐式下载显示，边下载边显示
    SDWebImageProgressiveDownload = 1 << 3,
    
    //用于处理相同URL，图片资源改变的情况。图片刷新时，会调用completeBlock
    //即使图片在缓存中，根据http响应头中的选项控制，有时也需要更新图片资源
    //损失一点性能来使用NSURLCahce代替SDWebImage操作disk缓存
    SDWebImageRefreshCached = 1 << 4,
    
    //请求在应用进入后台时继续执行，这里需要向系统申请更多的后台时间
    SDWebImageContinueInBackground = 1 << 5,
    
    //使用http cookies
    SDWebImageHandleCookies = 1 << 6,
    
    //证书验证时允许使用无效的证书，证书操作会使用默认的操作方式，也就是不对证书做验证
    SDWebImageAllowInvalidSSLCertificates = 1 << 7,
    
    //会在图片请求入队时插队在最前面
    SDWebImageHighPriority = 1 << 8,
    
    //延迟占位图的显示，直到图片下载完成
    SDWebImageDelayPlaceholder = 1 << 9,
    
    //处理动画图片
    SDWebImageTransformAnimatedImage = 1 << 10,
    
    //默认图片下载完成会自动显示，这个flag需要手动加载显示图片，这样显示前就可以对图片做一些其它的处理操作
    SDWebImageAvoidAutoSetImage = 1 << 11,
    
    //默认情况图片是根据原始大小进行解压的。这个flag会根据设备内存对图片进行scaledown
    SDWebImageScaleDownLargeImages = 1 << 12
}
```

#### block回调

```
//内部完成回调
typedef void(^SDExternalCompletionBlock)(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL);

//外部完成回调
typedef void(^SDInternalCompletionBlock)(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL);

//转换URL到缓存的key，会剔除url中动态的部分，比如参数
typedef NSString * _Nullable (^SDWebImageCacheKeyFilterBlock)(NSURL * _Nullable url);
```

#### 协议SDWebImageManagerDelegate

```
@protocol SDWebImageManagerDelegate <NSObject>
@optional

//当缓存中不存在图片记录需要下载时调用
- (BOOL)imageManager:(nonnull SDWebImageManager *)imageManager shouldDownloadImageForURL:(nullable NSURL *)imageURL;

//在图片下载缓存到disk和memory中之前，允许对图片直接进行transform处理
//这个方法会在全局队列中调用
- (nullable UIImage *)imageManager:(nonnull SDWebImageManager *)imageManager transformDownloadedImage:(nullable UIImage *)image withURL:(nullable NSURL *)imageURL;

@end
```

### SDWebImageCombinedOperation : NSObject <SDWebImageOperation>

#### 属性

```
//任务是否已被取消
@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
//无参数回调
@property (copy, nonatomic, nullable) SDWebImageNoParamsBlock cancelBlock;
//缓存操作
@property (strong, nonatomic, nullable) NSOperation *cacheOperation;
```

##### 取消

```
//如果任务已经取消了，则直接调用取消回调
- (void)setCancelBlock:(nullable SDWebImageNoParamsBlock)cancelBlock {
    if (self.isCancelled) {
        if (cancelBlock) {
            cancelBlock();
        }
        _cancelBlock = nil; // don't forget to nil the cancelBlock, otherwise we will get crashes
    } else {
        _cancelBlock = [cancelBlock copy];
    }
}

//同步取消，只能被取消一次，采用同步块处理
- (void)cancel {
    @synchronized(self) {
        self.cancelled = YES;
        if (self.cacheOperation) {
            [self.cacheOperation cancel];
            self.cacheOperation = nil;
        }
        if (self.cancelBlock) {
            self.cancelBlock();
            self.cancelBlock = nil;
        }
    }
}
```

### SDWebImageManager

- 全程使用同步块@synchronize对存放运行操作容器进行线程保护。

#### 初始化

```
- (nonnull instancetype)init {
    SDImageCache *cache = [SDImageCache sharedImageCache];
    SDWebImageDownloader *downloader = [SDWebImageDownloader sharedDownloader];
    return [self initWithCache:cache downloader:downloader];
}

- (nonnull instancetype)initWithCache:(nonnull SDImageCache *)cache downloader:(nonnull SDWebImageDownloader *)downloader {
    if ((self = [super init])) {
        _imageCache = cache;
        _imageDownloader = downloader;
        _failedURLs = [NSMutableSet new];
        _runningOperations = [NSMutableArray new];
    }
    return self;
}
```

#### 检查缓存是否存在

- 1.获取url对应的缓存key`NSString *key = [self cacheKeyForURL:url];`
- 2.先检查self.imageCache中的memory，然后检查disk中是否存在

```
- (void)cachedImageExistsForURL:(nullable NSURL *)url
                     completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    BOOL isInMemoryCache = ([self.imageCache imageFromMemoryCacheForKey:key] != nil);
    
    if (isInMemoryCache) {
        // making sure we call the completion block on the main queue
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(YES);
            }
        });
        return;
    }
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}
```

#### 保存缓存

```
- (void)saveImageToCache:(nullable UIImage *)image forURL:(nullable NSURL *)url {
    if (image && url) {
        NSString *key = [self cacheKeyForURL:url];
        [self.imageCache storeImage:image forKey:key toDisk:YES completion:nil];
    }
}
```

#### 开启下载请求

`API:`

```
- (id <SDWebImageOperation>)loadImageWithURL:(nullable NSURL *)url
                                     options:(SDWebImageOptions)options
                                    progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                   completed:(nullable SDInternalCompletionBlock)completedBlock
```

##### 1.参数校验

```
// 防止url是字符串
if ([url isKindOfClass:NSString.class]) {
    url = [NSURL URLWithString:(NSString *)url];
}
// 防止url是一个NSNULL对象
if (![url isKindOfClass:NSURL.class]) {
    url = nil;
}
```

##### 2.创建合并操作

```
__block SDWebImageCombinedOperation *operation = [SDWebImageCombinedOperation new];
__weak SDWebImageCombinedOperation *weakOperation = operation;
```

##### 3.黑名单检测

```
//是否是黑名单上的url
BOOL isFailedUrl = NO;
if (url) {
    @synchronized (self.failedURLs) {
        isFailedUrl = [self.failedURLs containsObject:url];
    }
}
    
//url无效或者是黑名单url并且不容许重试，则调用完成回调返回文件不存在错误NSURLErrorFileDoesNotExist
if (url.absoluteString.length == 0 || (!(options & SDWebImageRetryFailed) && isFailedUrl)) {
    [self callCompletionBlockForOperation:operation completion:completedBlock error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil] url:url];
    return operation;
}
```

##### 4.添加到运行中操作集合

```
@synchronized (self.runningOperations) {
    [self.runningOperations addObject:operation];
}
```

##### 5.查询缓存中的图片数据

```
//根据url获取缓存key
NSString *key = [self cacheKeyForURL:url];
operation.cacheOperation = [self.imageCache queryCacheOperationForKey:key done:^(UIImage *cachedImage, NSData *cachedData, SDImageCacheType cacheType) {
       //请求完成处理                                                                                   
}];
```  


###### 5.1.查询返回时请求已被取消，则移除请求记录并返回

```
if (operation.isCancelled) {
    [self safelyRemoveOperationFromRunning:operation];
    return;
}
```

###### 5.2缓存图片不存在或缓存需要更新，并且该url允许下载，则发出请求操作

```
if ((!cachedImage || options & SDWebImageRefreshCached) && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url])) {
    
    //如果缓存图片存在，则回调返回图片数据，并继续下载图片进行更新
    if (cachedImage) {
        [self callCompletionBlockForOperation:weakOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
    }

    // 根据图片选项创建下载器的选项配置
    SDWebImageDownloaderOptions downloaderOptions = 0;
    if (options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
    if (options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
    if (options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
    if (options & SDWebImageContinueInBackground) downloaderOptions |= SDWebImageDownloaderContinueInBackground;
    if (options & SDWebImageHandleCookies) downloaderOptions |= SDWebImageDownloaderHandleCookies;
    if (options & SDWebImageAllowInvalidSSLCertificates) downloaderOptions |= SDWebImageDownloaderAllowInvalidSSLCertificates;
    if (options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
    if (options & SDWebImageScaleDownLargeImages) downloaderOptions |= SDWebImageDownloaderScaleDownLargeImages;
    
    //如果缓存图片存在并需要更新图片
    if (cachedImage && options & SDWebImageRefreshCached) {
        //强制关闭进度式下载显示
        downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
        //需要忽视缓存响应
        downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
    }
    
    //创建下载任务
    SDWebImageDownloadToken *subOperationToken = [self.imageDownloader downloadImageWithURL:url
                                                                                    options:downloaderOptions
                                                                                   progress:progressBlock
                                                                                  completed:^(UIImage *downloadedImage, NSData *downloadedData, NSError *error, BOOL finished) {
                                                                                      
        __strong __typeof(weakOperation) strongOperation = weakOperation;
        if (!strongOperation || strongOperation.isCancelled) {
            //任务已经被取消
        } else if (error) {
            //下载失败，则调用完成回调
            [self callCompletionBlockForOperation:strongOperation completion:completedBlock error:error url:url];
            //不满足以下错误则加入黑名单
            if (   error.code != NSURLErrorNotConnectedToInternet
                && error.code != NSURLErrorCancelled
                && error.code != NSURLErrorTimedOut
                && error.code != NSURLErrorInternationalRoamingOff
                && error.code != NSURLErrorDataNotAllowed
                && error.code != NSURLErrorCannotFindHost
                && error.code != NSURLErrorCannotConnectToHost
                && error.code != NSURLErrorNetworkConnectionLost) {
                @synchronized (self.failedURLs) {
                    [self.failedURLs addObject:url];
                }
            }
        }else {
            //请求成功则从黑名单中移除记录
            if ((options & SDWebImageRetryFailed)) {
                @synchronized (self.failedURLs) {
                    [self.failedURLs removeObject:url];
                }
            }
            //是否缓存到disk
            BOOL cacheOnDisk = !(options & SDWebImageCacheMemoryOnly);
            
            //只是刷新本地缓存，不需要缓存，如果下载图片为空，则都nothing
            if (options & SDWebImageRefreshCached && cachedImage && !downloadedImage) {
                
            } else if (downloadedImage
                       && (!downloadedImage.images || (options & SDWebImageTransformAnimatedImage))
                       && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]) {
                
                //全局队列高优先级处理
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    //调用代理，获取transform后的图片
                    UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];
                    //图片处理完成兵器并且请求结束，则缓存图片
                    if (transformedImage && finished) {
                        BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                        //图片被transfrom，则需要重新计算imageData
                        [self.imageCache storeImage:transformedImage imageData:(imageWasTransformed ? nil : downloadedData) forKey:key toDisk:cacheOnDisk completion:nil];
                    }
                    //完成回调
                    [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:transformedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                });
                
            } else {
                //缓存图片
                if (downloadedImage && finished) {
                    [self.imageCache storeImage:downloadedImage imageData:downloadedData forKey:key toDisk:cacheOnDisk completion:nil];
                }
                //完成回调
                [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:downloadedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
            }
            
        }
         
                                                                                 
        if (finished) {//下载结束，移除正在操作记录
            [self safelyRemoveOperationFromRunning:strongOperation];
        }
    }];
    
    //给操作添加cancel处理回调
    @synchronized(operation) {
        // Need same lock to ensure cancelBlock called because cancel method can be called in different queue
        operation.cancelBlock = ^{
            [self.imageDownloader cancel:subOperationToken];
            __strong __typeof(weakOperation) strongOperation = weakOperation;
            [self safelyRemoveOperationFromRunning:strongOperation];
        };
    }
    
}
```

###### 5.3 图片缓存存在，调用完成回调返回图片数据并移除该请求操作

```
else if (cachedImage) {
    
    __strong __typeof(weakOperation) strongOperation = weakOperation;
    [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
    [self safelyRemoveOperationFromRunning:operation];
    
}
        ```
   
###### 5.4 缓存不存在，并且也不允许请求，则直接调用完成回调并移除该请求操作

```
else {
    
    // Image not in cache and download disallowed by delegate
    __strong __typeof(weakOperation) strongOperation = weakOperation;
    [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:nil data:nil error:nil cacheType:SDImageCacheTypeNone finished:YES url:url];
    [self safelyRemoveOperationFromRunning:operation];
    
}
```

#### 完成回调

```
- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  image:(nullable UIImage *)image
                                   data:(nullable NSData *)data
                                  error:(nullable NSError *)error
                              cacheType:(SDImageCacheType)cacheType
                               finished:(BOOL)finished
                                    url:(nullable NSURL *)url {
    dispatch_main_async_safe(^{
        if (operation && !operation.isCancelled && completionBlock) {
            completionBlock(image, data, error, cacheType, finished, url);
        }
    });
}
```

#### 运行中操作管理

##### 取消下载请求

```
@synchronized (self.runningOperations) {
        NSArray<SDWebImageCombinedOperation *> *copiedOperations = [self.runningOperations copy];
        //向集合所有对象发送cancel消息
        [copiedOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeAllObjects];
}
```

##### 是否正在下载

```
- (BOOL)isRunning {
    BOOL isRunning = NO;
    @synchronized (self.runningOperations) {
        isRunning = (self.runningOperations.count > 0);
    }
    return isRunning;
}
```

##### 移除操作

```
@synchronized (self.runningOperations) {
    if (operation) {
        [self.runningOperations removeObject:operation];
    }
}
```