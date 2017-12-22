## SDWebImageFrame

帧图片对象，持有动画图片的某一帧图片和时间。

`@property (nonatomic, strong, readonly, nonnull) UIImage *image;`

`@property (nonatomic, readonly, assign) NSTimeInterval duration;`

`+ (instancetype _Nonnull)frameWithImage:(UIImage * _Nonnull)image `duration:(NSTimeInterval)duration;

## @protocol SDWebImageOperation

```
@protocol SDWebImageOperation <NSObject>

- (void)cancel;

@end
```