## YYKeyboardManager

- manager通过+ (void)load;注册监听键盘状态通知。
- 需要监听键盘的类对象需要遵守YYKeyboardObserver协议，当键盘状态改变时会反馈键盘信息给这些观察者。观察者再做出自己的响应。
- mananger也会提供一些键盘相关的位置、UI信息、显示方面信息的API。

### 注册成观察者的协议

```
@protocol YYKeyboardObserver <NSObject>
@optional
- (void)keyboardChangedWithTransition:(YYKeyboardTransition)transition;
@end
```

#### 使用NSHashTable持有观察者

利用NSHashTable对集合内对象灵活的内存管理规则，进行weak持有其中的对象。

键盘观察对象管理

- (void)addObserver:(id<YYKeyboardObserver>)observer {
    if (!observer) return;
    [_observers addObject:observer];
}

- (void)removeObserver:(id<YYKeyboardObserver>)observer {
    if (!observer) return;
    [_observers removeObject:observer];

#### 初始化

类加载阶段初始化hashTable和注册键盘监听通知

```
+ (void)load {
	//延迟以防初始化失败
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self defaultManager];
    });
}

+ (instancetype)defaultManager {
    static YYKeyboardManager *mgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mgr = [[self alloc] _init];
    });
    return mgr;
}

- (instancetype)_init {
    self = [super init];
    
    //hashTable弱持有其中的对象
    _observers = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality capacity:0];
    
    //监听键盘状态
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_keyboardFrameWillChangeNotification:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    // for iPad (iOS 9)
    if ([UIDevice currentDevice].systemVersion.floatValue >= 9) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_keyboardFrameDidChangeNotification:)
                                                     name:UIKeyboardDidChangeFrameNotification
                                                   object:nil];
    }
    return self;
}
```

#### 键盘所在的window

- 先检测windows中是否含有键盘，没有则单独检测keyWindow
- 然后检测windows中window的类名称

`这样检测需要依赖系统UI层的类名称，但系统UI层名称会随着系统版本而改变。这种验证方式不稳定，并且keyWindow本来就是windows的一员，检测上市重复了。`

```
- (UIWindow *)keyboardWindow {
    UIWindow *window = nil;
    //[UIApplication sharedApplication].windows 不包括依稀创建和管理的window
    for (window in [UIApplication sharedApplication].windows) {
        if ([self _getKeyboardViewFromWindow:window]) return window;
    }
    
    window = [UIApplication sharedApplication].keyWindow;//获取windows中最近被设置为makeKeyAndVisible的window
    if ([self _getKeyboardViewFromWindow:window]) return window;
    
    //通过查找系统UI层window的名称来判断是否是键盘的背景window。
    NSMutableArray *kbWindows = nil;
    for (window in [UIApplication sharedApplication].windows) {
        
        NSString *windowName = NSStringFromClass(window.class);
        if ([self _systemVersion] < 9) {
            // UITextEffectsWindow
            if (windowName.length == 19 &&
                [windowName hasPrefix:@"UI"] &&
                [windowName hasSuffix:@"TextEffectsWindow"]) {
                if (!kbWindows) kbWindows = [NSMutableArray new];
                [kbWindows addObject:window];
            }
        } else {
            // UIRemoteKeyboardWindow
            if (windowName.length == 22 &&
                [windowName hasPrefix:@"UI"] &&
                [windowName hasSuffix:@"RemoteKeyboardWindow"]) {
                if (!kbWindows) kbWindows = [NSMutableArray new];
                [kbWindows addObject:window];
            }
        }
    }
    
    //当且仅有一个满足该条件时，确定为键盘的背景window
    if (kbWindows.count == 1) {
        return kbWindows.firstObject;
    }
    
    return nil;
}
```

#### 键盘的view

```
- (UIView *)keyboardView {
    UIWindow *window = [self keyboardWindow];
    UIView *view = [self _getKeyboardViewFromWindow:window];
    return view;
}
```

#### 从window获取键盘view

```
- (UIView *)_getKeyboardViewFromWindow:(UIWindow *)window {
    
    /*
     iOS 6/7:
     UITextEffectsWindow
        UIPeripheralHostView << keyboard
     
     iOS 8:
     UITextEffectsWindow
        UIInputSetContainerView
            UIInputSetHostView << keyboard
     
     iOS 9:
     UIRemoteKeyboardWindow
        UIInputSetContainerView
            UIInputSetHostView << keyboard
     */
    
    if (!window) return nil;
    
    // Get the window
    NSString *windowName = NSStringFromClass(window.class);
    if ([self _systemVersion] < 9) {
        // UITextEffectsWindow
        if (windowName.length != 19) return nil;
        if (![windowName hasPrefix:@"UI"]) return nil;
        if (![windowName hasSuffix:@"TextEffectsWindow"]) return nil;
    } else {
        // UIRemoteKeyboardWindow
        if (windowName.length != 22) return nil;
        if (![windowName hasPrefix:@"UI"]) return nil;
        if (![windowName hasSuffix:@"RemoteKeyboardWindow"]) return nil;
    }
    
    // Get the view
    if ([self _systemVersion] < 8) {
        // UIPeripheralHostView
        for (UIView *view in window.subviews) {
            NSString *viewName = NSStringFromClass(view.class);
            if (viewName.length != 20) continue;
            if (![viewName hasPrefix:@"UI"]) continue;
            if (![viewName hasSuffix:@"PeripheralHostView"]) continue;
            return view;
        }
    } else {
        // UIInputSetContainerView
        for (UIView *view in window.subviews) {
            NSString *viewName = NSStringFromClass(view.class);
            if (viewName.length != 23) continue;
            if (![viewName hasPrefix:@"UI"]) continue;
            if (![viewName hasSuffix:@"InputSetContainerView"]) continue;
            // UIInputSetHostView
            for (UIView *subView in view.subviews) {
                NSString *subViewName = NSStringFromClass(subView.class);
                if (subViewName.length != 18) continue;
                if (![subViewName hasPrefix:@"UI"]) continue;
                if (![subViewName hasSuffix:@"InputSetHostView"]) continue;
                return subView;
            }
        }
    }
    
    return nil;
}
```


#### 键盘信息

```
NSValue *beforeValue = info[UIKeyboardFrameBeginUserInfoKey];
NSValue *afterValue = info[UIKeyboardFrameEndUserInfoKey];
NSNumber *curveNumber = info[UIKeyboardAnimationCurveUserInfoKey];
NSNumber *durationNumber = info[UIKeyboardAnimationDurationUserInfoKey];
```

#### 通知所有观察者键盘状态变化

```
//取消之前_notifyAllObservers消息得发送
[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_notifyAllObservers) object:nil];

if (duration == 0) {
	//立刻在runLoop中执行
    [self performSelector:@selector(_notifyAllObservers) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
} else {
    [self _notifyAllObservers];
}
```

#### 位置转换

```
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    if (CGRectIsNull(rect)) return rect;
    if (CGRectIsInfinite(rect)) return rect;
    
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    if (!mainWindow) mainWindow = [UIApplication sharedApplication].windows.firstObject;
    if (!mainWindow) { // no window ?!
        if (view) {
            [view convertRect:rect fromView:nil];
        } else {
            return rect;
        }
    }
    
    rect = [mainWindow convertRect:rect fromWindow:nil];
    if (!view) return [mainWindow convertRect:rect toWindow:nil];
    if (view == mainWindow) return rect;
    
    UIWindow *toWindow = [view isKindOfClass:[UIWindow class]] ? (id)view : view.window;
    if (!mainWindow || !toWindow) return [mainWindow convertRect:rect toView:view];
    if (mainWindow == toWindow) return [mainWindow convertRect:rect toView:view];
    
    // in different window
    rect = [mainWindow convertRect:rect toView:mainWindow];
    rect = [toWindow convertRect:rect fromWindow:mainWindow];
    rect = [view convertRect:rect fromView:toWindow];
    return rect;
}
```


#### 与IQKeyboardManager的区别

- YYKeyboardManager只是简单提供了监听键盘位置和动画、访问键盘视图的功能。主要关心的是键盘操作。
- IQkeyboardManager主要提供的是键盘和编辑类控件TextView/TextField之类的交互处理。

