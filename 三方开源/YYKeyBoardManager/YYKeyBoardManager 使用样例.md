## YYKeyBoardManager 使用样例


```

// Get keyboard manager
YYKeyboardManager *manager = [YYKeyboardManager defaultManager];
	
// Get keyboard view and window
UIView *view = manager.keyboardView;
UIWindow *window = manager.keyboardWindow;
	
// Get keyboard status
BOOL visible = manager.keyboardVisible;
CGRect frame = manager.keyboardFrame;
frame = [manager convertRect:frame toView:self.view];
	
// Track keyboard animation
[manager addObserver:self];
- (void)keyboardChangedWithTransition:(YYKeyboardTransition)transition {
    CGRect fromFrame = [manager convertRect:transition.fromFrame toView:self.view];
    CGRect toFrame =  [manager convertRect:transition.toFrame toView:self.view];
    BOOL fromVisible = transition.fromVisible;
    BOOL toVisible = transition.toVisible;
    NSTimeInterval animationDuration = transition.animationDuration;
    UIViewAnimationCurve curve = transition.animationCurve;
}
```