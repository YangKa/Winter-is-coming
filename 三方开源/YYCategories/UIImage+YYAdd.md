## UIImage+YYAdd

1.获取gif图片某一帧的持续时间

```
static NSTimeInterval _yy_CGImageSourceGetGIFFrameDelayAtIndex(CGImageSourceRef source, size_t index) {
    NSTimeInterval delay = 0;
    CFDictionaryRef dic = CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    if (dic) {
        CFDictionaryRef dicGIF = CFDictionaryGetValue(dic, kCGImagePropertyGIFDictionary);
        if (dicGIF) {
            NSNumber *num = CFDictionaryGetValue(dicGIF, kCGImagePropertyGIFUnclampedDelayTime);
            if (num.doubleValue <= __FLT_EPSILON__) {
                num = CFDictionaryGetValue(dicGIF, kCGImagePropertyGIFDelayTime);
            }
            delay = num.doubleValue;
        }
        CFRelease(dic);
    }
    
    // http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility
    if (delay < 0.02) delay = 0.1;
    return delay;
}
```

2.验证是否是gif图片

2.1 根据图片数据判断

```
+ (BOOL)isAnimatedGIFData:(NSData *)data {
    if (data.length < 16) return NO;
    UInt32 magic = *(UInt32 *)data.bytes;
    // http://www.w3.org/Graphics/GIF/spec-gif89a.txt
    if ((magic & 0xFFFFFF) != '\0FIG') return NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFTypeRef)data, NULL);
    if (!source) return NO;
    size_t count = CGImageSourceGetCount(source);
    CFRelease(source);
    return count > 1;
}
```

2.2 根据文件路径判断

```
+ (BOOL)isAnimatedGIFFile:(NSString *)path {
    if (path.length == 0) return NO;
    const char *cpath = path.UTF8String;
    FILE *fd = fopen(cpath, "rb");
    if (!fd) return NO;
    
    BOOL isGIF = NO;
    UInt32 magic = 0;
    if (fread(&magic, sizeof(UInt32), 1, fd) == 1) {
        if ((magic & 0xFFFFFF) == '\0FIG') isGIF = YES;
    }
    fclose(fd);
    return isGIF;
}
```

3.颜色图片

3.1 普通颜色

```
+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
    if (!color || size.width <= 0 || size.height <= 0) return nil;
    CGRect rect = CGRectMake(0.0f, 0.0f, size.width, size.height);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, rect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
```

3.2 通过tintColor颜色创建图片

```
- (UIImage *)imageByTintColor:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(self.size, NO, self.scale);
    CGRect rect = CGRectMake(0, 0, self.size.width, self.size.height);
    [color set];
    UIRectFill(rect);
    [self drawAtPoint:CGPointMake(0, 0) blendMode:kCGBlendModeDestinationIn alpha:1];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}
```

4.是否含有透明通道

```
- (BOOL)hasAlphaChannel {
    if (self.CGImage == NULL) return NO;
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(self.CGImage) & kCGBitmapAlphaInfoMask;
    return (alpha == kCGImageAlphaFirst ||
            alpha == kCGImageAlphaLast ||
            alpha == kCGImageAlphaPremultipliedFirst ||
            alpha == kCGImageAlphaPremultipliedLast);
}
```

5.截取图片局部区域

```
- (UIImage *)imageByCropToRect:(CGRect)rect {
    rect.origin.x *= self.scale;
    rect.origin.y *= self.scale;
    rect.size.width *= self.scale;
    rect.size.height *= self.scale;
    
    if (rect.size.width <= 0 || rect.size.height <= 0) return nil;
    CGImageRef imageRef = CGImageCreateWithImageInRect(self.CGImage, rect);
    UIImage *image = [UIImage imageWithCGImage:imageRef scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(imageRef);
    return image;
}
```

6.给图片提添加内边距

```
- (UIImage *)imageByInsetEdge:(UIEdgeInsets)insets withColor:(UIColor *)color {
    
    CGSize size = self.size;
    size.width -= insets.left + insets.right;
    size.height -= insets.top + insets.bottom;
    if (size.width <= 0 || size.height <= 0) return nil;
    
    CGRect rect = CGRectMake(-insets.left, -insets.top, self.size.width, self.size.height);
    
    UIGraphicsBeginImageContextWithOptions(size, NO, self.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (color) {
        CGContextSetFillColorWithColor(context, color.CGColor);
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, CGRectMake(0, 0, size.width, size.height));
        CGPathAddRect(path, NULL, rect);
        
        CGContextAddPath(context, path);
        CGContextEOFillPath(context);
        CGPathRelease(path);
    }
    [self drawInRect:rect];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
```

7.角度和度之间转换

7.1 度转换成角度

```
static inline CGFloat DegreesToRadians(CGFloat degrees) {
    return degrees * M_PI / 180;
}
```

7.2 角度转换成度

```
static inline CGFloat RadiansToDegrees(CGFloat radians) {
    return radians * 180 / M_PI;
}
```

8.获取图片内边距内的内容

```
- (UIImage *)imageByInsetEdge:(UIEdgeInsets)insets withColor:(UIColor *)color {
    
    CGSize size = self.size;
    size.width -= insets.left + insets.right;
    size.height -= insets.top + insets.bottom;
    if (size.width <= 0 || size.height <= 0) return nil;
    
    CGRect rect = CGRectMake(-insets.left, -insets.top, self.size.width, self.size.height);
    
    UIGraphicsBeginImageContextWithOptions(size, NO, self.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (color) {
        CGContextSetFillColorWithColor(context, color.CGColor);
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, CGRectMake(0, 0, size.width, size.height));
        CGPathAddRect(path, NULL, rect);
        
        CGContextAddPath(context, path);
        CGContextEOFillPath(context);
        CGPathRelease(path);
    }
    [self drawInRect:rect];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
```

9.  图片旋转

```
- (UIImage *)imageByRotate:(CGFloat)radians fitSize:(BOOL)fitSize {
    size_t width = (size_t)CGImageGetWidth(self.CGImage);
    size_t height = (size_t)CGImageGetHeight(self.CGImage);
    CGRect newRect = CGRectApplyAffineTransform(CGRectMake(0., 0., width, height),
                                                fitSize ? CGAffineTransformMakeRotation(radians) : CGAffineTransformIdentity);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 (size_t)newRect.size.width,
                                                 (size_t)newRect.size.height,
                                                 8,
                                                 (size_t)newRect.size.width * 4,
                                                 colorSpace,
                                                 kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;
    
    CGContextSetShouldAntialias(context, true);
    CGContextSetAllowsAntialiasing(context, true);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    
    CGContextTranslateCTM(context, +(newRect.size.width * 0.5), +(newRect.size.height * 0.5));
    CGContextRotateCTM(context, radians);
    
    CGContextDrawImage(context, CGRectMake(-(width * 0.5), -(height * 0.5), width, height), self.CGImage);
    CGImageRef imgRef = CGBitmapContextCreateImage(context);
    UIImage *img = [UIImage imageWithCGImage:imgRef scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(imgRef);
    CGContextRelease(context);
    return img;
}
```



