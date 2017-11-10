
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
        
###RunLoop的应用

        

