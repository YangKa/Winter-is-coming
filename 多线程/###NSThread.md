##NSThread

###创建使用：
- (instancetype)initWithTarget:(id)target selector:(SEL)selector object:(id) argument;

+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument;

###start启动
线程启动后并不会马上执行，多个线程之间是并行的，也就意味着线程的执行状态也是在运行和就绪状态之间不断切换的。
何时运行，运行的状态取决于系统的调度。

###结束
1.正常执行完结束
2.执行出错结束
3.直接调用NSThrad类的exit方法来终止当前线程。

###总结：
优：
1.NSThread创建简单，使用方便。
2.NSThread常用的是获取当前线程[NSThread currentThread]。
缺：
1.但对于多线程的管理需要手动管理，加锁，一般不使用。
2.只能接受一个参数，有局限性。



