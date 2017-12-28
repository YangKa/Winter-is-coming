## CALayer+YYAdd

1.截图

```
- (UIImage *)snapshotImage {
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.opaque, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self renderInContext:context];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
```

2.生成PDF数据

```
- (NSData *)snapshotPDF {
    
    NSMutableData* data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    
    CGRect bounds = self.bounds;
    CGContextRef context = CGPDFContextCreate(consumer, &bounds, NULL);
    CGDataConsumerRelease(consumer);
    if (!context) return nil;
    
    CGPDFContextBeginPage(context, NULL);
    CGContextTranslateCTM(context, 0, bounds.size.height);
    CGContextScaleCTM(context, 1.0, -1.0);
    [self renderInContext:context];
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
    
    return data;
}
```

3.设置阴影

```
- (void)setLayerShadow:(UIColor*)color offset:(CGSize)offset radius:(CGFloat)radius {
    self.shadowColor = color.CGColor;
    self.shadowOffset = offset;
    self.shadowRadius = radius;
    self.shadowOpacity = 1;
    //设置栅格化，减少重复绘制
    self.shouldRasterize = YES;
    self.rasterizationScale = [UIScreen mainScreen].scale;
}
```

## UIView

1.截图

```
- (UIImage *)snapshotImageAfterScreenUpdates:(BOOL)afterUpdates {
    
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.opaque, 0);
    if (![self respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)]) {
        [self.layer renderInContext:UIGraphicsGetCurrentContext()];
    }else{
        if (@available(iOS 7.0, *)) {
            [self drawViewHierarchyInRect:self.bounds afterScreenUpdates:afterUpdates];
        }else{
        }
    }
    UIImage *snap = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return snap;
}
```

2.当前view所在的viewController

```
- (UIViewController *)viewController {
    
    for (UIView *view = self; view; view = view.superview) {
        UIResponder *nextResponder = [view nextResponder];
        if ([nextResponder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)nextResponder;
        }
    }
    return nil;
}
```
