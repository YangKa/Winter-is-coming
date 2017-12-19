## _AFURLSessionTaskSwizzling 

`继承NSObject通过runtime机制在+load方法中对task类进行method swizzling。`

##### 主要作用：

- 遍历NSURLSessionDataTask的继承链，替换任务类中的resume和suspend方法。
- 替换的方法对原操作并未做任何修改，只是添加了一个相应通知发送的操作。

##### 通知：

AFNSURLSessionTaskDidResumeNotification  //任务启动
AFNSURLSessionTaskDidSuspendNotification //任务暂停

##### 核心方法：

```
+ (void)load {
    if (NSClassFromString(@"NSURLSessionTask")) {
        //创建一个ephemeralSessionConfiguration配置的session
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession * session = [NSURLSession sessionWithConfiguration:configuration];
        
        //通过该session创建一个NSURLSessionDataTask类型的dataTask
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wnonnull"
        NSURLSessionDataTask *localDataTask = [session dataTaskWithURL:nil];
#pragma clang diagnostic pop
        
        IMP originalAFResumeIMP = method_getImplementation(class_getInstanceMethod([self class], @selector(af_resume)));
        Class currentClass = [localDataTask class];
        
        //遍历NSURLSessionDataTask类的继承链，对resume和af_resume进行swizzling交互
        while (class_getInstanceMethod(currentClass, @selector(resume))) {
            Class superClass = [currentClass superclass];
            IMP classResumeIMP = method_getImplementation(class_getInstanceMethod(currentClass, @selector(resume)));
            IMP superclassResumeIMP = method_getImplementation(class_getInstanceMethod(superClass, @selector(resume)));
            
            //父类和子类的resume方法IMP不同，并且与要交换的的af_resume的IMP不同，则进行resume和suspend方法的交换
            if (classResumeIMP != superclassResumeIMP &&
                originalAFResumeIMP != classResumeIMP) {
                [self swizzleResumeAndSuspendMethodForClass:currentClass];
            }
            currentClass = [currentClass superclass];
        }
        
        //因为session被取消，只是保证不再添加和创建新的任务，已经存在session中的任务还是会继续执行。所以需要先cancel其中的任务然后在invalidate该session
        [localDataTask cancel];
        //session被废弃
        [session finishTasksAndInvalidate];
    }
}
```

其中有一个比较有趣的地方，_AFURLSessionTaskSwizzling定义了一个无效的state方法用于去掉警告

```
//为了保证af_resume和af_suspend不被警告
- (NSURLSessionTaskState)state {
    NSAssert(NO, @"State method should never be called in the actual dummy class");
    return NSURLSessionTaskStateCanceling;
}

- (void)af_resume {
    NSAssert([self respondsToSelector:@selector(state)], @"Does not respond to state");
    NSURLSessionTaskState state = [self state];//调用的不是_AFURLSessionTaskSwizzling中的state方法，而是添加到的那个任务类的state
    [self af_resume];
    
    if (state != NSURLSessionTaskStateRunning) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AFNSURLSessionTaskDidResumeNotification object:self];
    }
}
```