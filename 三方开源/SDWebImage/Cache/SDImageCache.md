## SDImageCache

- 每个缓存器都有一个namespace用于区分，同时以域名作为disk保存目录的上一级目录。
- 持有的NSCache对象的name也是赋值namespace。
- 缓存分为disk和memory缓存。使用NSCahce的子类对象进行缓存保存，借助NSCache的自动清理缓存和线程安全的特性。
- 通过SDImageCacheConfig配置对象来设置缓存操作选项。
- 系统内存紧张时清除内存。
- 应用进入后台或将要退出时删除过期的文件，针对disk文件。
- NSCache是线程安全的，所以只对disk的访问进行安全控制，即在串行队列中访问，

`默认设置：`
- 使用memory缓存
- 缓存最初周期为一周
- 禁止iCloud
- 图片解压缩
- 最大缓存大小为0

#### 获取图片大小

直接计算像素数量作为图片大小
`return image.size.height * image.size.width * image.scale * image.scale;`

### SDImageCacheConfig
```
static const NSInteger kDefaultCacheMaxCacheAge = 60 * 60 * 24 * 7; // 1 week

@implementation SDImageCacheConfig

- (instancetype)init {
    if (self = [super init]) {
        _shouldDecompressImages = YES;
        _shouldDisableiCloud = YES;
        _shouldCacheImagesInMemory = YES;
        _diskCacheReadingOptions = 0;
        _maxCacheAge = kDefaultCacheMaxCacheAge;
        _maxCacheSize = 0;
    }
    return self;
}

@end
```

### AutoPurgeCache : NSCache

NSCache在系统内存紧张时会自动请求部分缓存，这里是之间注册内存警告通知然后一次清理所有内存缓存。
`[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];`

### SDImageCache

#### 属性

```
//缓存容器
@property (strong, nonatomic, nonnull) NSCache *memCache;
//disk保存路径
@property (strong, nonatomic, nonnull) NSString *diskCachePath;
//自定义路径
@property (strong, nonatomic, nullable) NSMutableArray<NSString *> *customPaths;
//串行操作队列
@property (SDDispatchQueueSetterSementics, nonatomic, nullable) dispatch_queue_t ioQueue;
```

#### 通知

```
//系统内存紧张时清除内存
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMemory) name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];

        //应用退出时删除过期文件
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deleteOldFiles)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];

        //应用进入后台时删除过期文件
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(backgroundDeleteOldFiles)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
```

#### 检查当前队列是不是 ioQueue

```
- (void)checkIfQueueIsIOQueue {
    const char *currentQueueLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    const char *ioQueueLabel = dispatch_queue_get_label(self.ioQueue);
    if (strcmp(currentQueueLabel, ioQueueLabel) != 0) {
        NSLog(@"This method should be called from the ioQueue");
    }
}
```

##### 生成缓存文件名

以字符串链接的md5签名作为文件名 + 原后缀
```
- (nullable NSString *)cachedFileNameForKey:(nullable NSString *)key {
    const char *str = key.UTF8String;
    if (str == NULL) {
        str = "";
    }
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSURL *keyURL = [NSURL URLWithString:key];
    NSString *ext = keyURL ? keyURL.pathExtension : key.pathExtension;
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%@",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15],
                           ext.length == 0 ? @"" : [NSString stringWithFormat:@".%@", ext]];//这里要添加后缀
    return filename;
}
```

##### 保存到memory

```
if (self.config.shouldCacheImagesInMemory) {
    NSUInteger cost = SDCacheCostForImage(image);
    [self.memCache setObject:image forKey:key cost:cost];
}
```

##### 保存image到disk

```
//串行队列中异步存储到disk中
dispatch_async(self.ioQueue, ^{
    //建立自动释放池
    //图片解码后的位图数据占用内存较大,将data提前释放增加可用内存
    @autoreleasepool {
        NSData *data = imageData;
        if (!data && image) {
            //没有提供数据，则使用SDWebImageCodersManager将image按照png的格式进行解码成data
            data = [[SDWebImageCodersManager sharedInstance] encodedDataWithImage:image format:SDImageFormatPNG];
        }
        //保存位图数据到disk
        [self storeImageDataToDisk:data forKey:key];
    }
    //回到主线程调用完成回调
    if (completionBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock();
        });
    }
});
```
##### 保存imageData到disk中

以传入的urlString进行MD5签名+后缀作为key，将解码后的imageData保存到disk中。

```
- (void)storeImageDataToDisk:(nullable NSData *)imageData forKey:(nullable NSString *)key {
    if (!imageData || !key) {
        return;
    }
    
    //操作队列不是ioQueue警告
    [self checkIfQueueIsIOQueue];
    
    //创建disk保存文件夹
    if (![_fileManager fileExistsAtPath:_diskCachePath]) {
        [_fileManager createDirectoryAtPath:_diskCachePath withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    
    //将图片链接md5签名后生成新的fileURL
    // get cache Path for image key
    NSString *cachePathForKey = [self defaultCachePathForKey:key];
    // transform to NSUrl
    NSURL *fileURL = [NSURL fileURLWithPath:cachePathForKey];
    
    //保存图片数据
    [_fileManager createFileAtPath:cachePathForKey contents:imageData attributes:nil];
    
    // 为该FileURL添加禁止iCloud备份标识
    if (self.config.shouldDisableiCloud) {
        [fileURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
}
```

##### 检测disk中图片是否存在

```
- (void)diskImageExistsWithKey:(nullable NSString *)key completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    
    dispatch_async(_ioQueue, ^{
        BOOL exists = [_fileManager fileExistsAtPath:[self defaultCachePathForKey:key]];
        // checking the key with and without the extension
        if (!exists) {//检测无后缀的key
            exists = [_fileManager fileExistsAtPath:[self defaultCachePathForKey:key].stringByDeletingPathExtension];
        }
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(exists);
            });
        }
    });
}
```

##### 获取disk图片

```
- (nullable UIImage *)diskImageForKey:(nullable NSString *)key {
    //获取图片数据
    NSData *data = [self diskImageDataBySearchingAllPathsForKey:key];
    if (data) {
        //编码图片
        UIImage *image = [[SDWebImageCodersManager sharedInstance] decodedImageWithData:data];
        //修改图片的scale
        image = [self scaledImageForKey:key image:image];
        //解压缩图片
        if (self.config.shouldDecompressImages) {
            image = [[SDWebImageCodersManager sharedInstance] decompressedImageWithImage:image data:&data options:@{SDWebImageCoderScaleDownLargeImagesKey: @(NO)}];
        }
        return image;
    } else {
        return nil;
    }
}
```

用户获取disk图片时需要保存图片到memory中，事宜提高访问效率，而是更新图片在memory中的访问记录。

```
UIImage *diskImage = [self diskImageForKey:key];
if (diskImage && self.config.shouldCacheImagesInMemory) {
    NSUInteger cost = SDCacheCostForImage(diskImage);
    [self.memCache setObject:diskImage forKey:key cost:cost];
}
```

##### 查找imageData从disk中

因为保存生成文件名的时候后缀可能有可能没有，在查找的时候需要考虑这种情况。保修起见，有后缀的先查找，没有查到然后再尝试查找没有后缀的。

先以默认的路径开始查找

```
NSString *defaultPath = [self defaultCachePathForKey:key];
    NSData *data = [NSData dataWithContentsOfFile:defaultPath options:self.config.diskCacheReadingOptions error:nil];
    if (data) {
        return data;
    }
    
    //去掉后缀后获取数据
    data = [NSData dataWithContentsOfFile:defaultPath.stringByDeletingPathExtension options:self.config.diskCacheReadingOptions error:nil];
    if (data) {
        return data;
    }
```

没有找到则按照自定义的路径中查找

```
NSArray<NSString *> *customPaths = [self.customPaths copy];
    for (NSString *path in customPaths) {
        NSString *filePath = [self cachePathForKey:key inPath:path];
        NSData *imageData = [NSData dataWithContentsOfFile:filePath options:self.config.diskCacheReadingOptions error:nil];
        if (imageData) {
            return imageData;
        }

        // fallback because of https://github.com/rs/SDWebImage/pull/976 that added the extension to the disk file name
        // checking the key with and without the extension
        imageData = [NSData dataWithContentsOfFile:filePath.stringByDeletingPathExtension options:self.config.diskCacheReadingOptions error:nil];
        if (imageData) {
            return imageData;
        }
    }
```

##### 移除图片

图片的移除要先移除memory中的记录，然后移除disk中的记录。

1、移除memory中记录

```
if (self.config.shouldCacheImagesInMemory) {
    [self.memCache removeObjectForKey:key];
}
```

2、移除disk中记录

```
dispatch_async(self.ioQueue, ^{
        [_fileManager removeItemAtPath:[self defaultCachePathForKey:key] error:nil];
    
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }
});
```
##### 清空disk

直接移除目录，一次删除目录下的所以数据。然后再次重建一个空目录。在串行队列中执行。

```
dispatch_async(self.ioQueue, ^{
    [_fileManager removeItemAtPath:self.diskCachePath error:nil];
    [_fileManager createDirectoryAtPath:self.diskCachePath
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:NULL];

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }
});
```

##### 删除过期文件

分两次清理，第一次清理过期的文件数据，第二次清理剩余文件总大小低于分配空间最大值的一半

- 1.先获取缓存目录下所有文件URL和最早未过期时间

```
//缓存目录URL
        NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];
        //需要的文件属性
        NSArray<NSString *> *resourceKeys = @[NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];

        // 枚举获取缓存目录下所有子URL
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:resourceKeys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];
        //没有超出过期时间的最早日期
        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-self.config.maxCacheAge];
```

- 2.第一次清理

```
//未过期的文件URL和总文件大小
        NSMutableDictionary<NSURL *, NSDictionary<NSString *, id> *> *cacheFiles = [NSMutableDictionary dictionary];
        NSUInteger currentCacheSize = 0;

        //第一次清理
        //1.遍历子URL查询文件属性，移除过期的文件记录
        //2.记录移除的总文件大小
        NSMutableArray<NSURL *> *urlsToDelete = [[NSMutableArray alloc] init];
        for (NSURL *fileURL in fileEnumerator) {
            
            NSError *error;
            NSDictionary<NSString *, id> *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:&error];
            // 属性为空 或 是个目录
            if (error || !resourceValues || [resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }

            // 如果文件修改日期早于过期日期，则添加URL到准备删除的数组中
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                [urlsToDelete addObject:fileURL];
                continue;
            }

            // Store a reference to this file and account for its total size.
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += totalAllocatedSize.unsignedIntegerValue;
            cacheFiles[fileURL] = resourceValues;
        }
        
        //移除图片
        for (NSURL *fileURL in urlsToDelete) {
            [_fileManager removeItemAtURL:fileURL error:nil];
        }

```

- 3.二次清理

```
//当未过期的文件总大小超过设置的最大值时，按LRU算法有限清除最近最久为访问的数据
//清理数据直到剩余总大小低于设置的最大值的一半
if (self.config.maxCacheSize > 0 && currentCacheSize > self.config.maxCacheSize) {
// Target half of our maximum cache size for this cleanup pass.
const NSUInteger desiredCacheSize = self.config.maxCacheSize / 2;

// 将File UR按修改时间从早到晚排序
NSArray<NSURL *> *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                         usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                             return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
                                                         }];

//逐次移除文件数据，直到剩余文件总大小低于最大值的一半
for (NSURL *fileURL in sortedFiles) {
    
    if ([_fileManager removeItemAtURL:fileURL error:nil]) {
        NSDictionary<NSString *, id> *resourceValues = cacheFiles[fileURL];
        NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
        currentCacheSize -= totalAllocatedSize.unsignedIntegerValue;

        if (currentCacheSize < desiredCacheSize) {
            break;
        }
    }
}
```

- 4.清理结束

```
if (completionBlock) {
    dispatch_async(dispatch_get_main_queue(), ^{
        completionBlock();
    });
}
```

##### 后台删除过期文件

APP进入后台后运行时间不确定，可能不足以支持disk过期文件删除任务的执行结束，这里需要向系统申请一段时间来保证任务执行结束。

```
//获取UIApplication
Class UIApplicationClass = NSClassFromString(@"UIApplication");
if(!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
    return;
}
//[UIApplication sharedApplication]
UIApplication *application = [UIApplication performSelector:@selector(sharedApplication)];
    
//向系统申请一段时间来执行任务
__block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
    
    //系统分配时间已到主动结束任务和置UIBackgroundTaskIdentifier为invalide
    [application endBackgroundTask:bgTask];
    bgTask = UIBackgroundTaskInvalid;
}];

//执行删除过期文件任务
[self deleteOldFilesWithCompletionBlock:^{
    //任务结束则结束向系统的申请
    [application endBackgroundTask:bgTask];
    bgTask = UIBackgroundTaskInvalid;
}];
```

##### 获取文件大小

```
- (NSUInteger)getSize {
    __block NSUInteger size = 0;
    dispatch_sync(self.ioQueue, ^{
        //获取目录下所有文件名
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtPath:self.diskCachePath];
        //遍历文件名，生成文件地址
        for (NSString *fileName in fileEnumerator) {
            NSString *filePath = [self.diskCachePath stringByAppendingPathComponent:fileName];
            //根据文件地址获取文件属性
            NSDictionary<NSString *, id> *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            //获取文件属性增加文件总大小
            size += [attrs fileSize];
        }
    });
    return size;
}
```

##### 获取文件大小和数量

```
//disk目录链接
    NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];

    dispatch_async(self.ioQueue, ^{
        NSUInteger fileCount = 0;
        NSUInteger totalSize = 0;
        
        //获取该目录下所有文件的URL集合，URL包含文件的NSFileSize属性，不会查询隐藏文件
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:@[NSFileSize]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];
        //遍历File URL获取文件大小，递增文件的总大小
        for (NSURL *fileURL in fileEnumerator) {
            NSNumber *fileSize;
            [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];
            totalSize += fileSize.unsignedIntegerValue;
            fileCount += 1;
        }

        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(fileCount, totalSize);
            });
        }
    });
```


