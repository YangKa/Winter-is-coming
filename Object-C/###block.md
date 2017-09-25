###block

块是一种代替函数指针的语法结构。使用函数指针时，需要用"不透明的void指针"来传递状态。改用块可以把原来用标准C语言特性编写的代码封装成简明易用的接口。

块会把它所捕获的变量都拷贝一份，拷贝并不是对象本身，而是这些对象的指针变量。（浅拷贝）

####分类

块有三种类型：全局块、堆块、栈块

####如何区分

#####创建
- 如果一个block中引用了全局变量，或者没有引用任何外部变量（属性、实例变量、局部变量），那么该block为全局块。
- 其它引用情况为栈块。

堆块需要在赋值给其它对象时判断：
#####ARC
- 如果block是栈块，那么被赋值对象是堆块。因为block的赋值采用的copy，会将block转移到堆上。
- 如果block是全局块或堆块，那么被赋值对象依然是全局块或堆块。

#####MRC

将block赋值给其他对象时，block是什么类型，被赋值对象就是什么类型。