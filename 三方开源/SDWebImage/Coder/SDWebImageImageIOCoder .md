## SDWebImageImageIOCoder 

- 遵守<SDWebImageProgressiveCoder>协议，可以对图片进行增量解码。
- 支持PNG、JPEG、TIFF，包括渐进式解码
- gif图片只支持第一帧处理
- HEIC是系统本地支持，支持条件：`(iOS 11 || macOS 10.13) && (isMac || isIPhoneAndA10FusionChipAbove) && (!Simulator)`


#### 全局静态变量

```
static const size_t kBytesPerPixel = 4;
static const size_t kBitsPerComponent = 8;

//the maximum size in MB of the decoded image 
static const CGFloat kDestImageSizeMB = 60.0f;

static const CGFloat kSourceImageTileSizeMB = 20.0f;

static const CGFloat kBytesPerMB = 1024.0f * 1024.0f;
static const CGFloat kPixelsPerMB = kBytesPerMB / kBytesPerPixel;
static const CGFloat kDestTotalPixels = kDestImageSizeMB * kPixelsPerMB;
static const CGFloat kTileTotalPixels = kSourceImageTileSizeMB * kPixelsPerMB;

static const CGFloat kDestSeemOverlap = 2.0f;
```

#### 检测是否支持HEIC

```
+ (BOOL)canEncodeToHEICFormat {
    static BOOL canEncode = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableData *imageData = [NSMutableData data];
        CFStringRef imageUTType = [NSData sd_UTTypeFromSDImageFormat:SDImageFormatHEIC];
        
        // Create an image destination.
        CGImageDestinationRef imageDestination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)imageData, imageUTType, 1, NULL);
        if (imageDestination) {
            // Can encode to HEIC
            CFRelease(imageDestination);
            canEncode = YES;
        } else {
            // Can't encode to HEIC
            canEncode = NO;
        }
    });
    return canEncode;
}
```

#### 图片解码

如果是gif图片则使用第一帧，否则修正下图片的方向

```
- (UIImage *)decodedImageWithData:(NSData *)data {
    if (!data) return nil;
    
    //默认创建的UIImage图片方向是垂直的UIImageOrientationUp
    UIImage *image = [[UIImage alloc] initWithData:data];
    if (!image) {
        return nil;
    }
    
    //gif 处理
    SDImageFormat format = [NSData sd_imageFormatForImageData:data];
    if (format == SDImageFormatGIF) {
        image = [UIImage animatedImageWithImages:@[image] duration:image.duration];
        return image;
    }
    //修正图片的方向
    UIImageOrientation orientation = [[self class] sd_imageOrientationFromImageData:data];
    if (orientation != UIImageOrientationUp) {
        image = [UIImage imageWithCGImage:image.CGImage
                                    scale:image.scale
                              orientation:orientation];
    }
    return image;
}
```

#### 图片编码

```
- (NSData *)encodedDataWithImage:(UIImage *)image format:(SDImageFormat)format {
    if (!image) {
        return nil;
    }
    //含有透明通道时为PNG，没有为JPEG
    if (format == SDImageFormatUndefined) {
        BOOL hasAlpha = SDCGImageRefContainsAlpha(image.CGImage);
        if (hasAlpha) {
            format = SDImageFormatPNG;
        } else {
            format = SDImageFormatJPEG;
        }
    }
    
    NSMutableData *imageData = [NSMutableData data];
    CFStringRef imageUTType = [NSData sd_UTTypeFromSDImageFormat:format];
    
    //创建图片容器
    CGImageDestinationRef imageDestination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)imageData, imageUTType, 1, NULL);
    if (!imageDestination) {
        return nil;
    }
    //创建图片属性
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    NSInteger exifOrientation = [SDWebImageCoderHelper exifOrientationFromImageOrientation:image.imageOrientation];
    [properties setValue:@(exifOrientation) forKey:(__bridge_transfer NSString *)kCGImagePropertyOrientation];
    
    //添加图片到容器中
    CGImageDestinationAddImage(imageDestination, image.CGImage, (__bridge CFDictionaryRef)properties);
    
    // Finalize the destination.
    if (CGImageDestinationFinalize(imageDestination) == NO) {
        // Handle failure.
        imageData = nil;
    }
    CFRelease(imageDestination);
    
    return [imageData copy];
}

#pragma mark - Helper
//动态图、含有透明通道不应该解码
+ (BOOL)shouldDecodeImage:(nullable UIImage *)image {
    // Prevent "CGBitmapContextCreateImage: invalid context 0x0" error
    if (image == nil) {
        return NO;
    }
    
    // do not decode animated images
    if (image.images != nil) {
        return NO;
    }
    
    CGImageRef imageRef = image.CGImage;
    
    BOOL hasAlpha = SDCGImageRefContainsAlpha(imageRef);
    // do not decode images with alpha
    if (hasAlpha) {
        return NO;
    }
    
    return YES;
}
```

#### 图片数据递增解码

```
- (UIImage *)incrementallyDecodedImageWithData:(NSData *)data finished:(BOOL)finished {
    
    if (!_imageSource) {
        _imageSource = CGImageSourceCreateIncremental(NULL);
    }
    UIImage *image;

    //必须传入所有数据，不仅仅是新增的数据，用来判断图片数据是否增量完整
    CGImageSourceUpdateData(_imageSource, (__bridge CFDataRef)data, finished);
    
    //第一次绘制渐进式图片时
    if (_width + _height == 0) {
        //获取图片属性信息，获取宽、高、方向值
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(_imageSource, 0, NULL);
        if (properties) {
            
            NSInteger orientationValue = 1;
            //像素高
            CFTypeRef val = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
            if (val) CFNumberGetValue(val, kCFNumberLongType, &_height);
            //像素宽
            val = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
            if (val) CFNumberGetValue(val, kCFNumberLongType, &_width);
            //图片方向
            val = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
            if (val) CFNumberGetValue(val, kCFNumberNSIntegerType, &orientationValue);
            
            CFRelease(properties);

            //在绘制时丢失了方向信息，这样使用initWithCGIImage创建的有时会方向错误，所有需要临时保存方向值后面用于纠正
            _orientation = [SDWebImageCoderHelper imageOrientationFromEXIFOrientation:orientationValue];
        }
    }
    
    //持续绘制
    if (_width + _height > 0) {
        // 创建位图
        CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(_imageSource, 0, NULL);
        if (partialImageRef) {
            
            //获取当前图片数据显示的高，因为是渐进式显示
            const size_t partialHeight = CGImageGetHeight(partialImageRef);
            
            CGColorSpaceRef colorSpace = SDCGColorSpaceGetDeviceRGB();
            CGContextRef bmContext = CGBitmapContextCreate(NULL, _width, _height, 8, _width * 4, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
            
            if (bmContext) {
                //位图绘制
                CGContextDrawImage(bmContext, (CGRect){.origin.x = 0.0f, .origin.y = 0.0f, .size.width = _width, .size.height = partialHeight}, partialImageRef);
                CGImageRelease(partialImageRef);
                partialImageRef = CGBitmapContextCreateImage(bmContext);
                CGContextRelease(bmContext);
            }
            else {
                CGImageRelease(partialImageRef);
                partialImageRef = nil;
            }
        }
        
        //修正图片方向
        if (partialImageRef) {
            image = [UIImage imageWithCGImage:partialImageRef scale:1 orientation:_orientation];
            CGImageRelease(partialImageRef);
        }
    }
    //增量完成
    if (finished) {
        if (_imageSource) {
            CFRelease(_imageSource);
            _imageSource = NULL;
        }
    }
    
    return image;
}
```

#### 图片解压缩

```
- (UIImage *)decompressedImageWithImage:(UIImage *)image
                                   data:(NSData *__autoreleasing  _Nullable *)data
                                options:(nullable NSDictionary<NSString*, NSObject*>*)optionsDict {
    
    //查看options选择SDWebImageCoderScaleDownLargeImagesKey是否需要ScaleDown
    BOOL shouldScaleDown = NO;
    if (optionsDict != nil) {
        NSNumber *scaleDownLargeImagesOption = nil;
        if ([optionsDict[SDWebImageCoderScaleDownLargeImagesKey] isKindOfClass:[NSNumber class]]) {
            scaleDownLargeImagesOption = (NSNumber *)optionsDict[SDWebImageCoderScaleDownLargeImagesKey];
        }
        if (scaleDownLargeImagesOption != nil) {
            shouldScaleDown = [scaleDownLargeImagesOption boolValue];
        }
    }
    
    if (!shouldScaleDown) {
        //解压缩图片
        return [self sd_decompressedImageWithImage:image];
    } else {
        //解压缩和scaleDown图片
        UIImage *scaledDownImage = [self sd_decompressedAndScaledDownImageWithImage:image];
        
        if (scaledDownImage && !CGSizeEqualToSize(scaledDownImage.size, image.size)) {
            // 图片scale修改，需要替换图片数据data
            SDImageFormat format = [NSData sd_imageFormatForImageData:*data];
            NSData *imageData = [self encodedDataWithImage:scaledDownImage format:format];
            if (imageData) {
                *data = imageData;
            }
        }
        return scaledDownImage;
    }
}
```

#### 图片单独解压缩

```
- (nullable UIImage *)sd_decompressedImageWithImage:(nullable UIImage *)image {
    if (![[self class] shouldDecodeImage:image]) {
        return image;
    }
    // 调用自动释放池，防止内存暴增
    @autoreleasepool{
        
        //位图环境创建
        CGImageRef imageRef = image.CGImage;
        CGColorSpaceRef colorspaceRef = [[self class] colorSpaceForImageRef:imageRef];
        size_t width = CGImageGetWidth(imageRef);
        size_t height = CGImageGetHeight(imageRef);
        size_t bytesPerRow = kBytesPerPixel * width;
        
        CGContextRef context = CGBitmapContextCreate(NULL,
                                                     width,
                                                     height,
                                                     kBitsPerComponent,
                                                     bytesPerRow,
                                                     colorspaceRef,
                                                     kCGBitmapByteOrderDefault|kCGImageAlphaNoneSkipLast);
        if (context == NULL) {
            return image;
        }
        
        //绘制位图并去掉透明度
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
        CGImageRef imageRefWithoutAlpha = CGBitmapContextCreateImage(context);
        UIImage *imageWithoutAlpha = [UIImage imageWithCGImage:imageRefWithoutAlpha
                                                         scale:image.scale
                                                   orientation:image.imageOrientation];
        
        CGContextRelease(context);
        CGImageRelease(imageRefWithoutAlpha);
        
        return imageWithoutAlpha;
    }
}
```

#### 图片解压缩和scaleDown

```
- (nullable UIImage *)sd_decompressedAndScaledDownImageWithImage:(nullable UIImage *)image {
    
    //不能解码
    if (![[self class] shouldDecodeImage:image]) {
        return image;
    }
    //不能scaleDown
    if (![[self class] shouldScaleDownImage:image]) {
        return [self sd_decompressedImageWithImage:image];
    }
    
    CGContextRef destContext;
    @autoreleasepool {
        CGImageRef sourceImageRef = image.CGImage;
        
        CGSize sourceResolution = CGSizeZero;
        sourceResolution.width = CGImageGetWidth(sourceImageRef);
        sourceResolution.height = CGImageGetHeight(sourceImageRef);
        
        float sourceTotalPixels = sourceResolution.width * sourceResolution.height;
        float imageScale = kDestTotalPixels / sourceTotalPixels;
        CGSize destResolution = CGSizeZero;
        //原始高宽
        destResolution.width = (int)(sourceResolution.width*imageScale);
        destResolution.height = (int)(sourceResolution.height*imageScale);
        
        // 颜色空间
        CGColorSpaceRef colorspaceRef = [[self class] colorSpaceForImageRef:sourceImageRef];
        
        size_t bytesPerRow = kBytesPerPixel * destResolution.width;
        //创建位图上下文
        destContext = CGBitmapContextCreate(NULL,
                                            destResolution.width,
                                            destResolution.height,
                                            kBitsPerComponent,
                                            bytesPerRow,
                                            colorspaceRef,
                                            kCGBitmapByteOrderDefault|kCGImageAlphaNoneSkipLast);
        
        if (destContext == NULL) {
            return image;
        }
        
        //高质量
        CGContextSetInterpolationQuality(destContext, kCGInterpolationHigh);
        
        // Now define the size of the rectangle to be used for the
        // incremental blits from the input image to the output image.
        // we use a source tile width equal to the width of the source
        // image due to the way that iOS retrieves image data from disk.
        // iOS must decode an image from disk in full width 'bands', even
        // if current graphics context is clipped to a subrect within that
        // band. Therefore we fully utilize all of the pixel data that results
        // from a decoding opertion by achnoring our tile size to the full
        // width of the input image.
        
        //原Tile
        CGRect sourceTile = CGRectZero;
        sourceTile.size.width = sourceResolution.width;
        sourceTile.size.height = (int)(kTileTotalPixels / sourceTile.size.width );
        sourceTile.origin.x = 0.0f;
        
        // 输出Tile
        CGRect destTile;
        destTile.size.width = destResolution.width;
        destTile.size.height = sourceTile.size.height * imageScale;
        destTile.origin.x = 0.0f;
        
        // The source seem overlap is proportionate to the destination seem overlap.
        // this is the amount of pixels to overlap each tile as we assemble the ouput image.
        float sourceSeemOverlap = (int)((kDestSeemOverlap/destResolution.height)*sourceResolution.height);
        CGImageRef sourceTileImageRef;
        // calculate the number of read/write operations required to assemble the
        // output image.
        int iterations = (int)( sourceResolution.height / sourceTile.size.height );
        // If tile height doesn't divide the image height evenly, add another iteration
        // to account for the remaining pixels.
        int remainder = (int)sourceResolution.height % (int)sourceTile.size.height;
        if(remainder) {
            iterations++;
        }
        
        // Add seem overlaps to the tiles, but save the original tile height for y coordinate calculations.
        float sourceTileHeightMinusOverlap = sourceTile.size.height;
        sourceTile.size.height += sourceSeemOverlap;
        destTile.size.height += kDestSeemOverlap;
        for( int y = 0; y < iterations; ++y ) {
            @autoreleasepool {
                sourceTile.origin.y = y * sourceTileHeightMinusOverlap + sourceSeemOverlap;
                destTile.origin.y = destResolution.height - (( y + 1 ) * sourceTileHeightMinusOverlap * imageScale + kDestSeemOverlap);
                sourceTileImageRef = CGImageCreateWithImageInRect( sourceImageRef, sourceTile );
                if( y == iterations - 1 && remainder ) {
                    float dify = destTile.size.height;
                    destTile.size.height = CGImageGetHeight( sourceTileImageRef ) * imageScale;
                    dify -= destTile.size.height;
                    destTile.origin.y += dify;
                }
                CGContextDrawImage( destContext, destTile, sourceTileImageRef );
                CGImageRelease( sourceTileImageRef );
            }
        }
        
        //位图图片
        CGImageRef destImageRef = CGBitmapContextCreateImage(destContext);
        CGContextRelease(destContext);
        if (destImageRef == NULL) {
            return image;
        }
        //创建图片
        UIImage *destImage = [UIImage imageWithCGImage:destImageRef scale:image.scale orientation:image.imageOrientation];
        CGImageRelease(destImageRef);
        if (destImage == nil) {
            return image;
        }
        return destImage;
    }
}
```


