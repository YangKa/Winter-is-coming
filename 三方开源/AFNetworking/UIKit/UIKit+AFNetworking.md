## UIActivityIndicatorView+AFNetworking

- 1.使用关联对象持有一个观察对象
- 2.将task赋值给观察对象，先移除通知后判断task是否在执行结束。没有则将task作为对应object参数并注册通知。
- 3.如果task.state不为NSURLSessionTaskStateRunning，则启动动画，否则停止动画
- 4.通过通知来控制动画的启动和显示

`这里没有做多任务之间的分离，收到的通知可能来至别的任务。`

```
- (void)setAnimatingWithStateOfTask:(NSURLSessionTask *)task {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    [notificationCenter removeObserver:self name:AFNetworkingTaskDidResumeNotification object:nil];
    [notificationCenter removeObserver:self name:AFNetworkingTaskDidSuspendNotification object:nil];
    [notificationCenter removeObserver:self name:AFNetworkingTaskDidCompleteNotification object:nil];
    
    if (task) {
        //任务存在且没有结束
        if (task.state != NSURLSessionTaskStateCompleted) {
            
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreceiver-is-weak"
#pragma clang diagnostic ignored "-Warc-repeated-use-of-weak"
            if (task.state == NSURLSessionTaskStateRunning) {
                [self.activityIndicatorView startAnimating];
            } else {
                [self.activityIndicatorView stopAnimating];
            }
#pragma clang diagnostic pop

            [notificationCenter addObserver:self selector:@selector(af_startAnimating) name:AFNetworkingTaskDidResumeNotification object:task];
            [notificationCenter addObserver:self selector:@selector(af_stopAnimating) name:AFNetworkingTaskDidCompleteNotification object:task];
            [notificationCenter addObserver:self selector:@selector(af_stopAnimating) name:AFNetworkingTaskDidSuspendNotification object:task];
        }
    }
}
```

## UIRefreshControl+AFNetworking

和UIActivityIndicatorView+AFNetworking方式一样，都是控制动画的开始和结束。

## UIProgressView+AFNetworking


- 1.通过关联对象保证上传和下载的动画设置
- 2.KVO观察任务的state状态和上传下载的数据量`countOfBytesReceived`和`countOfBytesSent`，分别设置上传和下载的context指针
- 3.在`observeValueForKeyPath：ofObject：change：context：`方法中检测context是否是上传和下载的void*指针，获取数据量和object即task对象总数据量的比。获取animation设置修改progressView的进度。
- 4.受到state的改变，如果是任务结束，则需要task移除观察者，这里用了try-catch来防止错误

KVO注册

```
	[task addObserver:self forKeyPath:@"state" options:(NSKeyValueObservingOptions)0 context:AFTaskCountOfBytesReceivedContext];
    [task addObserver:self forKeyPath:@"countOfBytesReceived" options:(NSKeyValueObservingOptions)0 context:AFTaskCountOfBytesReceivedContext];
```

KVO监听和移除

```
    if (context == AFTaskCountOfBytesSentContext || context == AFTaskCountOfBytesReceivedContext) {
        
        //上传进度改变
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesSent))]) {
            if ([object countOfBytesExpectedToSend] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setProgress:[object countOfBytesSent] / ([object countOfBytesExpectedToSend] * 1.0f) animated:self.af_uploadProgressAnimated];
                });
            }
        }
        //下载进度改变
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesReceived))]) {
            if ([object countOfBytesExpectedToReceive] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setProgress:[object countOfBytesReceived] / ([object countOfBytesExpectedToReceive] * 1.0f) animated:self.af_downloadProgressAnimated];
                });
            }
        }
        //任务状态改变
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(state))]) {
            //任务结束移除观察者
            if ([(NSURLSessionTask *)object state] == NSURLSessionTaskStateCompleted) {
                @try {
                    [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(state))];

                    if (context == AFTaskCountOfBytesSentContext) {
                        [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(countOfBytesSent))];
                    }
                    if (context == AFTaskCountOfBytesReceivedContext) {
                        [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(countOfBytesReceived))];
                    }
                }
                @catch (NSException * __unused exception) {
                }
            }
        }
    }
```


## UIWebView+AFNetworking


对task进行属性关联

```
- (void)loadRequest:(NSURLRequest *)request
           MIMEType:(NSString *)MIMEType
   textEncodingName:(NSString *)textEncodingName
           progress:(NSProgress * _Nullable __autoreleasing * _Nullable)progress
            success:(NSData * (^)(NSHTTPURLResponse *response, NSData *data))success
            failure:(void (^)(NSError *error))failure
{
    NSParameterAssert(request);

    //取消之前的请求
    if (self.af_URLSessionTask.state == NSURLSessionTaskStateRunning || self.af_URLSessionTask.state == NSURLSessionTaskStateSuspended) {
        [self.af_URLSessionTask cancel];
    }
    self.af_URLSessionTask = nil;
    
    __weak __typeof(self)weakSelf = self;
    NSURLSessionDataTask *dataTask;
    dataTask = [self.sessionManager
            GET:request.URL.absoluteString
            parameters:nil
            progress:nil
            success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
                __strong __typeof(weakSelf) strongSelf = weakSelf;
                
                //成功回调
                if (success) {
                    success((NSHTTPURLResponse *)task.response, responseObject);
                }
                
                //显示数据
                [strongSelf loadData:responseObject MIMEType:MIMEType textEncodingName:textEncodingName baseURL:[task.currentRequest URL]];

                //调用webViewDelegate代理方法，加载数据结束
                if ([strongSelf.delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
                    [strongSelf.delegate webViewDidFinishLoad:strongSelf];
                }
            }
            failure:^(NSURLSessionDataTask * _Nonnull task, NSError * _Nonnull error) {
                if (failure) {
                    failure(error);
                }
            }];
    
    //保存task
    self.af_URLSessionTask = dataTask;
    //如果progress不为空，则将progress指针指向task的downloadProgress
    if (progress != nil) {
        *progress = [self.sessionManager downloadProgressForTask:dataTask];
    }
    
    //启动任务
    [self.af_URLSessionTask resume];

    //开始加载数据
    if ([self.delegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [self.delegate webViewDidStartLoad:self];
    }
}
```


## UIButton+AFNetworking

分为容器图片和背景图片在不同状态下的在线加载显示。


#### 设置图片公共下载器

```
+ (void)setSharedImageDownloader:(AFImageDownloader *)imageDownloader;

+ (AFImageDownloader *)sharedImageDownloader;
```

#### 取消下载

```
- (void)cancelImageDownloadTaskForState:(UIControlState)state;

- (void)cancelBackgroundImageDownloadTaskForState:(UIControlState)state;
```

例如取消下载任务

```
- (void)cancelImageDownloadTaskForState:(UIControlState)state {
    AFImageDownloadReceipt *receipt = [self af_imageDownloadReceiptForState:state];
    if (receipt != nil) {
    	//取消任务
        [[self.class sharedImageDownloader] cancelTaskForImageDownloadReceipt:receipt];
        //移除关联记录
        [self af_setImageDownloadReceipt:nil forState:state];
    }
}
```

AFImageDownloader图片下载器在启动一个任务时会创建一个AFImageDownloadReceipt对象，它能方便的对任务进行取消。这样将对任务的操作进行转移，方便对多任务的处理。

#### static方法进行状态的转换和AFImageDownloadReceipt的对象关联保存。

分别对容器图片和背景图片的状态创建了四个AF状态。并进行对象关联

```
#pragma mark - 容器图片的转换

//创建四个AF状态分别对应UIControlState的状态
static char AFImageDownloadReceiptNormal;
static char AFImageDownloadReceiptHighlighted;
static char AFImageDownloadReceiptSelected;
static char AFImageDownloadReceiptDisabled;

static const char * af_imageDownloadReceiptKeyForState(UIControlState state) {
    switch (state) {
        case UIControlStateHighlighted:
            return &AFImageDownloadReceiptHighlighted;
        case UIControlStateSelected:
            return &AFImageDownloadReceiptSelected;
        case UIControlStateDisabled:
            return &AFImageDownloadReceiptDisabled;
        case UIControlStateNormal:
        default:
            return &AFImageDownloadReceiptNormal;
    }
}

//每个状态下都有一个下载器
- (AFImageDownloadReceipt *)af_imageDownloadReceiptForState:(UIControlState)state {
    return (AFImageDownloadReceipt *)objc_getAssociatedObject(self, af_imageDownloadReceiptKeyForState(state));
}

- (void)af_setImageDownloadReceipt:(AFImageDownloadReceipt *)imageDownloadReceipt
                           forState:(UIControlState)state
{
    objc_setAssociatedObject(self, af_imageDownloadReceiptKeyForState(state), imageDownloadReceipt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
```

#### 获取图片

- 需要给request设置接收类型为image

```
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
[request addValue:@"image/*" forHTTPHeaderField:@"Accept"];
```

下载图片请求，`采用[NSUUID UUID]生成随机字符串来作为receipt和下载任务的回调的验证条件`

```
- (void)setImageForState:(UIControlState)state
          withURLRequest:(NSURLRequest *)urlRequest
        placeholderImage:(nullable UIImage *)placeholderImage
                 success:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, UIImage *image))success
                 failure:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure
{
    //查询AFImageDownloadReceipt判断相同请求是否存在
    if ([self isActiveTaskURLEqualToURLRequest:urlRequest forState:state]) {
        return;
    }
    
    //取消之前的请求
    [self cancelImageDownloadTaskForState:state];
    //下载器
    AFImageDownloader *downloader = [[self class] sharedImageDownloader];
    //查询缓存
    id <AFImageRequestCache> imageCache = downloader.imageCache;
    UIImage *cachedImage = [imageCache imageforRequest:urlRequest withAdditionalIdentifier:nil];
    if (cachedImage) {
        
        //有缓存直接返回或直接显示图片
        if (success) {
            success(urlRequest, nil, cachedImage);
        } else {
            [self setImage:cachedImage forState:state];
        }
        //移除对象关联
        [self af_setImageDownloadReceipt:nil forState:state];
    } else {
        
        //没有缓存则先显示占位图
        if (placeholderImage) {
            [self setImage:placeholderImage forState:state];
        }
        
        //
        __weak __typeof(self)weakSelf = self;
        NSUUID *downloadID = [NSUUID UUID];//下载任务的随机标识
        AFImageDownloadReceipt *receipt;
        receipt = [downloader
                   downloadImageForURLRequest:urlRequest
                   withReceiptID:downloadID
                   success:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, UIImage * _Nonnull responseObject) {
                       
                       //检测是不是对应的请求返回
                       __strong __typeof(weakSelf)strongSelf = weakSelf;
                       if ([[strongSelf af_imageDownloadReceiptForState:state].receiptID isEqual:downloadID]) {
                           //设置了success则直接返回或则直接显示图片
                           if (success) {
                               success(request, response, responseObject);
                           } else if(responseObject) {
                               [strongSelf setImage:responseObject forState:state];
                           }
                           //移除对象关联
                           [strongSelf af_setImageDownloadReceipt:nil forState:state];
                       }

                   }
                   failure:^(NSURLRequest * _Nonnull request, NSHTTPURLResponse * _Nullable response, NSError * _Nonnull error) {
                       
                       __strong __typeof(weakSelf)strongSelf = weakSelf;
                       if ([[strongSelf af_imageDownloadReceiptForState:state].receiptID isEqual:downloadID]) {
                           if (failure) {
                               failure(request, response, error);
                           }
                           [strongSelf  af_setImageDownloadReceipt:nil forState:state];
                       }
                   }];
        
        //属性关联state与对应的receipt
        [self af_setImageDownloadReceipt:receipt forState:state];
    }
}
```









