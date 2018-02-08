## AAChartKit

### 原理：

1.使用原生类进行各种图表属性的配置，并转换成js能处理的json字符串。
2.然后使用webView加载引用js图表库框架的html，然后执行传入对应的配置参数进行js函数操作。
3.通过对配置参数的修改进行图表的变化控制。
等同于图表设置交给oc，图表渲染交给js。并且可以利用WKWebView自动管理内存释放的特性youhua

### js图表渲染

Highcharts 是一个用纯 JavaScript 编写的一个图表库， 能够很简单便捷的在 Web 网站或是 Web 应用程序添加有交互性的图表，并且免费提供给个人学习、个人网站和非商业用途使用。

Highcharts 支持的图表类型有直线图、曲线图、区域图、柱状图、饼状图、散状点图、仪表图、气泡图、瀑布流图等多达 20 种图表，其中很多图表可以集成在同一个图形中形成混合图。

### 关键宏类AAGlobalMacro

#define AAObject(objectName) [[objectName alloc]init] 

//头文件设置属性和属性设置方法
#define AAPropStatementAndFuncStatement(propertyModifier,className, propertyPointerType, propertyName)                  \
@property(nonatomic,propertyModifier)propertyPointerType  propertyName;                                                 \
- (className * (^) (propertyPointerType propertyName)) propertyName##Set;

//实现文件中实现该属性设置
#define AAPropSetFuncImplementation(className, propertyPointerType, propertyName)                                       \
- (className * (^) (propertyPointerType propertyName))propertyName##Set{   
                                             \
	return ^(propertyPointerType propertyName) {                                                                            \
		self.propertyName = propertyName;                                                                                       \
		return self;                                                                                                            \
	};                                                                                                                      \
}

作用是实现点语法，一是方便属性的设置，而是简化model类型的创建

### AAJsonConverter

一个转换工具，使用runtime和KVO将model对象转换成字典，然后转换成json字符串。

两个关键方法：

```
+ (NSDictionary*)getObjectData:(id)obj {
    NSMutableDictionary *dic = [NSMutableDictionary dictionary];
    unsigned int propsCount;
    Class class = [obj class];
    do {
        objc_property_t *props = class_copyPropertyList(class, &propsCount);
        for (int i = 0;i < propsCount; i++) {
            objc_property_t prop = props[i];
            
            NSString *propName = [NSString stringWithUTF8String:property_getName(prop)];
            id value = [obj valueForKey:propName];
            if (value == nil) {
                value = [NSNull null];
                continue;
            } else {
                value = [self getObjectInternal:value];
            }
            [dic setObject:value forKey:propName];
        }
        class = [class superclass];
    } while (class != [NSObject class]);
    
    return dic;
}
```

使用递归对数据进行遍历
```
+ (id)getObjectInternal:(id)obj {
    if (   [obj isKindOfClass:[NSString class]]
        || [obj isKindOfClass:[NSNumber class]]
        || [obj isKindOfClass:[NSNull   class]] ) {
        return obj;
    }
    
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *objarr = obj;
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:objarr.count];
        for (int i = 0;i < objarr.count; i++) {
            [arr setObject:[self getObjectInternal:[objarr objectAtIndex:i]] atIndexedSubscript:i];
        }
        return arr;
    }
    
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *objdic = obj;
        NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithCapacity:[objdic count]];
        for (NSString *key in objdic.allKeys) {
            [dic setObject:[self getObjectInternal:[objdic objectForKey:key]] forKey:key];
        }
        return dic;
    }
    return [self getObjectData:obj];
}

```

### 图表配置

作者根据Highcharts的对不同图表的配置建立了一个model集合，方便对不同样式配置的组合。

最基础的是AAChartModel，对应HightChart上的chart配置集合和其它样式的属性设置，它确定了图标的基调，大致是个什么表。

### AAOptionsConstructor

通过将AAChartModel进行分解成不同的样式配置，然后创建一个AAoptions对象进行持有，这个类实质持有一个图表各个样式的配置集合。

然后通过AAJsonConvert使用runtime对AAoptions对象进行转换，生成对应的json字符串

将样式配置jsonString传入js函数，通过webView进行绘制渲染。

### webView

这里提供了一个html文件和5个js文件用于图表的绘制渲染。使用webView执行js绘制函数。

```
if (AASYSTEM_VERSION >= 9.0) {
        [_wkWebView  evaluateJavaScript:funcitonNameStr completionHandler:^(id item, NSError * _Nullable error) {
            if (error) {
                AADetailLog(@"☠️☠️💀☠️☠️WARNING!!!!! THERE ARE SOME ERROR INFOMATION_______%@",error);
            }
        }];
    } else {
        [_uiWebView  stringByEvaluatingJavaScriptFromString:funcitonNameStr];
    }
```

1.将配置的json字符串传入`function loadTheHighChartView (sender,receivedWidth,receivedHeight)`
2.然后进行js层面的参数处理，这里接收渲染的参数和上下文大小
3.通过图表构造函数 Highcharts.Chart('container', {样式配置}) 来创建图表方法进行渲染


