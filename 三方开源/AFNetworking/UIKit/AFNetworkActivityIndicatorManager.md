
## AFNetworkActivityIndicatorManager


- 单例对象，通过开启网络指示器的管理则会监听请求任务开启完成的通知，通过增加和递减活动请求数，类似栈和信号量的管理一样来进行网络指示器的显示和隐藏。

- 大量使用同步快@synchronized(self){}来保证动态属性的线程安全，也是保证按照通知的顺序串行修改网络指示器的状态。

- 可以直接在didFinishLaunchingWithOptions中进行开启，默认是关闭状态
 `[[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];`

- 活动中的请求数会根据监听情况自我管理，不需要手动去调用`incrementActivityCount` 或 `decrementActivityCount`去管理

- 通过设置显示延迟和消失延迟来延迟网络指示器显示的时间，以防请求时间过短消失太快，用户没有注意到的情况。

#### 通过NSTimer来进行延迟动作的调用

//显示前的延迟时间，默认1.0s
`@property (nonatomic, assign) NSTimeInterval activationDelay;`

//消失前的延迟时间，默认0.17s
`@property (nonatomic, assign) NSTimeInterval completionDelay;`

#### 设置活动指示器hidden或display时执行动作，
`- (void)setNetworkingActivityActionWithBlock:(nullable void (^)(BOOL networkActivityIndicatorVisible))block;`

#### 四种状态

```
typedef NS_ENUM(NSInteger, AFNetworkActivityManagerState) {
    AFNetworkActivityManagerStateNotActive,   // 未激活
    AFNetworkActivityManagerStateDelayingStart,  //激活前的延时阶段
    AFNetworkActivityManagerStateActive,    // 激活
    AFNetworkActivityManagerStateDelayingEnd  // 取消阶段
};
```

#### 初始化

1.设置当前状态为AFNetworkActivityManagerStateNotActive
2.注册通知，监听任务的启动、暂停、完成
3.设置延迟默认时间

#### 网络活动状态

指示器的显示是根据当前请求活动数来判断的，而活动数又是变动的。
这里采用了同步块来保证数据的访问安全。

```
- (BOOL)isNetworkActivityOccurring {
    @synchronized(self) {
        return self.activityCount > 0;
    }
}
```

#### 控制网络指示器的显示

```
- (void)setNetworkActivityIndicatorVisible:(BOOL)networkActivityIndicatorVisible {
    if (_networkActivityIndicatorVisible != networkActivityIndicatorVisible) {
        
        //KVO和同步块
        [self willChangeValueForKey:@"networkActivityIndicatorVisible"];
        @synchronized(self) {
             _networkActivityIndicatorVisible = networkActivityIndicatorVisible;
        }
        [self didChangeValueForKey:@"networkActivityIndicatorVisible"];
        
        //自定义了操作则执行，否则交由UIApplication显示
        if (self.networkActivityActionBlock) {
            self.networkActivityActionBlock(networkActivityIndicatorVisible);
        } else {
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:networkActivityIndicatorVisible];
        }
    }
}
```

#### 增减活动数

```
	//启动KVO
    [self willChangeValueForKey:@"activityCount"];

    //同步块内修改活动数
	@synchronized(self) {
		_activityCount++;
		//_activityCount = MAX(_activityCount - 1, 0);
	}
    [self didChangeValueForKey:@"activityCount"];

    //在主线程中更新当前指示器的状态
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateCurrentStateForNetworkActivityChange];
    });
```

#### 网络任务活动数改变时更新网络指示器状态

```
- (void)updateCurrentStateForNetworkActivityChange {
    if (self.enabled) {
        switch (self.currentState) {
            case AFNetworkActivityManagerStateNotActive:
                if (self.isNetworkActivityOccurring) {
                    [self setCurrentState:AFNetworkActivityManagerStateDelayingStart];
                }
                break;
            case AFNetworkActivityManagerStateDelayingStart:
                //No op. Let the delay timer finish out.
                break;
            case AFNetworkActivityManagerStateActive:
                if (!self.isNetworkActivityOccurring) {
                    [self setCurrentState:AFNetworkActivityManagerStateDelayingEnd];
                }
                break;
            case AFNetworkActivityManagerStateDelayingEnd:
                if (self.isNetworkActivityOccurring) {
                    [self setCurrentState:AFNetworkActivityManagerStateActive];
                }
                break;
        }
    }
}
```

#### 网络状态改变时执行的操作

```
- (void)setCurrentState:(AFNetworkActivityManagerState)currentState {
//使用同步块，保证按照请求的状态变化串行修改指示器的状态
    @synchronized(self) {
        if (_currentState != currentState) {
            [self willChangeValueForKey:@"currentState"];
            _currentState = currentState;
            switch (currentState) {
                case AFNetworkActivityManagerStateNotActive:
                    [self cancelActivationDelayTimer];
                    [self cancelCompletionDelayTimer];
                    [self setNetworkActivityIndicatorVisible:NO];
                    break;
                case AFNetworkActivityManagerStateDelayingStart:
                    [self startActivationDelayTimer];
                    break;
                case AFNetworkActivityManagerStateActive:
                    [self cancelCompletionDelayTimer];
                    [self setNetworkActivityIndicatorVisible:YES];
                    break;
                case AFNetworkActivityManagerStateDelayingEnd:
                    [self startCompletionDelayTimer];
                    break;
            }
        }
        [self didChangeValueForKey:@"currentState"];
    }
}
```

