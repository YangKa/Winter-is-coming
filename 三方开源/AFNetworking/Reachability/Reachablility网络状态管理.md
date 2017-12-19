## Reachablility网络状态管理

### AFNetworkReachabilityManager

这个类比较简单，功能单一，就是为了监听网络状态和发送网络状态改变的通知。

### 创建SCNetworkReachabilityRef

- 通过domain创建
	`SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);`

- 通过Address创建
	`SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);`

创建sockaddr

```
	#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000) || (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 101100)
	    struct sockaddr_in6 address;
	    bzero(&address, sizeof(address));
	    address.sin6_len = sizeof(address);
	    address.sin6_family = AF_INET6;
	#else
	    struct sockaddr_in address;
	    bzero(&address, sizeof(address));
	    address.sin_len = sizeof(address);
	    address.sin_family = AF_INET;
	#endif
```

### 开启监听

- 1.将networkReachability和状态改变的回调绑定到设置的环境中。callBack调用时会调用用户设置的block告知外部网络状态。
- 2.将networkReachability添加到主线程的RunLoop的commonModes集合下，循环检测当前网络状态的改变。
- 3.在后台线程中异步查询网络状态，执行block回调和发送状态改变通知`AFNetworkingReachabilityDidChangeNotification`

```
- (void)startMonitoring {

    if (!self.networkReachability) {
        return;
    }
    
    //停止监听
    [self stopMonitoring];

    //回调状态block
    __weak __typeof(self)weakSelf = self;
    AFNetworkReachabilityStatusBlock callback = ^(AFNetworkReachabilityStatus status) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }
    };

    //配置环境
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, AFNetworkReachabilityRetainCallback, AFNetworkReachabilityReleaseCallback, NULL};
    //设置状态改变回调
    SCNetworkReachabilitySetCallback(self.networkReachability, AFNetworkReachabilityCallback, &context);
    //在主线程runLoop下的commonModes集下循环检测
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    
    //发送初始状态
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(self.networkReachability, &flags)) {
            AFPostReachabilityStatusChange(flags, callback);
        }
    });
}
```
### 停止监听

将networkReachablility从所在的RunLoop中移除，实现停止监听的功能
```
	- (void)stopMonitoring {
	    if (self.networkReachability) {
	    	//将
	        SCNetworkReachabilityUnscheduleFromRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
	    }
	}
```

### NSKeyValueObserving

将networkReachabilityStatus的改变与reachable、reachableViaWWAN、reachableViaWiFi关联。
当networkReachabilityStatus值改变时会发动通知给关联值得观察者告知这些值已经改变。
`可以通过+ (NSSet *)keyPathsForValuesAffecting<keyPath>来单独设置那些key于keyPath关联。`

```
	+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
	    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
	        return [NSSet setWithObject:@"networkReachabilityStatus"];
	    }
	
	    return [super keyPathsForValuesAffectingValueForKey:key];
	}
```

### 通过网络标志SCNetworkReachabilityFlags判断网络状态

```
	static AFNetworkReachabilityStatus AFNetworkReachabilityStatusForFlags(SCNetworkReachabilityFlags flags) {
	
	    //网络是否可达
	    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
	    //是否需要连接
	    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
	    //是否能自动连接
	    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand ) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
	    //是否不需要用户操作就可以连接
	    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
	    //网络是否可用
	    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));
		
		
	    AFNetworkReachabilityStatus status = AFNetworkReachabilityStatusUnknown;
	    if (isNetworkReachable == NO) {
	        status = AFNetworkReachabilityStatusNotReachable;
	    }
	#if	TARGET_OS_IPHONE
	    else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
	        status = AFNetworkReachabilityStatusReachableViaWWAN;
	    }
	#endif
	    else {
	        status = AFNetworkReachabilityStatusReachableViaWiFi;
	    }
	
	    return status;
	}
```