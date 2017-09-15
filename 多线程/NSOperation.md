##NSOperation

###介绍：
NSOpeation作为一个抽象类，包含单个task的管理代码和数据。
我们使用它的具体子类，NSInvocationOperation和NSBlockOperation。也可以自己定义它的子类使用。

###执行方式：
1.需要执行Operation时，将这个task添加到NSOperationQueue,queue并不会直接执行这个task，而是另开一个线程异步执行它，或者采用libdispatch执行它。
2.直接调用Operation的start方法，它会直接在当前线程同步执行。手动执行会增加代码负担，因为直接执行一个不在ready状态的operation将会抛出异常，我们需要手动管理它的状态，控制他的生命周期。
3.直接使用Operation的main方法，执行结束他的状态编程finish，operation会从queue中移除。而start结束后需要finish属性不会改变。


###操作依赖:

1.可以为通过`addDependency:`和`removeDependency:`为operation之间添加依赖关系。被依赖的操作只要执行结束，不管成功还是失败，或者cancel，都算执行完成。这时依赖它们的operation就会进入ready状态准备执行。
2.通过`@property NSOperationQueuePriority queuePriority;`设置operation执行优先级。

```
	typedef NS_ENUM(NSInteger, NSOperationQueuePriority) {
		NSOperationQueuePriorityVeryLow = -8L,
		NSOperationQueuePriorityLow = -4L,
		NSOperationQueuePriorityNormal = 0,
		NSOperationQueuePriorityHigh = 4,
		NSOperationQueuePriorityVeryHigh = 8
	};
```

希望operation执行结束后执行操作可以使用`void (^completionBlock) void`。

###KVO-KVC

operation的属性采用了OKV和KVC模式。我们可以通过建立KVO来观察一下属性来对做出响应操作：

- isCancelled -readonly
- isAsyncchronous -readonly
- isExecuting -readonly
- isFinished -readonly
- isReady -readonly
- dependencies -readonly
- queuePriority readwrite
- completionBlock readwrite

note: 
1.不应该将这些属性变化和UI直接绑定，因为UI操作是在main线程，而operation的执行可能在另一个线程。
2.子类化的operation中添加的属性也建议采用KVOheKVC模式

###线程安全
NSOperation采用的是multicore aware，是线程安全的，访问对象时不需要添加额外的同步锁。
note：对于子类化中添加的方法，我们也要保证这些方法的线程访问安全，所以需要采用同步访问数据的方式去保护数据。

###NSInvocationOperation

####使用：

- - initWithTarget:selector:object:

- - initWithInvocation:

####属性

- invocation，关联的invocation
- resulte，任务执行的结果


###NSBlockOperation

异步执行，所有block在不同的线程。

####使用：

- + blockOperationWithBlock:(void (^)(void))block;
- - addExecutionBlock:(void (^)(void))block;

####属性

- executionBlocks, 该operation下所有的blocks

###总结：
1.线程安全
2.queue中异步执行
3.可以操作依赖，设置优先级

###NSOperation是否能取消
NSOperationQueue中正在执行的任务（状态为isExecuting）是不能直接通过cancel或cancelAllOperation来取消的，只能取消在wait状态的任务。

1.通过在任务执行代码中不断检测当前queue的状态来判断是否直接结束。
2.继承NSOperation，重写main方法，这个方法会自动加入AutoReleasepool来管理内存。通过在这个方法中判断self.iscancelled来决定是否立刻结束。
