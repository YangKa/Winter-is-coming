###Runtime

RunTime简称运行时。就是系统在运行的时候的一些机制，其中最主要的是消息机制。对于C语言，函数的调用在编译的时候会决定调用哪个函数（ C语言的函数调用请看这里 ）。编译完成之后直接顺序执行，无任何二义性。OC的函数调用成为消息发送。属于动态调用过程。在编译的时候并不能决定真正调用哪个函数（事实证明，在编 译阶段，OC可以调用任何函数，即使这个函数并未实现，只要申明过就不会报错。而C语言在编译阶段就会报错）。只有在真正运行的时候才会根据函数的名称找 到对应的函数来调用。

####常用功能
- 1.使用关联对象(AssociateObject)动态添加属性。主要用于category。
- 2.method swizzling，实现方法交换。可用于hook、日志记录。
- 3.isa swizzling。KVO实现原理。
- 4.属性遍历、修改、添加属性。
- 5.实现字典转模型的自动转换。（MJExtension的原理）
- 6.实现NSCoding的自动归档和解档

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

   	  Person *onePerson = [[Person alloc] init];
     NSLog(@"first time : %@",[onePerson description]);

     unsigned  int count = 0;
     Ivar *members = class_copyIvarList([Person class], &count);

     for (int i = 0; i < count; i++)
     {
         Ivar var = members[i];
         const charchar *memberAddress = ivar_getName(var);
         const charchar *memberType = ivar_getTypeEncoding(var);
         NSLog(@"address = %s ; type = %s",memberAddress,memberType);
              }

    //对私有变量的更改
    Ivar m_address = members[1];
    object_setIvar(onePerson, m_address, @"朝阳公园");
    NSLog(@"second time : %@",[onePerson description]);

####5.实现字典转模型的自动转换

unsigned int outCount = 0;
objc_property_t *properties = class_copyPropertyList(self.class, &outCount);
for (int i = 0; i < outCount; i++) {
    objc_property_t property = properties[i];
    const char *propertyName = property_getName(property);
    NSString *key = [NSString stringWithUTF8String:propertyName];

    id value = nil;

    if (![dict[key] isKindOfClass:[NSNull class]]) {
        value = dict[key];
    }

    unsigned int count = 0;
    objc_property_attribute_t *atts =  property_copyAttributeList(property, &count);
    objc_property_attribute_t att = atts[0];
    NSString *type = [NSString stringWithUTF8String:att.value];
    type = [type stringByReplacingOccurrencesOfString:@"“" withString:@""];
    type = [type stringByReplacingOccurrencesOfString:@"@" withString:@""];

    NSLog(@"type%@",type);

    //数据为数组时
    if ([value isKindOfClass:[NSArray class]]) {
        Class class = NSClassFromString(key);
        NSMutableArray *temArr = [[NSMutableArray alloc] init];
        for (NSDictionary *tempDic in value) {
            if (class) {
                id model = [[class alloc] initWithDic:tempDic];
                [temArr addObject:model];
            }
        }
        value = temArr;
    }

    //数据为字典时
    if ([value isKindOfClass:[NSDictionary class]] && ![type hasPrefix:@"NS"] ) {
        Class class = NSClassFromString(key);
        if (class) {
            value = [[class alloc] initWithDic:value];
        }
    }



####6.实现NSCoding的自动归档和解档

unsigned int outCount = 0;
Ivar ivars = class_copyIvarList(self.class, &outCount);
for (int i = 0; i< outCount; i++) {
      Ivar ivar = ivars[i];
     const char ivarName = ivar_getName(ivar);
     NSString ivarNameStr = [NSString stringWithUTF8String:ivarName];
      NSString setterName = [ivarNameStr substringFromIndex:1];

        //解码
        id obj = [aDecoder decodeObjectForKey:setterName]; //要注意key与编码的key是一致的
        SEL setterSel = [self creatSetterWithKey:setterName];
        if (obj) {
            ((void (*)(id ,SEL ,id))objc_msgSend)(self,setterSel,obj);
        }

    }
    free(ivars);