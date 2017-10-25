##UIWebView高度自适应

###常规思路
####1.在- (void)webViewDidFinishLoad:(UIWebView *)webView中检测高度，设置webView高度

`问题：`
1.这个方法的调用并不能代表页面渲染完成，高度后期可能还有变化
2.页面的一些操作会重置页面的高度

###思路：
为了适应页面高度的多次变化，实现持续高度动态化。有两个方面可以考虑。
一是从html下手，通过JSContext监听html中可能引起页面高度变化的函数
二是从webView本身下手，监听scrollView的contentSize的高度变化

####2.通过JSContext监听html中页面显示完成后的js方法调用，重置webView高度
	
	```
	1.这个以html为内部人员所写为前提，在所有可能页面渲染结束的js方法里最后调用一个共同方法。例如`func updateDocumentHeigth（）`；

	2.在`webViewDidFinishLoad`方法中建立`JSContext`与`html`的联系。并监听`updateDocumentHeigth`方法。
	JSContext *context = [webView valueForKeyPath:@"documentView.webView.mainFrame.javaScriptContext"];
	context[@"updateDocumentHeigth"] = ^(){
		//update webView frame
	};

	3.updateDocumentHeigth方法被调用时，在block中重置webView的高度，注意在Main Thread中更新。
	```

####3.通过`KVO`，或利用三方库`RAC`监听scrollView的`contentSize`。然后重置webView高度

	
	`RAC：`
	```
    [RACObserve(self.contentWebView.scrollView, contentSize) subscribeNext:^(id x) {
        webView.height = webView.scrollView.contentSize.height;
        webView.scrollView.contentSize = CGSizeMake(0, webView.height);
    }];
    ```

	`KVO：`
	```
	 [_webView.scrollView addObserver:self forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:nil];

	 - (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
	    if ([keyPath isEqualToString:@"contentSize"]) {
	        CGFloat height = [[change valueForKey:NSKeyValueChangeNewKey] CGSizeValue].height;
	        webView.height = height;
	        webView.scrollView.contentSize = CGSizeMake(0, height);
	    }
	}
	```
