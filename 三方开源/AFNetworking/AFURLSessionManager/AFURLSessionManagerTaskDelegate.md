## AFURLSessionManagerTaskDelegate

作为每个task任务的代理对象主要负责三点：

1. 设置uploadProgress、downloadProgress，将progress的状态的状态控制和task绑定
2. KVO监听上传和下载progress的进度fractionCompleted变化
3. task完成任务的代理、dataTask数据的接收、downloadTask下载完成后的临时文件转移

#### 协议：

`遵守NSURLSessionTaskDelegate`、`NSURLSessionDataDelegate`、`NSURLSessionDownloadDelegate`

#### 关键属性：

```
//会话管理
@property (nonatomic, weak) AFURLSessionManager *manager;

//临时数据容器、上传和下载进度对象
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSProgress *uploadProgress;
@property (nonatomic, strong) NSProgress *downloadProgress;

//上传进度、下载进度、请求结束回调
@property (nonatomic, copy) AFURLSessionTaskProgressBlock uploadProgressBlock;
@property (nonatomic, copy) AFURLSessionTaskProgressBlock downloadProgressBlock;
@property (nonatomic, copy) AFURLSessionTaskCompletionHandler completionHandler;
```

#### 进度监听设置

`- (void)setupProgressForTask:(NSURLSessionTask *)task`

- 设置uploadProgress、downloadProgress执行进度暂停、启动和取消的回调
- KVO监听NSURLSessionTask任务上传和下载的进度
- KVO监听上传和下载progress的进度fractionCompleted变化

#### KVO响应

- 将任务上传下载进度同步到progress
- progress的进度改变分别调用各自的回调

```
	 if ([object isKindOfClass:[NSURLSessionTask class]] || [object isKindOfClass:[NSURLSessionDownloadTask class]]) {
        
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesReceived))]) {
            
            self.downloadProgress.completedUnitCount = [change[NSKeyValueChangeNewKey] longLongValue];
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesExpectedToReceive))]) {
            
            self.downloadProgress.totalUnitCount = [change[NSKeyValueChangeNewKey] longLongValue];
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesSent))]) {
            
            self.uploadProgress.completedUnitCount = [change[NSKeyValueChangeNewKey] longLongValue];
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(countOfBytesExpectedToSend))]) {
            self.uploadProgress.totalUnitCount = [change[NSKeyValueChangeNewKey] longLongValue];
        }
    }
    else if ([object isEqual:self.downloadProgress]) {
        if (self.downloadProgressBlock) {
            self.downloadProgressBlock(object);
        }
    }
    else if ([object isEqual:self.uploadProgress]) {
        if (self.uploadProgressBlock) {
            self.uploadProgressBlock(object);
        }
    }
```

##### NSURLSessionTaskDelegate

- 1.释放接收的self.mutableData数据，转移到局部变量中
- 2.创建userInfo字典，作为发送请求结束通知的附加数据
- 3.有报错，则直接返回完成回调和发送完成通知。如没有定义group或queue，则使用默认的group和主队列
- 4.没有报错，则现在url_session_manager_processing_queue（）中对数据进行序列化，然后返回完成回调和发送完成通知。


```
- (void)URLSession:(__unused NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
    __strong AFURLSessionManager *manager = self.manager;
    
    //接收的数据
    NSData *data = nil;
    if (self.mutableData) {
        data = [self.mutableData copy];
        //请求已结束，不在需要使用，释放掉增加内存
        self.mutableData = nil;
    }

    //userInfo 用于发送通知
    __block NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[AFNetworkingTaskDidCompleteResponseSerializerKey] = manager.responseSerializer;
    //有下载文件保存地址则返回地址，没有则尝试保存下载数据
    if (self.downloadFileURL) {
        userInfo[AFNetworkingTaskDidCompleteAssetPathKey] = self.downloadFileURL;
    } else if (data) {
        userInfo[AFNetworkingTaskDidCompleteResponseDataKey] = data;
    }
    ////回调返回的group和执行队列
    __block id responseObject = nil;
    __block dispatch_group_t group = manager.completionGroup ?: url_session_manager_completion_group();
    __block dispatch_queue_t queue = manager.completionQueue ?: dispatch_get_main_queue();
    
    if (error) {
        userInfo[AFNetworkingTaskDidCompleteErrorKey] = error;
        
        dispatch_group_async(group, queue, ^{
            //返回回调
            if (self.completionHandler) {
                self.completionHandler(task.response, responseObject, error);
            }
            //通知需要在主线程中发送，主队列中只有一个线程并且是主线程。
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
            });
        });
    } else {
    	//url_session_manager_processing_queue 数据解析的队列
        dispatch_async(url_session_manager_processing_queue(), ^{
        
            NSError *serializationError = nil;
            if (self.downloadFileURL) {//下载请求则返回文件地址
                responseObject = self.downloadFileURL;
            }else{
                //校验和序列化数据
                responseObject = [manager.responseSerializer responseObjectForResponse:task.response data:data error:&serializationError];
            }
            
            if (responseObject) {
                userInfo[AFNetworkingTaskDidCompleteSerializedResponseKey] = responseObject;
            }
            if (serializationError) {
                userInfo[AFNetworkingTaskDidCompleteErrorKey] = serializationError;
            }

            dispatch_group_async(group, queue, ^{
                
                //返回回调
                if (self.completionHandler) {
                    self.completionHandler(task.response, responseObject, error);
                }
                
                //通知需要在主线程中发送，主队列中只有一个线程并且是主线程。
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:AFNetworkingTaskDidCompleteNotification object:task userInfo:userInfo];
                });
            });
        });
    }
#pragma clang diagnostic pop
}
```

##### NSURLSessionDataTaskDelegate

添加返回的数据到self.mutableData容器中

```
- (void)URLSession:(__unused NSURLSession *)session
          dataTask:(__unused NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    [self.mutableData appendData:data];
}
```

##### NSURLSessionDownloadTaskDelegate

获取文件转移地址，转移临时文件到相应地址。转移失败则发送错误通知。

```
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    NSError *fileManagerError = nil;
    self.downloadFileURL = nil;

    if (self.downloadTaskDidFinishDownloading) {
        //返回自定义的文件存储地址
        self.downloadFileURL = self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        
        if (self.downloadFileURL) {
            //转移临时文件到指定位置
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:self.downloadFileURL error:&fileManagerError];
            //发送文件转移错误通知
            if (fileManagerError) {
                [[NSNotificationCenter defaultCenter] postNotificationName:AFURLSessionDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:fileManagerError.userInfo];
            }
        }
    }
}
```
