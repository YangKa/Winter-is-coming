#GCD

GCD是一个基于C的API，一种与block有关的技术，提供了对线程的抽象。它在后台管理着一个线程池，开发者不用直接和线程打交道，只需要向队列中添加代码块即可。
由GCD来集中管理线程，缓解大量线程被创建的问题。
这种模式将大量task考虑为一个队列，而不是一堆线程，更容易掌握和使用。

##队列

```
	串行队列 
	_syncQueue = dispatch_queue_create("com.xxxx.xxx", NULL)

	并行队列
	_syncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PROORITY_DEFAULT, 0)
```

####GCD有5个公开的队列：
- 运行在主线程的main queue
- 3个不同优先级的后台
- 一个优先级更低的后台队列(用于I/O)

####自定义队列
- 用户可以创建自己定义的队列，分为串行和并行队列。
- 自定义队列中被调度的所有block最终都将被放入到系统的全局队列中和线程池中。

####note
- 大多数情况下采用默认的优先级队列，因为可能产生不同优先级的队列对共享资源的竞争。比如低优先级的任务阻塞了高优先级的任务。

##同步异步

```
	同步异步
	dispatch_sync()
	dispatch_async()

	栅栏（barrier）异步/同步    
	dispatch_barrier_async()
	dispatch_barrier_sync()
```

对队列中，栅栏块必须单独执行，不能与其它块并行。这只对并发队列有意义。
并发队列如果发现接下来执行的是个栅栏块，那么就会一直等待当前所有并发块都执行结束，然后来单独执行这个栅栏块。栅栏块结束后，再按正常方式继续向下进行处理。
将同步和异步派发结合起来，可以实现与普通加锁机制一样的同步行为，而这么做却不会阻塞执行异步派发的线程。

###group
多个任务合并到一个队列中执行

- 可以把不同优先级的任务归于一个组，并在执行完时获得通知。
- 要是把所有任务都放入串行队列中，那这个group就失去了意义。只需要在最后在添加一个block以达到notify的效果。

###dispatch_once
只执行一次

- 采用`原子访问`来查询标记，以判断其对应的代码已经执行过。

###dispatch_after
在一定时间后执行添加的block。

###dispatch_apply
`dispatch_apply(size_t iterations, dispatch_queue_t queue, void(^block)(size_t))`

重复执行iterations次。

- 会持续阻塞，知道所有任务完成为止。如加入的块派给了当前队列或高于当前队列的串行队列，会产生死锁。
- 如果采用并发队列，那么系统可以根据资源情况来并发执行这些块。

