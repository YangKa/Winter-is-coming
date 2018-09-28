## APN（Application performance management， 性能监控）

App的性能问题包括崩溃、网络请求错误或超时、响应速度慢、列表滚动卡顿、流量大、耗电等。
其中大部分都是开发者错误的使用线程、锁、系统函数、编程范式、数据结构等导致的。

### 监控点

- 网络请求：成功率、状态码、流量、网络响应时间、HTTP与HTTPS的 DNS 解析、TCP握手、SSL握手（HTTP除外）、首包时间等时间
- 界面卡顿、卡顿堆栈
- 崩溃率、崩溃堆栈
- Abort 率：也就是由于内存过高的等原因，被系统杀死的情况
- 交互监控：页面加载时间、页面的交互痕迹
- 维度信息：地域、运营商、网络接入方式、操作系统、应用版本等
- 其他：内存、帧率、CPU使用率、启动时间、电量等

### 卡顿检测

#### 卡顿原理

	目前主流移动设备均采用双缓存+垂直同步的显示技术。显示系统有两个缓存区，GPU会预先渲染好一帧放入一个缓存区内，当下一帧渲染好后，GPU会直接将视频控制器的指针指向第二个容器。这里，GPU会等待显示器的VSync（垂直信号）信号发出来，然后进行新的一帧渲染和缓存区的更新。

###### 帧绘制划分：

	CPU：负责计算显示的内容，例如视图创建、布局计算、图片解码、文本绘制等，随后CPU将计算好的内容提交给 GPU。
	GPU：进行变换、合成、渲染。
	
##### 卡顿原因：

	大多数手机的屏幕刷新频率是60Hz，如果在1000/60=16.67ms内没有将这一帧的任务执行完毕，就会发生丢帧现象，这便是用户感受到卡顿的原因。
	
	除了 UI 绘制外，系统事件、输入事件、程序回调服务，以及我们插入的其他代码也都在主线程中执行，那么一旦在主线程里添加了操作复杂的代码，这些代码就有可能阻碍主线程去响应点击、滑动事件，以及阻碍主线程的 UI 绘制操作，这就是造成卡顿的最常见原因。

#### 

##### 1.通过CADisplayLink来检测FPS

	通过一段连续的 FPS 帧数计算丢帧率来衡量当前页面绘制的质量
	方式简单，但帧率不稳定。

#### 2.监控UI线程的runLoop状态，检测每次执行消息循环的时间，当这一时间大于阈值时，就记为发生一次卡顿。

	Runloop对于事件的处理主要是在kCFRunLoopBeforeSource和kCFRunLoopBeforeWaiting状态之间，还有kCFRunLoopAfterWaiting之后。可以通过对两个状态进行监控，如果消耗时间过长就代表着卡顿的发生。
	
	因为有的卡顿的连续性耗时较长，例如打开新页面时的卡顿；而有的卡顿连续性耗时相对较短但频次较快，如列表滑动时的卡顿。一个时间段内卡顿的次数累计大于N时才触发采集和上报。
	
	通过两者结合，观察FPS和卡顿信息可以评估这次卡顿APP性能究竟下降到什么了什么程度。
	
##### 2.1检测RunLoop卡顿

- 先创建子线程，给子线程runLoop添加machPort进行保活。
- 创建observer，观察mainRunLoop的状态，记录kCFRunLoopBeforeSource和kCFRunLoopBeforeWaiting的状态时间点。
- 给子线程runLoop添加一个timer，每过T时间检测runLoop是否执行结束，没有则检测执行时间是否超过阈值。从而判断是否卡顿。
		
### 防止子线程访问UI

UIKit的大部分对象都不是线程安全的，所有继承自UIResponder的类都需要在主线程操作，如果在子线程更改了这些UI对象就会导致未知道的行为，比如随机出现丢失动画、页面错乱甚至crash。

hook掉UIView、CALayer的setNeedsLayout、setNeedsDisplay、setNeedsDisplayInRect:三个方法，当调用这三个方法时判断是否在主线程，如果不在主线程调用就让程序crash，在crash堆栈能看出是哪里的问题。
	
### 崩溃检测

崩溃主要是Mach异常和Object-C异常（NSException）引起的。
可以使用三方工具`PLCrashReporter`收集。

#### Mach异常捕获
	注册一个异常端口，这个异常端口会对当前任务的所有线程有效，如果想要针对单个线程，可以通过 thread_set_exception_ports注册自己的异常端口。
	发生异常时，首先会将异常抛给线程的异常端口，然后尝试抛给任务的异常端口，当我们捕获异常时，就可以做一些自己的工作，比如，当前堆栈收集等。

#### Unix信号捕获
	Mach异常会在BSD层转换成Unix信号，可以通过捕获signal来获取mach异常。
	通过注册signalHandler的方式获取信号异常。
	signal(SIGHUP, signalHandler);
	signal(SIGINT, signalHandler);
	signal(SIGQUIT, signalHandler);
	   
	signal(SIGABRT, signalHandler);
	signal(SIGILL, signalHandler);
	signal(SIGSEGV, signalHandler);
	signal(SIGFPE, signalHandler);
	signal(SIGBUS, signalHandler);
	signal(SIGPIPE, signalHandler);


#### NSException捕获
	通过注册NSUncaughtExceptionHandler(&handler);获取NSException异常。

### Abort率检测

	对于内存过高被杀死的情况是没有办法直接统计的，一般通过排除法来做百分比的统计，原理如下：

	程序启动，设置标志位
	程序正常退出，清楚标志
	程序Crash，清楚标志
	程序电量过低导致关机，这个也没办法直接监控，可以加入电量检测来辅助判断
	第二次启动，标志位如果存在，则代表Abort一次，上传后台做统计。

### 交互控制

	通过Runtime hook对应的生命周期方法即可，比如 viewDidLoad、viewWillAppear等。
	通过观察CPU占用率和页面加载时间可以评估页面的运算复杂度。
	
### CPU占用
	

### 内存占用

	内存和 App 运行时间结合，可以观察内存和使用时长的关系进而分析是否发生内存泄漏
	
### 网络监控

对于成功率、状态码、流量，以及网络的响应时间之类的，我们可以主要可以通过两种方式来做

- 针对URLConnection、CFNetwork、NSURLSession三种网络做Hook，hook的具体技术可以是method swizzle 也可以是Proxy、Fishhook之类的
- 也可以使用 NSURLProtocol 对网络请求的拦截，进而得到流量、响应时间等信息，但是NSURLProtocol有自己的局限，比如NSURLProtocol只能拦截NSURLSession，NSURLConnection以及UIWebView，但是对于CFNetwork则无能为力

- URLConnection、CFNetwork、NSURLSession底层都是 BSDSocket，所以可以尝试在socket上动手脚来实现效果，类似于通过ViewController的生命周期方法来统计页面加载时间的做法，我们Hook socket相关的方法来做，比如通过hook socket连接时的 connect方法，拿到tcp握手的起始时间，通过hook SSLHandshake方法，在SSLHandshake执行的时候拿到 SSL握手的起始时间等。

apple在 iOS 10 推出一个API，可以在 iOS10 版本以上进行网络信息的收集

`- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics`






