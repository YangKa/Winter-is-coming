## AFHTTPSessionManager

继承AFURLSessionManager，提供对HTTP的访问接口。

主要属性有三个：

```
请求地址
@property (readonly, nonatomic, strong, nullable) NSURL *baseURL;

请求序列化
@property (nonatomic, strong) AFHTTPRequestSerializer <AFURLRequestSerialization> * requestSerializer;

返回数据序列化
@property (nonatomic, strong) AFHTTPResponseSerializer <AFURLResponseSerialization> * responseSerializer;
```

初始化：

```
- (instancetype)initWithBaseURL:(NSURL *)url
           sessionConfiguration:(NSURLSessionConfiguration *)configuration
{
    self = [super initWithSessionConfiguration:configuration];
    if (!self) {
        return nil;
    }

    //地址尾部没有/，则追加一个'/'。保证后面追加地址时工作正常
    if ([[url path] length] > 0 && ![[url absoluteString] hasSuffix:@"/"]) {
        url = [url URLByAppendingPathComponent:@""];
    }
    self.baseURL = url;

    //HTTP基类请求解析器
    self.requestSerializer = [AFHTTPRequestSerializer serializer];
    
    //JSON类响应解析器
    self.responseSerializer = [AFJSONResponseSerializer serializer];

    return self;
}
```

#### 核心方法

- 尝试序列化请求数据，会添加HTTP header选项和对参数进行序列化
 
```
NSError *serializationError = nil;
    NSMutableURLRequest *request = [self.requestSerializer requestWithMethod:method URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString] parameters:parameters error:&serializationError];
    
    if (serializationError) {
        if (failure) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            dispatch_async(self.completionQueue ?: dispatch_get_main_queue(), ^{
                failure(nil, serializationError);
            });
#pragma clang diagnostic pop
        }

        return nil;
    }
```

- 调用父类的方法进行任务的创建

```
__block NSURLSessionDataTask *dataTask = nil;
    dataTask = [self dataTaskWithRequest:request
                          uploadProgress:uploadProgress
                        downloadProgress:downloadProgress
                       completionHandler:^(NSURLResponse * __unused response, id responseObject, NSError *error) {
        if (error) {
            if (failure) {
                failure(dataTask, error);
            }
        } else {
            if (success) {
                success(dataTask, responseObject);
            }
        }
    }];
```

#### GET 请求
发送一个请求来获取服务器上的某个资源。

```
- (NSURLSessionDataTask *)GET:(NSString *)URLString
                   parameters:(id)parameters
                     progress:(void (^)(NSProgress * _Nonnull))downloadProgress
                      success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
                      failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure
{
    //get请求可能是下载请求，需要downloadProgress
    NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"GET"
                                                        URLString:URLString
                                                       parameters:parameters
                                                   uploadProgress:nil
                                                 downloadProgress:downloadProgress
                                                          success:success
                                                          failure:failure];

    [dataTask resume];

    return dataTask;
}
```

#### POST 请求

`向服务器提交数据。`

```
NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"POST"
                                                        URLString:URLString
                                                       parameters:parameters
                                                   uploadProgress:uploadProgress
                                                 downloadProgress:nil
                                                          success:success
                                                          failure:failure];

    [dataTask resume];
```

`附件上传`

- 上传任务因为已经序列化过，不需要借助dataTaskWithHTTPMethod来创建任务，直接使用父类的uploadTaskWithStreamedRequest：progress：completionHandler：来创建即可

```
 //对上传数据进行序列化
    NSError *serializationError = nil;
    NSString *url = [[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString];
    NSMutableURLRequest *request = [self.requestSerializer multipartFormRequestWithMethod:@"POST"
                                                                                URLString:url parameters:parameters constructingBodyWithBlock:block error:&serializationError];
    //序列化失败则返回
    if (serializationError) {
        if (failure) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wgnu"
            dispatch_async(self.completionQueue ?: dispatch_get_main_queue(), ^{
                failure(nil, serializationError);
            });
#pragma clang diagnostic pop
        }

        return nil;
    }

    //创建上传任务
    __block NSURLSessionDataTask *task = [self uploadTaskWithStreamedRequest:request
                                                                    progress:uploadProgress
                                                           completionHandler:^(NSURLResponse * __unused response, id responseObject, NSError *error) {
                                                               
                                                                if (error) {
                                                                    if (failure) {
                                                                        failure(task, error);
                                                                    }
                                                                } else {
                                                                    if (success) {
                                                                        success(task, responseObject);
                                                                    }
                                                                }
                                                            }];
    [task resume];
```

#### HEAD 请求
和GET请求类似，只有HTTP头信息，不包含参数。可以用来判断服务器端某个资源是否存在

```
NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"HEAD"
                                                        URLString:URLString
                                                       parameters:parameters
                                                   uploadProgress:nil
                                                 downloadProgress:nil
                                                          success:^(NSURLSessionDataTask *task, __unused id responseObject) {
                                                                        if (success) {
                                                                            success(task);
                                                                        }
                                                                    }
                                                          failure:failure];

    [dataTask resume];
```

#### PUT 请求
PUT和POST极为相似，都是向服务器发送数据，但它们之间有一个重要区别，PUT通常指定了资源的存放位置，而POST则没有，POST的数据存放位置由服务器自己决定。

```
NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"PUT"
                                                        URLString:URLString
                                                       parameters:parameters
                                                   uploadProgress:nil
                                                 downloadProgress:nil
                                                          success:success
                                                          failure:failure];

[dataTask resume];
```

#### PATCH 请求
PATCH方法是新引入的，是对PUT方法的补充，用来对已知资源进行局部更新

```
NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"PATCH"
                                                        URLString:URLString
                                                       parameters:parameters
                                                   uploadProgress:nil
                                                 downloadProgress:nil
                                                          success:success
                                                          failure:failure];

[dataTask resume];
```

#### DELETE 请求
删除某一个资源。比如云上删除文件的请求。

```
NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"DELETE"
                                                        URLString:URLString
                                                       parameters:parameters
                                                   uploadProgress:nil
                                                 downloadProgress:nil
                                                          success:success
                                                          failure:failure];

    [dataTask resume];
```