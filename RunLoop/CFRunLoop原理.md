
    RunLoop就是事件循环。具体实现分别是Foundation中的NSRunLoop和Core Foundation中的CFRunLoop，其中NSRunLoop是对CFRunLoop的封装。
它的思想如下：


	int main(void) {
		初始化();
		while (message != 退出) {
			处理事件( message );
			message = nextEvent();
		}
		return 0;
	}

###CFRunLoop

    CFRunLoop是与线程绑定的，不能直接创建，只能通过CFRunLoopGetCurrent和CFRunLoopGetMain函数来获得CFRunLoop对象，如果不存在的化就会创建一个。刚创建的run loop不是运行状态，需要使用者手动运行起来。其中Main run loop在应用主线程开启后就是运行状态。

#####事物
RunLoop中的需要处理的事物有四种：

    - Source：事件的来源。分为Source 0和Source 1，其中source 1是机遇mach port也就是端口的，source 0则是需要手动触发的。统一称为CFRunLoopSource.

    - Timers:就是定时器，被封装成CFRunLoopTimer.例如NSTimer。

    - Observers:严格说不是需要处理的事件，而是类似notification 或 delegate一样的东西，runloop会向observer汇报状态。被封装成CFRunLoopObserver。

    - Blocks：可以使用CFRunLoopPerformBlock向RunLoop中添加Blocks；

#####模式mode

    所有事物都需要关联特定的模式，在不同的模式下运行关联的事件。RunLoop的模式分为两种，一种是KCFRunLoopDefaultMode，还有一种是KCFRunLoopCommonModes的模式集合。
    注册commonModes的事件会在集合下的所有模式下的得到处理，也就是事件被添加到了所有模式中。
    KCFRunLoopDefaultMode默认是在common modes中的。

//TO DO
CommonModes下的几种模式
-

###运行RunLoop

- CFRunLoopRun(void)

        默认执行KCFRunLoopDefaultMode下，事件处理了不会返回会一直执行。只能使用CFRunLoopStop或者将runLoop中的所有事件来源（source、timers、observers、blocks）移除来使runLoop退出。
        对于只做一件事的线程来说，可以使用这个函数，省去了runLoop的外层循环。
	
- CFRunLoopRunResult CFRunLoopRunInMode(CFRunLoopMode mode,//运行模式
                                                                                CFTimeInterval seconds,//最长运行时间
                                                                                Boolean returnAfterSourceHandled//处理一个事件后是否返回
                                                                                );
                                                                                
        可以很好的控制runLoop，这样子CFRunLoop只是event loop的一部分，主要用来实际的执行事件，闲时会进入睡眠。
        
        现在的流程如下：
    
        int main(void) {
            CFRunLoopRef runLoop = CFRunLoopGetCurrent();
            
            // 添加一些 source，timer，observer 或者 block
            
            while (message != 退出) {
            message = 获取消息();
            mode = // 处理消息看是否需要改变 mode，比如 scroll view 滑动
            time = // 设置一个超时时间
            CFRunLoopRunInMode(mode,
            time,
            true); // 猜测大部分时间为 true，因为需要更灵活的控制
            }
            return 0;
        }
        
Runloop 整体层次结构
        
        每条线程对应一个唯一的 RunLoop 对象，我们并不能去手动创建，只能调用方法函数获取当前线程的 RunLoop 对象，第一次获取的时候 RunLoop 对象，其完成创建。(主线程除外，主线程其自动创建)
        一个 RunLoop 包含若干个 Mode， RunLoop 运行循环启动后，只能在一个特定的 Mode 下去处理当前 Mode 中的事件响应，这个Mode被称作 CurrentMode。其他Mode中的事件会被暂停，然后根据不同的事件切换到不同类型 Mode，从而处理相应事件，切换频率很快很快，这个切换动作是在同一个运行循环中完成的。
        一个 Mode 下，有若干个source0、source1、timer、observer (统称为 mode item)和若干port，也就是说所有的事件都是由 Mode 管理着。

RunLoop - 运行循环原理步骤解析

    RunLoop每次循环的执行步骤大概如下
    通知observers 已经进入RunLoop
    通知observes 即将开始处理timer source
    通知observes 即将开始处理input sources（不包括port-based source）
    开始处理input source（不包括port-based source）
    如果有port-based source待处理，则开始处理port-based source，跳转到第 9 步
    通知observes线程即将进入休眠
    让线程进入休眠状态，直到有以下事件发生：
    收到内核发送过来的消息
    定时器事件需要执行
    RunLoop的超时时间到了
    外部手动唤醒RunLoop
    通知observes 线程被唤醒
    处理待处理的事件：
    如果自定义的timer被fire，那么执行该timer事件并重新开始循环，跳转到第2步
    如果input source被fire，则处理该事件
    如果RunLoop被手动唤醒，并且没有超时，那么重新开始循环，跳转到第2步
    通知observes RunLoop已经退出

    主线程的 RunLoop 无需我们添加代码启动，但是子线程的特点是异步销毁的，要保活一个子线程必须启动其 RunLoop 循环
    子线程特点异步销毁，这里让控制器 VC 去强保活这个线程对象也是无效的。
    多线程中线程常驻，并不是线程的 thread 对象常驻，因为它仅仅只是一个 OC 对象，并不是真的执行任务的线程，更不能代表线程，真正的多线程(线程池)管理是由 CPU调度(进程调度) 决定的， OC 对象没有销毁但是其实线程池中也许已经没有这个线程了。线程池概念链接 和 CPU调度策略链接
    线程之间处理任务独立的互不干扰，其各自的 RunLoop 也是独立的，在上面 mode 下处理事件也是互不干扰，自行切换。
    子线程中 mode 模式类型 NSRunLoopCommonModes 和 NSDefaultRunLoopMode都有效，但是 UITrackingRunLoopMode mode 类型是无效的，子线程不能处理UI交互事件。
    我们并不希望这个子线程永远销毁不了(可以自定义一个 thread 断点delloc方法测试)，通过一个外部 BOOL变量 和 - (void)runUntilDate:(NSDate *)limitDate;方法去控制线程内事件循环
    (void)run; 启动处理事件循环，如果没有事件则立刻返回。注意：主线程上调用这个方法会导致无法返回后面所有方法不执行（进入无限循环，虽然不会阻塞主线程），因为主线程一般总是会有事件处理。

    (void)runUntilDate:(NSDate *)limitDate; 等同 run 方法，增加了超时参数limitDate，间隔 limitDate 时间循环避免进入无限循环。使用在UI线程（亦即主线程）上，可以达到暂停的效果。


        

