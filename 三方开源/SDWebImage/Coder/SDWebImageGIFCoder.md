## SDWebImageGIFCoder

- 遵守协议SDWebImageCoder，支持gif图片的编解码
- 支持gif图片的处理，可以将该解码器添加到codeManager中，但要保证高的优先级。
- 解码处理后的gif图片显示比UIImageView性能更好。

#### 获取每一帧图片的时间

```
(float)sd_frameDurationAtIndex:(NSUInteger)index source:(CGImageSourceRef)source {
    float frameDuration = 0.1f;
    
    //获取帧图片gif属性信息
    CFDictionaryRef cfFrameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil);
    NSDictionary *frameProperties = (__bridge NSDictionary *)cfFrameProperties;
    NSDictionary *gifProperties = frameProperties[(NSString *)kCGImagePropertyGIFDictionary];
    
    //从属性中获取
    NSNumber *delayTimeUnclampedProp = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    if (delayTimeUnclampedProp) {
        frameDuration = [delayTimeUnclampedProp floatValue];
    } else {
        NSNumber *delayTimeProp = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
        if (delayTimeProp) {
            frameDuration = [delayTimeProp floatValue];
        }
    }
    
    //将帧时间小于a duration of <= 10 ms，同一修改为100ms
    if (frameDuration < 0.011f) {
        frameDuration = 0.100f;
    }
    
    CFRelease(cfFrameProperties);
    return frameDuration;
}
```

#### 根据图片数据创建动画图片

- 获取imageSource和帧数
- 循环获取每一帧和时间创建帧对象
- 获取图片属性，查询轮询次数
- 创建UIImage对象`animatedImageNamed: duration:`

```
- (UIImage *)decodedImageWithData:(NSData *)data {
    
    if (!data) {
        return nil;
    }
    
    //创建imageSource，获取图片帧数
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) {
        return nil;
    }
    size_t count = CGImageSourceGetCount(source);
    
    UIImage *animatedImage;
    if (count <= 1) {
        //只有一帧动画
        animatedImage = [[UIImage alloc] initWithData:data];
    } else {
        NSMutableArray<SDWebImageFrame *> *frames = [NSMutableArray array];
        //循环获取每一帧，创建SDWebImageFrame对象
        for (size_t i = 0; i < count; i++) {
            //帧图片
            CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (!imageRef) {
                continue;
            }
            //帧时间
            float duration = [self sd_frameDurationAtIndex:i source:source];
            //图片scale
            CGFloat scale = 1;
            scale = [UIScreen mainScreen].scale;
            //图片
            UIImage *image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
            CGImageRelease(imageRef);
            //创建SDWebImageFrame对象并保存
            SDWebImageFrame *frame = [SDWebImageFrame frameWithImage:image duration:duration];
            [frames addObject:frame];
        }
        
        //获取图片图片属性中gif信息
        NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(source, nil);
        NSDictionary *gifProperties = [imageProperties valueForKey:(__bridge_transfer NSString *)kCGImagePropertyGIFDictionary];
        
        //查询gif图片的循环次数
        NSUInteger loopCount = 0;
        if (gifProperties) {
            NSNumber *gifLoopCount = [gifProperties valueForKey:(__bridge_transfer NSString *)kCGImagePropertyGIFLoopCount];
            if (gifLoopCount) {
                loopCount = gifLoopCount.unsignedIntegerValue;
            }
        }
        //根据这些帧对象重新创建新的图片
        animatedImage = [SDWebImageCoderHelper animatedImageWithFrames:frames];
        animatedImage.sd_imageLoopCount = loopCount;
    }
    //释放C对象
    CFRelease(source);
    
    return animatedImage;
}
```

#### 解压缩

gif图片不能解压缩，直接不处理。

#### 是否能编解码

获取image的格式SDImageFormat，验证是否是gif图片。

#### 编码

目的：给图片及每一帧添加gif信息

```
- (NSData *)encodedDataWithImage:(UIImage *)image format:(SDImageFormat)format {
    
    if (!image || format != SDImageFormatGIF) {
        return nil;
    }
    
    NSMutableData *imageData = [NSMutableData data];
    
    //gif格式对应的的UTType
    CFStringRef imageUTType = [NSData sd_UTTypeFromSDImageFormat:SDImageFormatGIF];
    //图片的所有帧对象
    NSArray<SDWebImageFrame *> *frames = [SDWebImageCoderHelper framesFromAnimatedImage:image];
    
    // Create an image destination. GIF does not support EXIF image orientation
    CGImageDestinationRef imageDestination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)imageData, imageUTType, frames.count, NULL);
    if (!imageDestination) {
        return nil;
    }
    
    if (frames.count == 0) {
        // 单张图片
        CGImageDestinationAddImage(imageDestination, image.CGImage, nil);
    } else {
        // 设置gif图片的属性信息
        NSUInteger loopCount = image.sd_imageLoopCount;
        NSDictionary *gifProperties = @{(__bridge_transfer NSString *)kCGImagePropertyGIFDictionary: @{(__bridge_transfer NSString *)kCGImagePropertyGIFLoopCount : @(loopCount)}};
        CGImageDestinationSetProperties(imageDestination, (__bridge CFDictionaryRef)gifProperties);
        
        // 循环设置单帧图片的属性信息
        for (size_t i = 0; i < frames.count; i++) {
            SDWebImageFrame *frame = frames[i];
            float frameDuration = frame.duration;
            CGImageRef frameImageRef = frame.image.CGImage;
            NSDictionary *frameProperties = @{(__bridge_transfer NSString *)kCGImagePropertyGIFDictionary : @{(__bridge_transfer NSString *)kCGImagePropertyGIFUnclampedDelayTime : @(frameDuration)}};
            CGImageDestinationAddImage(imageDestination, frameImageRef, (__bridge CFDictionaryRef)frameProperties);
        }
    }
    
    // Finalize the destination.
    if (CGImageDestinationFinalize(imageDestination) == NO) {
        // Handle failure.
        imageData = nil;
    }
    CFRelease(imageDestination);
    
    return [imageData copy];
}
```