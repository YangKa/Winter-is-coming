## AFNetworking 图片下载

### 缓存管理对象 AFAutoPurgingImageCache

#### AFImageCache协议

协议定义了图片的保存、获取和移除

```
@protocol AFImageCache <NSObject>

- (void)addImage:(UIImage *)image withIdentifier:(NSString *)identifier;
- (nullable UIImage *)imageWithIdentifier:(NSString *)identifier;
- (BOOL)removeImageWithIdentifier:(NSString *)identifier;
- (BOOL)removeAllImages;

@end
```

#### AFImageRequestCache 协议

扩展了AFImageCache的功能，将image对应的key扩展位一个NSURLRequest和一个identifier的组合。

```
@protocol AFImageRequestCache <AFImageCache>

- (void)addImage:(UIImage *)image forRequest:(NSURLRequest *)request withAdditionalIdentifier:(nullable NSString *)identifier;
- (BOOL)removeImageforRequest:(NSURLRequest *)request withAdditionalIdentifier:(nullable NSString *)identifier;
- (nullable UIImage *)imageforRequest:(NSURLRequest *)request withAdditionalIdentifier:(nullable NSString *)identifier;

@end
```

#### 图片缓存对象AFCacheImage

属性

```
@interface AFCachedImage : NSObject

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, assign) UInt64 totalBytes;
@property (nonatomic, strong) NSDate *lastAccessDate;
@property (nonatomic, assign) UInt64 currentMemoryUsage;

@end
```

##### 创建图片缓存对象

```
-(instancetype)initWithImage:(UIImage *)image identifier:(NSString *)identifier {
    if (self = [self init]) {
        self.image = image;
        self.identifier = identifier;

        //一个像素占一个字节，直接计算图片的像素数量作为图片大小
        CGSize imageSize = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
        CGFloat bytesPerPixel = 4.0;
        CGFloat bytesPerSize = imageSize.width * imageSize.height;
        self.totalBytes = (UInt64)bytesPerPixel * (UInt64)bytesPerSize;
        self.lastAccessDate = [NSDate date];
    }
    return self;
}
```

##### 更新最近访问图片时间

```
- (UIImage*)accessImage {
    self.lastAccessDate = [NSDate date];
    return self.image;
}
```


#### 初始化AFAutoPurgingImageCache

- 初始化会分配内存大小、开始自动清理缓存保留的限制大小。默认是100MB，60MB的限制。
- 使用一个可变字典作为缓存容器。
- 使用一个同步队列实现数据的访问同步并行。
- 使用dispatch_barrier_sync实现数据移除的串行同步执行，数据保存的串行异步，保证数据的访问安全和提高保存效率。

```
//缓存中能使用的的内存大小
@property (nonatomic, assign) UInt64 memoryCapacity;

//最大清理值，当内存占用超过最大值时会一直清理图片缓存，直到低于该值
@property (nonatomic, assign) UInt64 preferredMemoryUsageAfterPurge;

//当前所有图片缓存所占用的内存大小，实际是访问的self.currentMemoryUsage
@property (nonatomic, assign, readonly) UInt64 memoryUsage;

//使用字典作为缓存图片容器
@property (nonatomic, strong) NSMutableDictionary <NSString* , AFCachedImage*> *cachedImages;

//实时记录缓存中的占用大小
@property (nonatomic, assign) UInt64 currentMemoryUsage;
```

##### 获取图片

并行访问图片，提高效率

```
- (nullable UIImage *)imageWithIdentifier:(NSString *)identifier {
    __block UIImage *image = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        AFCachedImage *cachedImage = self.cachedImages[identifier];
        image = [cachedImage accessImage];
    });
    return image;
}
```

##### 移除图片

在同步队列中使用栏栅同步，保证执行删除前其它数据范文操作都已经结束，也不会有操作和删除操作并行执行。达到串行的效果

```
- (BOOL)removeImageWithIdentifier:(NSString *)identifier {
    __block BOOL removed = NO;
    dispatch_barrier_sync(self.synchronizationQueue, ^{
        AFCachedImage *cachedImage = self.cachedImages[identifier];
        if (cachedImage != nil) {
            [self.cachedImages removeObjectForKey:identifier];
            self.currentMemoryUsage -= cachedImage.totalBytes;
            removed = YES;
        }
    });
    return removed;
}
```

##### 添加图片

分为两步：

- 保存缓存图片对象

```
//保存图片缓存
    dispatch_barrier_async(self.synchronizationQueue, ^{
        AFCachedImage *cacheImage = [[AFCachedImage alloc] initWithImage:image identifier:identifier];

        //已经存在，则执行替换，需要先修改当前内存占用大小的修改
        AFCachedImage *previousCachedImage = self.cachedImages[identifier];
        if (previousCachedImage != nil) {
            self.currentMemoryUsage -= previousCachedImage.totalBytes;
        }

        //保存图片缓存和修改缓存占用大小
        self.cachedImages[identifier] = cacheImage;
        self.currentMemoryUsage += cacheImage.totalBytes;
    });
```

- 缓存大小超出最大缓存限制处理

```
//缓存临界情况处理
    dispatch_barrier_async(self.synchronizationQueue, ^{
        //超出分配缓存大小值
        if (self.currentMemoryUsage > self.memoryCapacity) {
            //需要清理的大小
            UInt64 bytesToPurge = self.currentMemoryUsage - self.preferredMemoryUsageAfterPurge;
            
            //将缓存对象按LRU算法排序
            NSMutableArray <AFCachedImage*> *sortedImages = [NSMutableArray arrayWithArray:self.cachedImages.allValues];
            NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"lastAccessDate"
                                                                           ascending:YES];
            [sortedImages sortUsingDescriptors:@[sortDescriptor]];

            //删除缓存直到剩余值低于self.preferredMemoryUsageAfterPurge
            UInt64 bytesPurged = 0;
            for (AFCachedImage *cachedImage in sortedImages) {
                [self.cachedImages removeObjectForKey:cachedImage.identifier];
                bytesPurged += cachedImage.totalBytes;
                if (bytesPurged >= bytesToPurge) {
                    break ;
                }
            }
            self.currentMemoryUsage -= bytesPurged;
        }
    });
```

##### 使用NSURLRequest和identifier作为key进行处理

```
- (NSString *)imageCacheKeyFromURLRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)additionalIdentifier {
    NSString *key = request.URL.absoluteString;
    if (additionalIdentifier != nil) {
        key = [key stringByAppendingString:additionalIdentifier];
    }
    return key;
}
```



