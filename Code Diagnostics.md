Swift 
##Code Diagnostics

工具：
- Address Sanitizer 地址检测
- Thread Sanitizer 线程检测
- Main Thread Sanitizer 主线程检测
- undefined Behavior Sanitizer 不确定行为检测

---------------------------------------------------------------------------
Address Sanitizer 
简称ASan，是一个基于c和swift的LLVM基础工具。用来发现运行时期发生的内存损坏和一些内存错误。这些内存错误会导致不可预料的行为并且很难重现。

原理：
ASan用自定义的允许对分配内存周围区域无效访问的方法，替换掉malloc和free方法。

当访问malloc时，会将分配内存的周围区域标记为限制访问（off-limits）。当调用free方法时，会将这块内存区域也标记为off-limits，并添加到一个隔离的队列中。当着块区域被重新分配会有延迟。
任何对标记为off-limits区域的访问都会导致Address Sanitizer生成错误报告。

性能影响

使用Address Sanitizer会导致CPU的使用增加2x 到5x,内存占用增加2x到3x。时间开发中，这种影响可以忽略不计。

限制
- 作为运行时诊断工具，只能检测在整个运行时中的内存错误。完整的检测还是需要依赖Unit test。
- Address Sanitizer不能检测内存泄露、内存未初始化、整数溢出的情况。可以使用TSan、UBSan和Instruments去检查这些问题。

---------------------------------------------------------------------------
Main Thread Sanitizer

主线程检测是基于Swift和C语言的独立工具，用于检测在后台线程中使用APPKit、UIKit和需要在UI线程中才能使用的API的情况。在非主线程中更新UI会出现更新无效、视觉缺陷、数据损坏、crash的情况。

原理：
APP启动时，主线程检测会动态替换所有需要在主线程使用的方法，这些方法会自动提前检测。能在后台线程安全使用的方法不会保护在这个检测里。

和其它代码检测工具不同，Main Thread Check不需要重新编译，它可以直接通过lib库使用。它可以在macOS上直接运行。可以通过在持续集成系统中通过注入动态库文件的方式使用它。
文件位置在 `/Applications/Xcode.app/Contents/Developer/usr/lib/libMainThreadChecker.dylib`


性能影响
主线程检测的影响是非常小的，只占用1-2%的CPU和增加低于0.1s的启动时间。


---------------------------------------------------------------------------
Thread Sanitizer

简称ASan，是一个基于c和swift的LLVM基础工具，用于检测运行时期的data races。主要是多线程的访问同一数据源。它也可以检测线程bug，包括互斥体未初始化和内存泄露。

注意：
TSan 只支持64位的操作系统，watchOS暂不支持。所以，不应该在运行在设备上的APP上使用它。

原理：
每个线程都持有自己和其它线程的时间戳来建立同步点。每次内存被访问时就增加时间戳，然后就可以通过时间的访问时间来分析data race。

性能影响：
CPU会缓慢2x到20x， 内存会增长5x到10x。

---------------------------------------------------------------------------
undefined Behavior Sanitizer 

一个基于C语言在运行时检测不确定行为的LLVM工具。它会描述任何操作的结果。例如除0，访问野指针，关联空指针。
不确定的行为会导致crash、错误的输出、或者一点问题都没有。在不同版本会有不同的行为。

原理：
在编译的时候在代码中注入检测点。注入的代码依需要检测的行为而定。

性能影响：
影响比较小，在debug模式下会占用平均20%的CPU。