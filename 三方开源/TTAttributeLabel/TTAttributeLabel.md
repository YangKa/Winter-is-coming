## TTAttributeLabel



TTAttributeLabel创建的比较早，那时attributedText还没有出现，所有一开始使用的的是CoreText，后期才支持的attributeString。并且需要翻墙才能在github上访问的到。

### TTAttributeLabel的表现大多数情况都和UILabel表现相同，只有部分不同：

- 1.多功能的text

不建议直接使用attributeText。TTTAttributedLabel协议为Label添加一个id的`text`属性，可以同时接受`NSString`或`NSAttributedString`。

```
@protocol TTTAttributedLabel <NSObject>
@property (nonatomic, copy) IBInspectable id text;
@end
```

- 2.NSTextAttachment

不支持向label中添加附件


### 事件回调代理TTTAttributedLabelDelegate

链接响应分为点击和长按

- 1.点击链接的回调

```
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithURL:(NSURL *)url;
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithAddress:(NSDictionary *)addressComponents;
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithPhoneNumber:(NSString *)phoneNumber;
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithDate:(NSDate *)date;
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithDate:(NSDate *)date timeZone:(NSTimeZone *)timeZone duration:(NSTimeInterval)duration;
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithTransitInformation:(NSDictionary *)components;
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithTextCheckingResult:(NSTextCheckingResult *)result;
```

- 2.长按链接的回调

```
- (void)attributedLabel:(TTTAttributedLabel *)label didLongPressLinkWithURL:(NSURL *)url atPoint:(CGPoint)point;
- (void)attributedLabel:(TTTAttributedLabel *)label didLongPressLinkWithAddress:(NSDictionary *)addressComponents atPoint:(CGPoint)point;
- (void)attributedLabel:(TTTAttributedLabel *)label didLongPressLinkWithPhoneNumber:(NSString *)phoneNumber atPoint:(CGPoint)point;
- (void)attributedLabel:(TTTAttributedLabel *)label didLongPressLinkWithDate:(NSDate *)date atPoint:(CGPoint)point;
- (void)attributedLabel:(TTTAttributedLabel *)label didLongPressLinkWithDate:(NSDate *)date timeZone:(NSTimeZone *)timeZone duration:(NSTimeInterval)duration atPoint:(CGPoint)point;
- (void)attributedLabel:(TTTAttributedLabel *)label didLongPressLinkWithTransitInformation:(NSDictionary *)components atPoint:(CGPoint)point;
```

### 链接对象 TTTAttributedLabelLink

`TTTAttributedLabelLink`代表某一段可响应的链接对象，它持有的`NSTextCheckingResult *result`属性保存链接的`range`和·type·类型。
`TTAttributedLabel`持有一个数值，保存着该text中存在的所有`TTTAttributedLabelLink`对象。

持有不同状态下的属性设置
```
@property (readonly, nonatomic, copy) NSDictionary *attributes;
@property (readonly, nonatomic, copy) NSDictionary *activeAttributes;
@property (readonly, nonatomic, copy) NSDictionary *inactiveAttributes;
```

可响应的block点击和长按回调
```
@property (nonatomic, copy) TTTAttributedLabelLinkBlock linkTapBlock;
@property (nonatomic, copy) TTTAttributedLabelLinkBlock linkLongPressBlock;
```

创建

```
- (instancetype)initWithAttributes:(NSDictionary *)attributes
                  activeAttributes:(NSDictionary *)activeAttributes
                inactiveAttributes:(NSDictionary *)inactiveAttributes
                textCheckingResult:(NSTextCheckingResult *)result;

- (instancetype)initWithAttributesFromLabel:(TTTAttributedLabel*)label
                         textCheckingResult:(NSTextCheckingResult *)result;
```

### 在TTTAttributedLabel添加链接字符串

```
- (void)addLink:(TTTAttributedLabelLink *)link;

- (TTTAttributedLabelLink *)addLinkWithTextCheckingResult:(NSTextCheckingResult *)result;

- (TTTAttributedLabelLink *)addLinkWithTextCheckingResult:(NSTextCheckingResult *)result attributes:(NSDictionary *)attributes;

- (TTTAttributedLabelLink *)addLinkToURL:(NSURL *)url withRange:(NSRange)range;

- (TTTAttributedLabelLink *)addLinkToAddress:(NSDictionary *)addressComponents withRange:(NSRange)range;

- (TTTAttributedLabelLink *)addLinkToPhoneNumber:(NSString *)phoneNumber withRange:(NSRange)range;

- (TTTAttributedLabelLink *)addLinkToDate:(NSDate *)date withRange:(NSRange)range;

- (TTTAttributedLabelLink *)addLinkToDate:(NSDate *)date timeZone:(NSTimeZone *)timeZone duration:(NSTimeInterval)duration withRange:(NSRange)range;

- (TTTAttributedLabelLink *)addLinkToTransitInformation:(NSDictionary *)components withRange:(NSRange)range;
```

添加links对象
```
- (void)addLinks:(NSArray *)links {
    NSMutableArray *mutableLinkModels = [NSMutableArray arrayWithArray:self.linkModels];
    
    //添加links中的属性并渲染
    NSMutableAttributedString *mutableAttributedString = [self.attributedText mutableCopy];
    for (TTTAttributedLabelLink *link in links) {
        if (link.attributes) {
            [mutableAttributedString addAttributes:link.attributes range:link.result.range];
        }
    }
    self.attributedText = mutableAttributedString;
    [self setNeedsDisplay];

    [mutableLinkModels addObjectsFromArray:links];
    self.linkModels = [NSArray arrayWithArray:mutableLinkModels];
}
```

### 思路

- 1.通过protocol添加的id类型text属性可以赋值text或attributedString，然后向TTAttributedLabel添加link对象。
- 2.通过TTTAttributedLabelLink对象中的属性集合渲染字符串中对应部分
- 3.为label添加长按手势和监听点击事件
- 4.检测点击区域是否在link区域，在则获取对应的link对象并调用对应的回调方法，交给代理者去处理
- 5.检测长按手势点击区域是否在link区域，在则获取对应的link对象并调用对应的回调方法，交给代理者去处理
- 6.点击区域检测使用了逐步扩大点击区域查找链接对象，以提供更大的点击区域

### 检测点击区域

#### 检测步骤:

- 1.判断点击位置的字符位置

```
- (CFIndex)characterIndexAtPoint:(CGPoint)p {
    if (!CGRectContainsPoint(self.bounds, p)) {
        return NSNotFound;
    }

    CGRect textRect = [self textRectForBounds:self.bounds limitedToNumberOfLines:self.numberOfLines];
    if (!CGRectContainsPoint(textRect, p)) {
        return NSNotFound;
    }

    // Offset tap coordinates by textRect origin to make them relative to the origin of frame
    p = CGPointMake(p.x - textRect.origin.x, p.y - textRect.origin.y);
    // Convert tap coordinates (start at top left) to CT coordinates (start at bottom left)
    p = CGPointMake(p.x, textRect.size.height - p.y);

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, textRect);
    CTFrameRef frame = CTFramesetterCreateFrame([self framesetter], CFRangeMake(0, (CFIndex)[self.attributedText length]), path, NULL);
    if (frame == NULL) {
        CGPathRelease(path);
        return NSNotFound;
    }

    CFArrayRef lines = CTFrameGetLines(frame);
    NSInteger numberOfLines = self.numberOfLines > 0 ? MIN(self.numberOfLines, CFArrayGetCount(lines)) : CFArrayGetCount(lines);
    if (numberOfLines == 0) {
        CFRelease(frame);
        CGPathRelease(path);
        return NSNotFound;
    }

    CFIndex idx = NSNotFound;

    CGPoint lineOrigins[numberOfLines];
    CTFrameGetLineOrigins(frame, CFRangeMake(0, numberOfLines), lineOrigins);

    for (CFIndex lineIndex = 0; lineIndex < numberOfLines; lineIndex++) {
        CGPoint lineOrigin = lineOrigins[lineIndex];
        CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);

        // Get bounding information of line
        CGFloat ascent = 0.0f, descent = 0.0f, leading = 0.0f;
        CGFloat width = (CGFloat)CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        CGFloat yMin = (CGFloat)floor(lineOrigin.y - descent);
        CGFloat yMax = (CGFloat)ceil(lineOrigin.y + ascent);

        // Apply penOffset using flushFactor for horizontal alignment to set lineOrigin since this is the horizontal offset from drawFramesetter
        CGFloat flushFactor = TTTFlushFactorForTextAlignment(self.textAlignment);
        CGFloat penOffset = (CGFloat)CTLineGetPenOffsetForFlush(line, flushFactor, textRect.size.width);
        lineOrigin.x = penOffset;

        // Check if we've already passed the line
        if (p.y > yMax) {
            break;
        }
        // Check if the point is within this line vertically
        if (p.y >= yMin) {
            // Check if the point is within this line horizontally
            if (p.x >= lineOrigin.x && p.x <= lineOrigin.x + width) {
                // Convert CT coordinates to line-relative coordinates
                CGPoint relativePoint = CGPointMake(p.x - lineOrigin.x, p.y - lineOrigin.y);
                idx = CTLineGetStringIndexForPosition(line, relativePoint);
                break;
            }
        }
    }

    CFRelease(frame);
    CGPathRelease(path);

    return idx;
}
```

- 2.获取点击字符index在哪个link对象range中，有则返回link对象

```
- (TTTAttributedLabelLink *)linkAtCharacterIndex:(CFIndex)idx {
    // Do not enumerate if the index is outside of the bounds of the text.
    if (!NSLocationInRange((NSUInteger)idx, NSMakeRange(0, self.attributedText.length))) {
        return nil;
    }
    
    NSEnumerator *enumerator = [self.linkModels reverseObjectEnumerator];
    TTTAttributedLabelLink *link = nil;
    while ((link = [enumerator nextObject])) {
        if (NSLocationInRange((NSUInteger)idx, link.result.range)) {
            return link;
        }
    }

    return nil;
}
```

- 3.没有找到则逐渐扩辐射区，查找以point为中心的8个方向点是否在某link对象区域内，再则返回

```
- (TTTAttributedLabelLink *)linkAtRadius:(const CGFloat)radius aroundPoint:(CGPoint)point {
    
    const CGFloat diagonal = CGFloat_sqrt(2 * radius * radius);
    const CGPoint deltas[] = {
        CGPointMake(0, -radius), CGPointMake(0, radius), // Above and below
        CGPointMake(-radius, 0), CGPointMake(radius, 0), // Beside
        CGPointMake(-diagonal, -diagonal), CGPointMake(-diagonal, diagonal),
        CGPointMake(diagonal, diagonal), CGPointMake(diagonal, -diagonal) // Diagonal
    };
    const size_t count = sizeof(deltas) / sizeof(CGPoint);
    
    TTTAttributedLabelLink *link = nil;
    //对点击point进行扩展延伸，重新判断获取对应的链接
    for (NSInteger i = 0; i < count && link.result == nil; i ++) {
        CGPoint currentPoint = CGPointMake(point.x + deltas[i].x, point.y + deltas[i].y);
        link = [self linkAtCharacterIndex:[self characterIndexAtPoint:currentPoint]];
    }
    
    return link;
}
```


#### 获取点击位置下的link对象：

``` 
- (TTTAttributedLabelLink *)linkAtPoint:(CGPoint)point {
    
    //点击点不在延伸区内或没有链接对象，则直接返回
    if (!CGRectContainsPoint(CGRectInset(self.bounds, -15.f, -15.f), point) || self.links.count == 0) {
        return nil;
    }
    //查找链接对象
    TTTAttributedLabelLink *result = [self linkAtCharacterIndex:[self characterIndexAtPoint:point]];
    //逐步扩大点击区域查找链接对象
    if (!result && self.extendsLinkTouchArea) {
        result = [self linkAtRadius:2.5f aroundPoint:point]
              ?: [self linkAtRadius:5.f aroundPoint:point]
              ?: [self linkAtRadius:7.5f aroundPoint:point]
              ?: [self linkAtRadius:12.5f aroundPoint:point]
              ?: [self linkAtRadius:15.f aroundPoint:point];
    }
    
    return result;
}
```

#### 屏蔽无效的点击

通过判断点击位置是否在链接区域来判断是否可以响应，这里用于判断长按区域是否有效。该方法会在`- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event`之前调用。

```
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return [self containslinkAtPoint:[touch locationInView:self]];
}
```

#### 长按手势

```
 //获取点击位置
CGPoint touchPoint = [sender locationInView:self];

//获取点击位置对于链接对象
TTTAttributedLabelLink *link = [self linkAtPoint:touchPoint];

if (link) {
    
    //设置了长按回调block，则执行并结束
    if (link.linkLongPressBlock) {
        link.linkLongPressBlock(self, link);
        return;
    }
    //获取连接对象对应的textCheckingResult对象
    NSTextCheckingResult *result = link.result;
    if (!result) {
        return;
    }
    //根据链接类型返回不同的代理方法
    switch (result.resultType) {
        case NSTextCheckingTypeLink:
            if ([self.delegate respondsToSelector:@selector(attributedLabel:didLongPressLinkWithURL:atPoint:)]) {
                [self.delegate attributedLabel:self didLongPressLinkWithURL:result.URL atPoint:touchPoint];
                return;
            }break;
            ...
    }
}
```

#### 点击

```
//点击取消，置空初始选中的link对象
- (void)touchesCancelled:(NSSet *)touches
               withEvent:(UIEvent *)event
{
    if (self.activeLink) {
        self.activeLink = nil;
    } else {
        [super touchesCancelled:touches withEvent:event];
    }
}

//获取初始点击位置的的链接对象
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];

    self.activeLink = [self linkAtPoint:[touch locationInView:self]];

    if (!self.activeLink) {
        [super touchesBegan:touches withEvent:event];
    }
}

//手势移动到另一个链接区域则取消初始链接对象的记录
- (void)touchesMoved:(NSSet *)touches
           withEvent:(UIEvent *)event
{
    if (self.activeLink) {
        UITouch *touch = [touches anyObject];

        if (self.activeLink != [self linkAtPoint:[touch locationInView:self]]) {
            self.activeLink = nil;
        }
    } else {
        [super touchesMoved:touches withEvent:event];
    }
}

//根据链接对象的结果类型进行转发对应的代理
- (void)touchesEnded:(NSSet *)touches
           withEvent:(UIEvent *)event
{
    if (self.activeLink) {
        if (self.activeLink.linkTapBlock) {
            self.activeLink.linkTapBlock(self, self.activeLink);
            self.activeLink = nil;
            return;
        }
        
        NSTextCheckingResult *result = self.activeLink.result;
        self.activeLink = nil;
        //点击回调
        switch (result.resultType) {
            case NSTextCheckingTypeLink:
                if ([self.delegate respondsToSelector:@selector(attributedLabel:didSelectLinkWithURL:)]) {
                    [self.delegate attributedLabel:self didSelectLinkWithURL:result.URL];
                    return;
                }
                break;
            case NSTextCheckingTypeAddress:
                if ([self.delegate respondsToSelector:@selector(attributedLabel:didSelectLinkWithAddress:)]) {
                    [self.delegate attributedLabel:self didSelectLinkWithAddress:result.addressComponents];
                    return;
                }
                break;
            case NSTextCheckingTypePhoneNumber:
                if ([self.delegate respondsToSelector:@selector(attributedLabel:didSelectLinkWithPhoneNumber:)]) {
                    [self.delegate attributedLabel:self didSelectLinkWithPhoneNumber:result.phoneNumber];
                    return;
                }
                break;
            case NSTextCheckingTypeDate:
                if (result.timeZone && [self.delegate respondsToSelector:@selector(attributedLabel:didSelectLinkWithDate:timeZone:duration:)]) {
                    [self.delegate attributedLabel:self didSelectLinkWithDate:result.date timeZone:result.timeZone duration:result.duration];
                    return;
                } else if ([self.delegate respondsToSelector:@selector(attributedLabel:didSelectLinkWithDate:)]) {
                    [self.delegate attributedLabel:self didSelectLinkWithDate:result.date];
                    return;
                }
                break;
            case NSTextCheckingTypeTransitInformation:
                if ([self.delegate respondsToSelector:@selector(attributedLabel:didSelectLinkWithTransitInformation:)]) {
                    [self.delegate attributedLabel:self didSelectLinkWithTransitInformation:result.components];
                    return;
                }
            default:
                break;
        }

        // Fallback to `attributedLabel:didSelectLinkWithTextCheckingResult:` if no other delegate method matched.
        if ([self.delegate respondsToSelector:@selector(attributedLabel:didSelectLinkWithTextCheckingResult:)]) {
            [self.delegate attributedLabel:self didSelectLinkWithTextCheckingResult:result];
        }
    } else {
        [super touchesEnded:touches withEvent:event];
    }
}
```

### 获取字符串range在父容易对应位置

```
- (CGRect)boundingRectForCharacterRange:(NSRange)range {
    NSMutableAttributedString *mutableAttributedString = [self.attributedText mutableCopy];

    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:mutableAttributedString];

    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    [textStorage addLayoutManager:layoutManager];

    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:self.bounds.size];
    [layoutManager addTextContainer:textContainer];

    NSRange glyphRange;
    [layoutManager characterRangeForGlyphRange:range actualGlyphRange:&glyphRange];

    return [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:textContainer];
}
```

### 是否能被复制

```
//是否响应界面上的命令，这里用于检测是否能执行copy命令
- (BOOL)canPerformAction:(SEL)action
              withSender:(__unused id)sender
{
#if !TARGET_OS_TV
    return (action == @selector(copy:));
#else
    return NO;
#endif
}
```

### 重载绘制

重载该方法可以修改Label上text的默认绘制行为，该方法被调用时绘制上下文已经被创建，这时可以选择对context进一步配置然后交由super去渲染。或者直接自己进行渲染，但是不能再调用super进行渲染。

```
- (void)drawTextInRect:(CGRect)rect {
    CGRect insetRect = UIEdgeInsetsInsetRect(rect, self.textInsets);
    if (!self.attributedText) {
        [super drawTextInRect:insetRect];
        return;
    }

    NSAttributedString *originalAttributedText = nil;

    // Adjust the font size to fit width, if necessarry
    if (self.adjustsFontSizeToFitWidth && self.numberOfLines > 0) {
        // Framesetter could still be working with a resized version of the text;
        // need to reset so we start from the original font size.
        // See #393.
        [self setNeedsFramesetter];
        [self setNeedsDisplay];
        
        if ([self respondsToSelector:@selector(invalidateIntrinsicContentSize)]) {
            [self invalidateIntrinsicContentSize];
        }
        
        // Use infinite width to find the max width, which will be compared to availableWidth if needed.
        CGSize maxSize = (self.numberOfLines > 1) ? CGSizeMake(TTTFLOAT_MAX, TTTFLOAT_MAX) : CGSizeZero;

        CGFloat textWidth = [self sizeThatFits:maxSize].width;
        CGFloat availableWidth = self.frame.size.width * self.numberOfLines;
        if (self.numberOfLines > 1 && self.lineBreakMode == TTTLineBreakByWordWrapping) {
            textWidth *= kTTTLineBreakWordWrapTextWidthScalingFactor;
        }

        if (textWidth > availableWidth && textWidth > 0.0f) {
            originalAttributedText = [self.attributedText copy];

            CGFloat scaleFactor = availableWidth / textWidth;
            if ([self respondsToSelector:@selector(minimumScaleFactor)] && self.minimumScaleFactor > scaleFactor) {
                scaleFactor = self.minimumScaleFactor;
            }

            self.attributedText = NSAttributedStringByScalingFontSize(self.attributedText, scaleFactor);
        }
    }

    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    {
        CGContextSetTextMatrix(c, CGAffineTransformIdentity);

        // Inverts the CTM to match iOS coordinates (otherwise text draws upside-down; Mac OS's system is different)
        CGContextTranslateCTM(c, 0.0f, insetRect.size.height);
        CGContextScaleCTM(c, 1.0f, -1.0f);

        CFRange textRange = CFRangeMake(0, (CFIndex)[self.attributedText length]);

        // First, get the text rect (which takes vertical centering into account)
        CGRect textRect = [self textRectForBounds:rect limitedToNumberOfLines:self.numberOfLines];

        // CoreText draws its text aligned to the bottom, so we move the CTM here to take our vertical offsets into account
        CGContextTranslateCTM(c, insetRect.origin.x, insetRect.size.height - textRect.origin.y - textRect.size.height);

        // Second, trace the shadow before the actual text, if we have one
        if (self.shadowColor && !self.highlighted) {
            CGContextSetShadowWithColor(c, self.shadowOffset, self.shadowRadius, [self.shadowColor CGColor]);
        } else if (self.highlightedShadowColor) {
            CGContextSetShadowWithColor(c, self.highlightedShadowOffset, self.highlightedShadowRadius, [self.highlightedShadowColor CGColor]);
        }

        // Finally, draw the text or highlighted text itself (on top of the shadow, if there is one)
        if (self.highlightedTextColor && self.highlighted) {
            NSMutableAttributedString *highlightAttributedString = [self.renderedAttributedText mutableCopy];
            [highlightAttributedString addAttribute:(__bridge NSString *)kCTForegroundColorAttributeName value:(id)[self.highlightedTextColor CGColor] range:NSMakeRange(0, highlightAttributedString.length)];

            if (![self highlightFramesetter]) {
                CTFramesetterRef highlightFramesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)highlightAttributedString);
                [self setHighlightFramesetter:highlightFramesetter];
                CFRelease(highlightFramesetter);
            }

            [self drawFramesetter:[self highlightFramesetter] attributedString:highlightAttributedString textRange:textRange inRect:textRect context:c];
        } else {
            [self drawFramesetter:[self framesetter] attributedString:self.renderedAttributedText textRange:textRange inRect:textRect context:c];
        }

        // If we adjusted the font size, set it back to its original size
        if (originalAttributedText) {
            // Use ivar directly to avoid clearing out framesetter and renderedAttributedText
            _attributedText = originalAttributedText;
        }
    }
    CGContextRestoreGState(c);
}
```

### 文本设置

#### 普通NSString设置

```
- (void)setText:(id)text
afterInheritingLabelAttributesAndConfiguringWithBlock:(NSMutableAttributedString * (^)(NSMutableAttributedString *mutableAttributedString))block
{
    NSMutableAttributedString *mutableAttributedString = nil;
    if ([text isKindOfClass:[NSString class]]) {
        mutableAttributedString = [[NSMutableAttributedString alloc] initWithString:text attributes:NSAttributedStringAttributesFromLabel(self)];
    } else {
        mutableAttributedString = [[NSMutableAttributedString alloc] initWithAttributedString:text];
        [mutableAttributedString addAttributes:NSAttributedStringAttributesFromLabel(self) range:NSMakeRange(0, [mutableAttributedString length])];
    }

    if (block) {
        mutableAttributedString = block(mutableAttributedString);
    }

    [self setText:mutableAttributedString];
}
```

#### attributedText设置

```
- (void)setText:(id)text {
    NSParameterAssert(!text || [text isKindOfClass:[NSAttributedString class]] || [text isKindOfClass:[NSString class]]);

    if ([text isKindOfClass:[NSString class]]) {
        [self setText:text afterInheritingLabelAttributesAndConfiguringWithBlock:nil];
        return;
    }

    self.attributedText = text;
    self.activeLink = nil;

    self.linkModels = [NSArray array];
    if (text && self.attributedText && self.enabledTextCheckingTypes) {
        //异步检测text中的link结果，然后在主线程中进行添加link对象
        __weak __typeof(self)weakSelf = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            __strong __typeof(weakSelf)strongSelf = weakSelf;

            NSDataDetector *dataDetector = strongSelf.dataDetector;//检测器
            if (dataDetector && [dataDetector respondsToSelector:@selector(matchesInString:options:range:)]) {
                NSArray *results = [dataDetector matchesInString:[(NSAttributedString *)text string] options:0 range:NSMakeRange(0, [(NSAttributedString *)text length])];
                if ([results count] > 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([[strongSelf.attributedText string] isEqualToString:[(NSAttributedString *)text string]]) {
                            [strongSelf addLinksWithTextCheckingResults:results attributes:strongSelf.linkAttributes];
                        }
                    });
                }
            }
        });
    }
    //查找链接并添加成link对象
    [self.attributedText enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, self.attributedText.length) options:0 usingBlock:^(id value, __unused NSRange range, __unused BOOL *stop) {
        if (value) {
            NSURL *URL = [value isKindOfClass:[NSString class]] ? [NSURL URLWithString:value] : value;
            [self addLinkToURL:URL withRange:range];
        }
    }];
}
```

