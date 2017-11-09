##GCD原理

####概述

    - GCD是提供了功能强大的任务和队列控制功能，相比于NSOperation更加底层，虽然现象苹果极力的推荐使用NSOperation来解决多线程问题, 但是,就目前市场上大部分企业的iOS开发团队而言, GCD仍然还是大头, NSOperation也只会逐步的来替代GCD, 但在多线程处理的时候,如果不注意也会导致一些问题, 比如死锁。

    - GCD的底层方法中通过信号量机制进行线程的管理。


    串行与并行针对的是队列，而同步与异步，针对的则是线程。

#####1.dispatch_async 函数如何实现，分发到主队列和全局队列有什么区别，一定会新建线程执行任务么？

	主队列只有一个主线程是串行队列，全局队列是并行队列。分发到主队列是不会在创建线程的，串行队列中添加异步任务等同于同步任务。
	由于每个队列都维护这自己的线程池，它会根据任务列队的多少和当前系统资源负载情况增加线程数，所以不一定会新增线程执行该任务。该任务也不一定会立刻执行，也可能处于等待中。
	
	实现：
	1.如果队列是串行队列，则直接调用dispatch_barrier_async_f栏栅异步
	2.如果是并行队列，则将block添加进入并行队列的任务队列链表中，在底层线程池中，依次取出执行


#####2.dispatch_sync 函数如何实现，为什么说 GCD 死锁是队列导致的而不是线程，死锁不是操作系统的概念么？

	死锁是指同一个线程中，两个任务的相互等待导致的僵持状态。GCD是面向队列的，由队列进行多线程的管理。所以说死锁是由队列导致的。
	
	dispatch_sync采用了信号量机制，保证每次只有一个block被执行。


#####3.信号量是如何实现的，有哪些使用场景？

	dispatch_semaphore有三个API，分别是create、wait、signal。
	使用信号量时，先使用一个初始值value创建（必须大于等于0），内部实际会保存两个value，一个当前value，一个是初始记录value。
	之后使用wait和signal互逆的两个API来进行操作。wait负责给value值减一，signal负责加一。根据规则，当调用wait方法时value值小于0则阻塞当前线程直到调用signal方法。
	
	dispatch_semaphore_wait:
	1.对传入的value值减一，如果value大于等于0就立刻返回。
	2.如果value小于0，就进入等待状态
	
	dispatch_semaphore_signal：
	1.将value值加一，大于0则返回0
	2.小于等于0，则尝试唤醒信号量
	
	使用场景：
		1.加锁操作
		2.将异步操作改为同步操作，实现任务之间的前后依赖
		

#####4.dispatch_group 的等待与通知、dispatch_once 如何实现？

    dispatch_once：
    通过一个静态变量来标记 block 是否已被执行，通过原子性操作保证只有一个线程进行block的执行，其它线程添加到链表节点等待信号量的唤醒，执行完 block 后会遍历链表唤醒其它所有等待的线程。
    内部实现：
    - 1.第一次调用时，通过原子性操作判断onceToken是否为空，为空则执行block函数，结束后将标记值赋值为DONE完成。然后循环遍历一个链表发送信号量，将链表节点上其它的访问线程唤醒。
    - 2.第二次调用时，由于onceToken不为空，且标志位为DONE完成状态，直接退出，不做任何事。
    - 3.多个线程调用时，开头的原子性判断条件保证了只有一个线程能进入block的执行分支，其它线程只能进入else分支。这里面会创建一个链表，链表的每个节点都调用信号量的wait方法并阻塞。而在if分支中则会遍历所有节点并调用signal方法唤醒等待中的线程。
    
    
    
	dispatch_group 的本质就是一个 value 非常大的信号量，等待 group 完成实际上就是等待 value 恢复初始值。而 notify 的作用是将所有注册的回调组装成一个链表，在 dispatch_async 完成时判断 value 是不是恢复初始值，如果是则调用 dispatch_async 异步执行所有注册的回调。
	
	dispatch_group_wait：
	在等待时间内会一直阻塞知道添加到group中的所有block执行结束。
	内部实现：
	1.检查group的当前信号量是否等于初始信号量的值，相同则任务都执行结束，执行返回操作
	2.检查wait时间是否到期，到期则执行返回
	3.进入等待，等待结束后唤醒group。
	
	dispatch_group_notify:
	在添加到group中的所有block执行结束后会被调用执行。
	内部实现：
	其实就是讲notify的block添加到任务链表的尾部，最后进行执行。
	
	dispatch_group：
	其实是一个值为LONG_MAX的信号量值。
	
	dispatch_group_enter：
	调用dispatch_async_group会调用，对信号量值减一
	
	dispatch_group_leave：
	1.每次调用dispatch_group_leave时除了给信号量值增一
	2.判断信号量值是否等于初始信号量值。相等则所有任务执行完成，调用_dispatch_group_wake唤醒回调。
	3.调用链表，执行添加到队尾的notify回调。
	
#####5.dispatch_source 用来做定时器如何实现，有什么优点和用途？

	大致流程：
	dispatch_source 可以用来实现定时器。所有的事件回调会在用户指定的队列中执行，source由manager队列进行管理。
	按照触发时间排好序（多个source），随后找到最近触发的定时器，调用内核的 select 方法等待。
	等待结束后，依次唤醒 manager 队列和用户指定队列，最终触发一开始设置的回调 block。

	定时器实现步骤：
	1.调用dispatch_source_create创建资源，指明source类型，事件回调在哪个队列上执行。其中这个source默认由dispatch_manager_queue来管理
	2.调用dispatch_source_set_timer，首先会暂停队列，然后在manager队列上执行参数绑定，唤醒队列
	3.设置event事件
	4.调用dispatch_resume启动source，dispatch_source_cancel取消source，dispatch_suspend暂停source
	
	优点：
	1.可以自由控制精度、随时修改时间间隔
	2.可以取消、暂停
	3.不持有对象，不必担心循环引用
	4.不像NSTimer依赖线程的runLoop
	
	用途：
	需要轮询的相关的功能，可以随时取消、控制时间间隔和精度。
	dispatch_after其实也是内部使用了dispatch_source定时器。

#####6.dispatch_suspend 和 dispatch_resume 如何实现，队列的的暂停和计时器的暂停有区别么？

	每个队列都有一个状态值，source的状态值默认是lock状态，其它队列都是interval状态。dispatch_resume和dispatch_suspend就是对这个状态值得切换。
	
	dispatch_suspend并不会让队列马上暂停，只会在当前正在执行的block执行结束后才会进入暂停状态。它的暂停只是不再从人物链表中获取未执行的block进行执行。
	是否一样不清楚？？？

#####7.队列和线程的关系

	GCD是面向队列的，我们选择API向队列添加任务block。系统在GCD下面维护着一个线程池，队列根据系统负载情况增减线程并发数，执行block。

	- 并行队列，会权衡当前系统负载，去同时并发几条线程去执行Block。
	- 串行队列中，始终只在一条线程中执行Block。

	- 主队列是串行队列，队列中只有一条主线程。

	sync、async
	- 往主队列提交block，无论是sync、async，都在主线程中执行。
	- 往非主线程中提交，如果是sync，会在当前提交的Block的线程中执行。如果是async，则在分线程中执行。

#####8.GCD的死锁

	如果sync提交一个block到一个串行队列，而提交block这个动作所在的线程，也是在这个当前队列中，就会引起死锁。

#####9.API的异同和作用场景

	dispatch_async：不阻塞当前线程，添加到执行队列，根据队列情况执行。
	dispatch_barrier_async: 会阻塞当前提交block的线程，会阻塞并行队列，保证它前面的任务优先于自己执行，后面的任务都晚于自身执行。（读操作同步并行，写操作栏栅串行）
	dispatch_barrier_sync：呈上起下，和dispatch_barrier_async一样，唯一不同是会阻塞当前提交block的线程。
	dispatch_sync: 会阻塞当前提交block的线程，但不能阻塞并行队列

	- 同步和异步的使用，可以在不加锁的情况下，保证数据读写的线程安全。真正的加上是在GCD底层的信号量机制中体现。

####注意点：

    1.创建线程会有内存开销和时间开销，线程上下文的切换也需要开销。并发编程下的线程过多时性能反而会下降。
    2.资源共享会导致线程竞争和锁。多个线程对共有资源进行写操作时，会产生数据错误，造成不可预料的结果。加锁可以放在线程竞争，但也容易导致死锁。过多的锁也会有一定的开销。
    3.队列优先级越过锁
    3.并发导致资源竞争
    
#####总结

	1.dispatch_async 会把任务添加到队列的一个链表中，添加完后会唤醒队列，根据 vtable 中的函数指针，调用 wakeup 方法。在 wakeup 方法中，从线程池里取出工作线程(如果没有就新建)，然后在工作线程中取出链表头部指向的 block 并执行。

	2.dispatch_sync 的实现略简单一些，它不涉及线程池(因此一般都在当前线程执行)，而是利用与线程绑定的信号量来实现串行。同步到其它队列时，它会调用dispatch_sync_barrier_f， 保证block执行的原子性。

	3.分发到不同队列时，代码进入的分支也不一样，比如 dispatch_async 到主队列的任务由 runloop 处理，而分发到其他队列的任务由线程池处理

	4.对于信号量来说，它主要使用 signal 和 wait 这两个接口，底层分别调用了内核提供的方法。在调用 signal 方法后，先将 value 减一，如果大于零立刻返回，否则陷入等待。signal 方法将信号量加一，如果 value 大于零立刻返回，否则说明唤醒了某一个等待线程，此时由系统决定哪个线程的等待方法可以返回。

	5.dispatch_barrier_async 改变了 block 的 vtable 标记位，当它将要被取出执行时，会等待前面的 block 都执行完，然后在下一次循环中被执行。

	6.dispatch_after 函数依赖于 dispatch_source 定时器，它只是注册了一个定时器，然后在回调函数中执行 block。
