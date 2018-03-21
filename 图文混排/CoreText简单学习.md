CoreText简单学习

简介：

CoreText这个库提供了高性能的文字布局、character转换成glygh、控制glyph在行和段落上的位置显示的功能。它使用自动字体替换优化字体操作，方面访问字体信息和glygh数据。

CoreText的布局引擎是高性能、简单易用、与CoreFoundation紧密结合的。文本布局API提供了高质量的排版，包括字符到字形的转换，连字，字距等等。

CoreText中的所有单独函数都是线程安全的。
字体对象(CTFont、CTFontDescriptor和一些关联对象)能在多operations、work queue、threads中同时进行。
布局对象(CTTypesetter、CTFramesetter、CTRun、CTLine、CTFrame和关联对象)只能在单个operation、work queue、thread中使用。

库下类：

CTFont

一个字体对象

CTFontCollection

包含一组字体描述

CTFontDescriptor

包含对字体的一组描述，用使用了字典集合。

CTFrame

每帧包含多行文本，通过CTFramesetter文本处理生成。

CTFramesetter

用于生成文本帧。是CTFrame的对象工厂

CTGlyphInfo

能重载Unicode到glyph ID的字体标识符的映射

CTLine

代表一行文本

CTParagraphStyle

在属性字符串中代表了段落或线条的属性

CTRun

代表一个glyph的run，一般连续的glyph会共享相同的属性和方向信息

CTRunDelegate

代表一个run的代理，用于控制glyph的排版特征，例如上移下移和宽度


CTTextTab

一个段落的tab信息，存储了tab的排版设置

CTTypesetter

表示行布局排版
