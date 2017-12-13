## UICountingLabel

### 原理：

	通过CADisplayLink以一定频率修改当前时间进度，并通过动画算法转换进度，得到符合动画算法的进度值。
	并通过设置的block或format格式来显示内容。

#### 1.采用CADisplayLink，默认以每秒30次更新当前内容。

	  CADisplayLink添加到mainRunLoop的 NSDefaultRunLoopMode和UI滚动UITrackingRunLoopMode模式下。
	  因为更新的计算量非常少，所以直接更新的所以操作在主线程中进行。

#### 2.内容显示有四种动画选择，其实就是基于不同的曲线算法，这些算法都经过（0，0）和（1，1）这两个点。

	分别是：
	UILabelCounterLinear
	UILabelCounterEaseIn
	UILabelCounterEaseOut
	UILabelCounterEaseInOut

	4个NSObject分别遵守UILabelCounter协议，实现- (CGFloat)update:(CGFloat)t;
	分别实现不同的曲线算法，保证数字递增进度符合动画特点。

	实质就是转换当前内容改变进度，符合某种曲线规律。

#### 3.进度progress=时间差/总时间，时间是间隔累积的，这样子可能会大于1，这里要做个判断限制。

#### 4.内容显示格式通过`formatBlock`或`attributedFormatBlock`来讲内容显示风格转交用户设置。以block的形势封装数据风格。