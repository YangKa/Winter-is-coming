###Runtime

####常用功能
- 1.使用关联对象(AssociateObject)动态添加属性。主要用于category。
- 2.method swizzling，实现方法交换。可用于hook、日志记录。
- 3.isa swizzling。KVO实现原理。
- 4.属性遍历、修改、添加属性。
- 5.实现字典转模型的自动转换。（MJExtension的原理）
- 6.HOOK

####1.关联对象(AssociateObject)

//和属性管理语言一致。
typedef OBJC_ENUM(uintptr_t, objc_AssociationPolicy) {
    OBJC_ASSOCIATION_ASSIGN = 0,          
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1, 
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3,   
    OBJC_ASSOCIATION_RETAIN = 01401,      
    OBJC_ASSOCIATION_COPY = 01403          
};

//关联对象
objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy)

//获取关联对象
objc_getAssociatedObject(id object, const void *key)

//移除所以关联对象
objc_removeAssociatedObjects(id object)

- note：移除关联属性时防止移除其他对象添加的属性，应该使用nil设置objc_setAssociatedObject去重置已经关联的对象。

####2.method swizzling

方式一：
```
Method m1 = class_getInstanceMethod([ShowExchange class], @selector(firstMethod));
Method m2 = class_getInstanceMethod([ShowExchange class], @selector(secondMethod));
method_exchangeImplementations(m1, m2);
ShowExchange *test = [ShowExchange new];
[test firstMethod];
```

方式二：
```

- (void)hook{
  Method m1 = class_getInstanceMethod([self class], @selector(viewWillAppear:));
  Method m2 = class_getInstanceMethod([self class], @selector(wxs_viewWillAppear:));
  BOOL isSuccess = class_addMethod([self class], @selector(viewWillAppear:), method_getImplementation(m2), method_getTypeEncoding(m2));
  - if (isSuccess) {

    // 添加成功：说明源方法m1现在的实现为交换方法m2的实现，现在将源方法m1的实现替换到交换方法m2中
    class_replaceMethod([self class], @selector(wxs_viewWillAppear:), method_getImplementation(m1), method_getTypeEncoding(m1));


  }else {

    //添加失败：说明源方法已经有实现，直接将两个方法的实现交换即
    method_exchangeImplementations(m1, m2);


  }
}

-(void)viewWillAppear:(BOOL)animated {
    NSLog(@"viewWillAppear");
}

```

####3.isa swizzling

修改class的isa指针，指向另一个class。这样当访问当前class时，实际上在访问另一个class。

- KVO要手动触发观察方法，需要手动调用`willChangeValueForKey:`和`didChangeValueForKey:`。
当我们添加观察对象时，实际上就是用runtim新生成一个子类，然后重写观察的对象setter方法，在重写方法中添加`willChangeValueForKey:`和`didChangeValueForKey:`。
- 移除观察者，也只是简单的将isa指向原来的类对象中。

####4.属性访问编辑

####5.实现字典转模型的自动转换