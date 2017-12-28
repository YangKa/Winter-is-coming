## YYImageCoder

编码器包含一个解码器YYImageDecoder类、一个编码器YYImageEncoder类、一个图片帧对象。

#### 图片格式

```
typedef NS_ENUM(NSUInteger, YYImageType) {
    YYImageTypeUnknown = 0, ///< unknown
    YYImageTypeJPEG,        ///< jpeg, jpg
    YYImageTypeJPEG2000,    ///< jp2
    YYImageTypeTIFF,        ///< tiff, tif
    YYImageTypeBMP,         ///< bmp
    YYImageTypeICO,         ///< ico
    YYImageTypeICNS,        ///< icns
    YYImageTypeGIF,         ///< gif
    YYImageTypePNG,         ///< png
    YYImageTypeWebP,        ///< webp
    YYImageTypeOther,       ///< other image format
};
```

#### 帧图片处理方式

在渲染下一帧图片时，当前加载帧的处理方式

```
typedef NS_ENUM(NSUInteger, YYImageDisposeMethod) {
    //不做处理
    YYImageDisposeNone = 0,
    
    //当加载下一帧时，画布帧区域将会被清空成透明的黑色区域
    YYImageDisposeBackground,
    
    //在渲染下一帧时，当前画布会显示上一帧的内容
    YYImageDisposePrevious,
};
```

#### 多帧渲染混合模式

当前帧和上一帧图片透明像素混合模式

```
typedef NS_ENUM(NSUInteger, YYImageBlendOperation) {
    YYImageBlendNone = 0,//不混合，直接覆盖
    YYImageBlendOver,//混合显示
};
```

### YYImageFrame : NSObject <NSCopying>

单帧图片对象，持有帧图片的详细信息。遵守NSCopying协议，

```
@interface YYImageFrame : NSObject <NSCopying>
@property (nonatomic) NSUInteger index;    ///< Frame index (zero based)
@property (nonatomic) NSUInteger width;    ///< Frame width
@property (nonatomic) NSUInteger height;   ///< Frame height
@property (nonatomic) NSUInteger offsetX;  ///< Frame origin.x in canvas (left-bottom based)
@property (nonatomic) NSUInteger offsetY;  ///< Frame origin.y in canvas (left-bottom based)
@property (nonatomic) NSTimeInterval duration;          ///< Frame duration in seconds
@property (nonatomic) YYImageDisposeMethod dispose;     ///< Frame dispose method.
@property (nonatomic) YYImageBlendOperation blend;      ///< Frame blend operation.
@property (nullable, nonatomic, strong) UIImage *image; ///< The image.
+ (instancetype)frameWithImage:(UIImage *)image;
@end
```

### _YYImageDecoderFrame : YYImageFrame

继承YYImageFrame，新增是否透明、是否显示全铺、混合渲染的上一帧指数。

```
@interface _YYImageDecoderFrame : YYImageFrame
@property (nonatomic, assign) BOOL hasAlpha;                ///< Whether frame has alpha.
@property (nonatomic, assign) BOOL isFullSize;              ///< Whether frame fill the canvas.
@property (nonatomic, assign) NSUInteger blendFromIndex;    ///< Blend from frame index to current frame.
@end
```

### YYImageDecoder

- 对图片数据进行解码。
- 使用自旋锁和信号量保证图片数据访问的线程安全。


### YYImageEncoder

- 对图片数据进行编码。
- 编码器持有一个图片数据集合，内容包括UIImage或者data、url。
- 使用@autoreleasepool自动释放池尽快释放图片占用内存。



#### 属性

```
@property (nonatomic, readonly) YYImageType type; ///< Image type.
@property (nonatomic) NSUInteger loopCount;       ///< Loop count, 0 means infinit, only available for GIF/APNG/WebP.
@property (nonatomic) BOOL lossless;              ///< Lossless, only available for WebP.
@property (nonatomic) CGFloat quality;            ///< Compress quality, 0.0~1.0, only available for JPG/JP2/WebP.

```

### UIImage (YYImageCoder)


