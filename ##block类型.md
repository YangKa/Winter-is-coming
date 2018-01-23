##block类型

block分为全局块、栈块、堆块

####MRC和ARC下创建block的时候：
	1.block最多只引用了全局变量，则为全局块
	2.其它情况，如引用了局部变量、实例变量、属性则为栈块

MRC情况下，block引用局部变量、实例变量、属性则是栈块。
ARC下生成的是堆块。

ARC下的栈块进行copy会变成堆块。
对全局块发送retain、release、copy都无效，block依然在全局区。

####内存管理：

	不管是对block进行retian、copy、release,block的引用计数都不会增加，始终为1。

	NSGlobalBlock:使用retain、copy、release都无效，block依旧存在全局区，且没有释放, 使用copy和retian只是返回block的指针。

	NSStackBlock:使用retain、release操作无效；栈区block会在方法返回后将block空间回收； 使用copy将栈区block复制到堆区，可以长久保留block的空间，以供后面的程序使用。

	NSMallocBlock:支持retian、release，虽然block的引用计数始终为1，但内存中还是会对引用进行管理，使用retain引用+1， release引用-1； 

	对于NSMallocBlock使用copy之后不会产生新的block，只是增加了一次引用，类似于使用retian。

