 
APP启动优化

------------------------------------------------------------------------

优化思路方向：
建立优化的度量指标 -> 明确优化方向 -> 分解优化目标 -> 分步达到优化目的 -> 统一测试优化效果

确定启动入口：前台启动、后台启动、点击通知启动、其它应用启动。这里只针对点击桌面图标打开APP的启动优化。

确定应用启动完成终点：一般以首页展开为结束点，也可以以用户打开APP最有可能的第一个操作动作为参考点。比如打开APP进入具体业务模块页面。

确定启动类型：启动分为冷启动和热启动，选择冷启动
	1.冷启动。APP初次启动
	2.热启动。后台进入前台，通过applicationWillEnterForeground:接收前台事件，紧接着应用恢复

三个方向：
	1.启动初始化时间，优化pre-main和main （主要耗时阶段）
	2.网络时间，发出页面数据请求的时间 （提前异步发起，缓存数据后监听页面的显示）
	3.响应处理时间，加载数据显示到屏幕的时间 （先通过UDP通知服务器缓存响应数据，然后再TCP到来时进行返回，。渲染的图片使用异步解码）

-------------------------------------------------------------------------------

第一阶段：pre-main

-----dylib load
1.加载应用的可执行文件（所有Mach-O文件的加载）
2.加载动态链接库加载器dyld（dynamic loader）
3.dyld递归加载应用所有依赖的dyld（dynamic library 动态链接库）

动态链接库包括：所有系统framework、加载OC runtime方法的libobjc，系统级别的libSystem，例如Libdispatch（GCD）和libsystem_blocks（Block）
使用动态链接库是为了方便做更新，减少可执行文件的体积。

-----rebase/binding
4.偏移镜像内部指针，指向外部正确的指针

-----Objc steup
1.添加ibjc类、添加category中的方法

-----initializer
1.执行+load()方法
2.C++静态对象加载


-----查看pre-main时间的方法
通过修改scheme中的环境变量DYLD_PRINT_STATISTICS设置为1，查看pre-main阶段耗时时间
Total pre-main time: 3.3 seconds (100.0%)
         dylib loading time: 1.7 seconds (53.3%)  读取镜像文件
        rebase/binding time: 613.28 milliseconds (18.4%) 修复镜像中的资源指针，指向正确的地址
            ObjC setup time:  95.61 milliseconds (2.8%)  注册objc类、添加category方法、保证selector唯一
           initializer time: 840.46 milliseconds (25.2%) +load()方法的执行和C++静态构造函数的创建
           slowest intializers :
               libSystem.dylib :   2.14 milliseconds (0.0%)
       libswiftCoreImage.dylib : 101.25 milliseconds (3.0%)
                      BQReport : 1.4 seconds (43.4%)

-----优化：
- 移除不必要的framework依赖
- check framework应当设为optional和required，如果该framework在当前App支持的所有iOS系统版本都存在，那么就设为required，否则就设为optional，因为optional会有些额外的检查
- 合并或删除一些class，删减一些无用的静态变量，删减没有被调用到或者已经废弃的方法
- 将不必须在+load方法中做的事情延迟到+initialize中
- 减少C的constructor函数
- 减少C++的静态对象
- 减少静态库的引用

-------------------------------------------------------------------------------

第二阶段：main()

1.dyld调用main()
2.调用UIApplicationMain()
3.调用applicationWillFinishLaunching
4.调用didFinishLaunchingWithOptions


优化：
- 首页视图使用代码编写
- 首页的viewDidLoad及viewWillAppear的操作尽量转移到viewDidAppear中
- release版本中要屏蔽NSLog的打印，因为它会隐式的创建一个Calendar
- 减少应用在启动时发送的请求数，转移到异步线程中请求
- 三方库的注册转移到首页的viewDidLoad:中
- 启动图中图片的解码放到异步线程中处理
- 在didFinishLaunchingWithOptions中进行尽量少的操作
- 使用懒加载

-------------------------------------------------------------------------------

- 移除不需要的动态库
- 移除不需要的类
- 合并功能类似的类和扩展（Category）
- 压缩图片资源
- 优化RootViewController的价值

优化原则：
1.pre-main阶段减少不必要的耗时操作
2.main阶段将耗时操作进行转移
3.优先保证视觉上的快


------------------------------------------其它----------------------------------
Mach-O是运行时可执行文件的文件类型。
文件类型：
	- Executable:应用的主要二进制
	- Dylib：动态链接库（DSO/DLL）
	- Bundle: 不能被链接的Dylib，只能在运行时使用dlopen()加载，可当做macOS的插件。
Image：executable，dylib或bundle
Frame