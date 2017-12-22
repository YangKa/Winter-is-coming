## SDWebImageCoder

### 协议SDWebImageCoder

提供一个是否在解压期间scaleDown大图片的key，在调用解压缩时设置使用
`FOUNDATION_EXPORT NSString * _Nonnull const SDWebImageCoderScaleDownLargeImagesKey;`

编解码图片

```
@protocol SDWebImageCoder <NSObject>

@required

//解码
- (BOOL)canDecodeFromData:(nullable NSData *)data;
- 
- (nullable UIImage *)decodedImageWithData:(nullable NSData *)data;
- 
- (nullable UIImage *)decompressedImageWithImage:(nullable UIImage *)image
                                            data:(NSData * _Nullable * _Nonnull)data
                                         options:(nullable NSDictionary<NSString*, NSObject*>*)optionsDict;

//编码                                         
- (BOOL)canEncodeToFormat:(SDImageFormat)format;
- (nullable NSData *)encodedDataWithImage:(nullable UIImage *)image format:(SDImageFormat)format;
```

### 协议SDWebImageProgressiveCoder

递增解码

```
@protocol SDWebImageProgressiveCoder <SDWebImageCoder>

@required

- (BOOL)canIncrementallyDecodeFromData:(nullable NSData *)data;

- (nullable UIImage *)incrementallyDecodedImageWithData:(nullable NSData *)data finished:(BOOL)finished;

@end
```


#### 获取设备RGB

```
CGColorSpaceRef SDCGColorSpaceGetDeviceRGB(void) {
    static CGColorSpaceRef colorSpace;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateDeviceRGB();
    });
    return colorSpace;
}
```

#### 图片是否含有透明元素

```
BOOL SDCGImageRefContainsAlpha(CGImageRef imageRef) {
    if (!imageRef) {
        return NO;
    }
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageRef);
    BOOL hasAlpha = !(alphaInfo == kCGImageAlphaNone ||
                      alphaInfo == kCGImageAlphaNoneSkipFirst ||
                      alphaInfo == kCGImageAlphaNoneSkipLast);
    return hasAlpha;
}
```