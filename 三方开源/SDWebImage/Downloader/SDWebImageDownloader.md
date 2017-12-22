## SDWebImageDownloader

### SDWebImageDownloadToken
和每个下载任务的管理token对象，用于取消任务

```
@interface SDWebImageDownloadToken : NSObject

@property (nonatomic, strong, nullable) NSURL *url;//下载地址
@property (nonatomic, strong, nullable) id downloadOperationCancelToken;//下载操作取消token

@end
```

### SDWebImageDownloader

##### 属性

```
//下载队列
@property (strong, nonatomic, nonnull) NSOperationQueue *downloadQueue;
//最近添加的操作，weak指针引用。方便操作结束后释放。
@property (weak, nonatomic, nullable) NSOperation *lastAddedOperation;
//创建操作的类
@property (assign, nonatomic, nullable) Class operationClass;
//存储下载url和下载操作的映射
@property (strong, nonatomic, nonnull) NSMutableDictionary<NSURL *, SDWebImageDownloaderOperation *> *URLOperations;
//头部header field
@property (strong, nonatomic, nullable) SDHTTPHeadersMutableDictionary *HTTPHeaders;

//用于对所有下载操作的网络响应处理进行序列化的队列
@property (SDDispatchQueueSetterSementics, nonatomic, nullable) dispatch_queue_t barrierQueue;

// The session in which data tasks will run
@property (strong, nonatomic) NSURLSession *session;
```

##### 两个队列：

NSOpeationQueue用于下载操作的管理。
dispatch_queue_t一个并行队列用于任务创建和数据访问的异步栏栅处理，保证数据安全。

##### 一个NSURLSession会话：

用于作为NSURLSessionTaskDelegate和NSURLSessionDataDelegate消息转发中枢，将消息传递到对应任务中，有具体任务自己响应处理。
用于作为下载操作的session管理。

##### 下载选项

```
typedef NS_OPTIONS(NSUInteger, SDWebImageDownloaderOptions) {
    //低优先级
    SDWebImageDownloaderLowPriority = 1 << 0,
    //进度下载
    SDWebImageDownloaderProgressiveDownload = 1 << 1,
    //默认情况请求是不使用NSURLCache进行缓存，使用该标识会NSURLCache会被启用
    SDWebImageDownloaderUseNSURLCache = 1 << 2,
    //不使用缓存的response cache
    SDWebImageDownloaderIgnoreCachedResponse = 1 << 3,
    //进入后台时向系统申请更多的时间来继续图片的下载，超时的图片未下载完成则取消下载操作
    SDWebImageDownloaderContinueInBackground = 1 << 4,
    //启用请求的NSHTTPCookieStore
    SDWebImageDownloaderHandleCookies = 1 << 5,
    //允许无效证书的验证
    SDWebImageDownloaderAllowInvalidSSLCertificates = 1 << 6,
    //高优先级队列进行下载
    SDWebImageDownloaderHighPriority = 1 << 7,
    //压缩下载的大图片
    SDWebImageDownloaderScaleDownLargeImages = 1 << 8,
}
```

##### 任务执行关系

通过添加operatio直接的依赖实现FIFO、LIFO

```
typedef NS_ENUM(NSInteger, SDWebImageDownloaderExecutionOrder) {
    //先进先出，队列算法
    SDWebImageDownloaderFIFOExecutionOrder,
    //先进后出，栈算法
    SDWebImageDownloaderLIFOExecutionOrder
};
```

##### 定义了一个可变和一个不可变的HTTP header 字典容器

```
typedef NSDictionary<NSString *, NSString *> SDHTTPHeadersDictionary;
typedef NSMutableDictionary<NSString *, NSString *> SDHTTPHeadersMutableDictionary;
```

##### + (void)initialize 

这里在第一次使用该类时，会检测是否导入了SDNetworkActivityIndicator，有则注册通知监听任务的状态来显示进度指示器。

```
 if (NSClassFromString(@"SDNetworkActivityIndicator")) {
 	id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];

    // Remove observer in case it was previously added.
    [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];
	//	add observer for task
    [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                             selector:NSSelectorFromString(@"startActivity")
                                                 name:SDWebImageDownloadStartNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                             selector:NSSelectorFromString(@"stopActivity")
                                                 name:SDWebImageDownloadStopNotification object:nil];
 }
```

##### 创建Session

```
- (void)createNewSessionWithConfiguration:(NSURLSessionConfiguration *)sessionConfiguration {
    
    //取消队列中的所有下载任务
    [self cancelAllDownloads];
    
    //取消之前的session
    if (self.session) {
        [self.session invalidateAndCancel];
    }
    //设置session下所有请求的超时时间
    sessionConfiguration.timeoutIntervalForRequest = self.downloadTimeout;

    //给session传输一个nil代理队列，session会自动创建一个串行操作队列来管理所有代理
    self.session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                 delegate:self
                                            delegateQueue:nil];
}

```

##### 下载操作类的设置

操作类是NSOperation的子类，并且在遵守SDWebImageDownloaderOperationInterface协议，否则使用SDWebImageDownloaderOperation

```
- (void)setOperationClass:(nullable Class)operationClass {
    
    if (operationClass && [operationClass isSubclassOfClass:[NSOperation class]] && [operationClass conformsToProtocol:@protocol(SDWebImageDownloaderOperationInterface)]) {
        _operationClass = operationClass;
    } else {
        _operationClass = [SDWebImageDownloaderOperation class];
    }
}
```

##### 创建任务

使用如下API创建下载任务，将创建过程通过createCallback传入该API中
- 在createCallback中创建任务并返回管理的任务
- API返回与任务管理的token对象

```
- (nullable SDWebImageDownloadToken *)addProgressCallback:
                                           completedBlock:
                                                   forURL:
                                           createCallback:(SDWebImageDownloaderOperation *(^)(void))createCallback
```

任务创建过程

```
__strong __typeof (wself) sself = wself;
        
//请求超时时间
NSTimeInterval timeoutInterval = sself.downloadTimeout;
if (timeoutInterval == 0.0) {
    timeoutInterval = 15.0;
}
    
//根据缓存策略创建request
NSURLRequestCachePolicy cachePolicy = options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData;
NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url
                                                            cachePolicy:cachePolicy
                                                        timeoutInterval:timeoutInterval];
    
request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
request.HTTPShouldUsePipelining = YES;//公用TCP通道
    
//对请求头部信息进行筛选
if (sself.headersFilter) {
    request.allHTTPHeaderFields = sself.headersFilter(url, [sself.HTTPHeaders copy]);
}
else {
    request.allHTTPHeaderFields = sself.HTTPHeaders;
}
    
//创建下载操作
SDWebImageDownloaderOperation *operation = [[sself.operationClass alloc] initWithRequest:request inSession:sself.session options:options];
operation.shouldDecompressImages = sself.shouldDecompressImages;
    
//请求验证
if (sself.urlCredential) {
    operation.credential = sself.urlCredential;
} else if (sself.username && sself.password) {
    operation.credential = [NSURLCredential credentialWithUser:sself.username password:sself.password persistence:NSURLCredentialPersistenceForSession];
}
    
//下载操作的优先级
if (options & SDWebImageDownloaderHighPriority) {
    operation.queuePriority = NSOperationQueuePriorityHigh;
} else if (options & SDWebImageDownloaderLowPriority) {
    operation.queuePriority = NSOperationQueuePriorityLow;
}
    
//将操作添加到队列中
[sself.downloadQueue addOperation:operation];
    
//后进先出，则将上一个操作与当前操作建立依赖关系
if (self.lastAddedOperation && sself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
    // Emulate LIFO execution order by systematically adding new operations as last operation's dependency
    [sself.lastAddedOperation addDependency:operation];
    sself.lastAddedOperation = operation;
    }
```

##### 创建与操作关联的downloadToken对象

采用栏栅块创建，保证线程安全

```
__block SDWebImageDownloadToken *token = nil;
dispatch_barrier_sync(self.barrierQueue, ^{
    SDWebImageDownloaderOperation *operation = self.URLOperations[url];
    //操作不存在则创建并绑定
    if (!operation) {
        //创建操作并保存
        operation = createCallback();
        self.URLOperations[url] = operation;

        //设置操作完成后在并行队列中串行处理动作
        __weak SDWebImageDownloaderOperation *woperation = operation;
        operation.completionBlock = ^{
			dispatch_barrier_sync(self.barrierQueue, ^{
				SDWebImageDownloaderOperation *soperation = woperation;
                //已经被取消
				if (!soperation) return;
                //移除操作
				if (self.URLOperations[url] == soperation) {
					[self.URLOperations removeObjectForKey:url];
				};
			});
        };
    }
    //关联progressBlock和completeBlock，并返回关联的token
    id downloadOperationCancelToken = [operation addHandlersForProgress:progressBlock completed:completedBlock];
    //创建downloadToken对象
    token = [SDWebImageDownloadToken new];
    token.url = url;
    token.downloadOperationCancelToken = downloadOperationCancelToken;
});
```

##### 取消下载任务

在并行队列中栏栅串行处理取消任务，保证数据访问安全。

```
- (void)cancel:(nullable SDWebImageDownloadToken *)token {
    
    dispatch_barrier_async(self.barrierQueue, ^{
        SDWebImageDownloaderOperation *operation = self.URLOperations[token.url];
        BOOL canceled = [operation cancel:token.downloadOperationCancelToken];
        if (canceled) {
            [self.URLOperations removeObjectForKey:token.url];
        }
    });
}
```

##### 根据NSURLSessionTask获取操作

```
根据NSURLSessionTask创建SDWebImageDownloaderOperation
- (SDWebImageDownloaderOperation *)operationWithTask:(NSURLSessionTask *)task {
    SDWebImageDownloaderOperation *returnOperation = nil;
    for (SDWebImageDownloaderOperation *operation in self.downloadQueue.operations) {
        if (operation.dataTask.taskIdentifier == task.taskIdentifier) {
            returnOperation = operation;
            break;
        }
    }
    return returnOperation;
}
```

##### 协议NSURLSessionTaskDelegate或NSURLSessionDataDelegate

主要作用就是做一个代理消息的转发。下载器负责接收所有task的代理，然后转发到单个任务的代理方法中去。

```
SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

//任务完成
[dataOperation URLSession:session task:task didCompleteWithError:error];
或
//请求收到挑战
[dataOperation URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
```