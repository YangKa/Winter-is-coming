## YYDiskCache

简介：

- 使用dispatch_after进行本地缓存各种限制条件的轮询检查和处理
- 采用一个static的NSMapTable进行全局diskCache的存储，保证多次创建都使用的是同一对象，使用信号量机制访问。
- 持有一个YYKVStorage进行对象的存储，采用数据库sqlite和文件系统两种方式进行存储管理，根据存储对象自动判断存储方式采用sqlite或File System
- 监听应用退出通知，将KVStroage对象释放
- 采用并行队列对YYKVStorage中存储的数据进行增删查改，只用全局宏定义信号量锁进行数据的线程安全保护。
- 所有block的回调一致采用在后台并行队列中返回。
- 缓存对象的extended data采用对象关联保存在YYDiskCache类单例里。在存储和访问缓存对象时进行保存和访问。
 ，当内存不足时，按照LRU算法自动移除部分对象
 
 
#### 实例变量
 
```
@implementation YYDiskCache {
    YYKVStorage *_kv;//key和value映射管理
    dispatch_semaphore_t _lock;//信号锁
    dispatch_queue_t _queue;//并行队列
}
```
 
 
#### 使用信号量机制进行线程锁保护

```
#define Lock() dispatch_semaphore_wait(self->_lock, DISPATCH_TIME_FOREVER)
#define Unlock() dispatch_semaphore_signal(self->_lock)
```

#### 获取可用disk空间大小

通过获取沙盒文件目录属性来查询NSFileSystemFreeSize

```
static int64_t _YYDiskSpaceFree() {
    
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:&error];
    if (error) return -1;
    int64_t space =  [[attrs objectForKey:NSFileSystemFreeSize] longLongValue];
    if (space < 0) space = -1;
    return space;
}
```

#### 获取MD5签名

```
static NSString *_YYNSStringMD5(NSString *string) {
    if (!string) return nil;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:
                @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                result[0],  result[1],  result[2],  result[3],
                result[4],  result[5],  result[6],  result[7],
                result[8],  result[9],  result[10], result[11],
                result[12], result[13], result[14], result[15]
            ];
}
```

#### 全局diskCache存储

使用静态NSMapTable作为diskCahce对象的存储容器，使用静态信号锁保证diskCache的访问安全

```
static NSMapTable *_globalInstances; //弱引用字典容器
static dispatch_semaphore_t _globalInstancesLock;//全局信号量锁

//全局初始化
static void _YYDiskCacheInitGlobal() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _globalInstancesLock = dispatch_semaphore_create(1);
        //key强引用，value弱引用
        _globalInstances = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
    });
}

//全局diskCache对象
static YYDiskCache *_YYDiskCacheGetGlobal(NSString *path) {
    if (path.length == 0) return nil;
    _YYDiskCacheInitGlobal();
    dispatch_semaphore_wait(_globalInstancesLock, DISPATCH_TIME_FOREVER);
    id cache = [_globalInstances objectForKey:path];
    dispatch_semaphore_signal(_globalInstancesLock);
    return cache;
}

//保存全局diskCache对象
static void _YYDiskCacheSetGlobal(YYDiskCache *cache) {
    if (cache.path.length == 0) return;
    _YYDiskCacheInitGlobal();
    dispatch_semaphore_wait(_globalInstancesLock, DISPATCH_TIME_FOREVER);
    [_globalInstances setObject:cache forKey:cache.path];
    dispatch_semaphore_signal(_globalInstancesLock);
}
```

#### 循环在后台检查缓存大小是否超过限制条件

使用dispatch_after循环检查

```
- (void)_trimRecursively {
    __weak typeof(self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        [self _trimInBackground];
        [self _trimRecursively];
    });
}

- (void)_trimInBackground {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        
        __strong typeof(_self) self = _self;
        if (!self) return;
        
        Lock();
        [self _trimToCost:self.costLimit];
        [self _trimToCount:self.countLimit];
        [self _trimToAge:self.ageLimit];
        [self _trimToFreeDiskSpace:self.freeDiskSpaceLimit];
        Unlock();
        
    });
}
```

#### 保存

保存数据

```
- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    if (!key) return;
    
    //移除已有文件
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    //获取存储对象的额外数据
    NSData *extendedData = [YYDiskCache getExtendedDataFromObject:object];
    //压缩对象
    NSData *value = nil;
    if (_customArchiveBlock) {
        value = _customArchiveBlock(object);
    } else {
        @try {
            value = [NSKeyedArchiver archivedDataWithRootObject:object];
        }
        @catch (NSException *exception) {
        }
    }
    if (!value) return;
    
    //需要使用文件系统，则根据key创建文件名
    NSString *filename = nil;
    if (_kv.type != YYKVStorageTypeSQLite) {
        if (value.length > _inlineThreshold) {
            filename = [self _filenameForKey:key];
        }
    }
    //保存数据
    Lock();
    [_kv saveItemWithKey:key value:value filename:filename extendedData:extendedData];
    Unlock();
}
```

#### 获取数据

```
- (id<NSCoding>)objectForKey:(NSString *)key {
    if (!key) return nil;
    
    //1.获取存储对象
    Lock();
    YYKVStorageItem *item = [_kv getItemForKey:key];
    Unlock();
    if (!item.value) return nil;
    
    //解压缩数据
    id object = nil;
    if (_customUnarchiveBlock) {
        object = _customUnarchiveBlock(item.value);
    } else {
        @try {
            object = [NSKeyedUnarchiver unarchiveObjectWithData:item.value];
        }
        @catch (NSException *exception) {
            // nothing to do...
        }
    }
    //尝试添加额外数据
    if (object && item.extendedData) {
        [YYDiskCache setExtendedData:item.extendedData toObject:object];
    }
    
    return object;
}
```

#### 增量数据

```
static const int extended_data_key; //增量数据key

#pragma mark - extended data
+ (NSData *)getExtendedDataFromObject:(id)object {
    if (!object) return nil;
    return (NSData *)objc_getAssociatedObject(object, &extended_data_key);
}

+ (void)setExtendedData:(NSData *)extendedData toObject:(id)object {
    if (!object) return;
    objc_setAssociatedObject(object, &extended_data_key, extendedData, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
```

