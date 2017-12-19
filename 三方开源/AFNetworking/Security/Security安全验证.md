### Security安全验证

数字证书：是一个电子文档，其中包含了持有者的信息、公钥以及证明该证书的数字签名
根证书：每个版本的iOS设备中，都会包含一些既有的CA根证书。如果证书是该CA根证书签名的，则为合法证书，否则为非法证书。
证书链: 通常一个CA证书颁发机构会有很多个子机构，用来签发不同用途的子证书，然后这些子证书又再用来签发相应的证书。这要是该证书链上的证书都是正确的。
证书验证：1.验证是不是由信任的CA所签发 2.是不是和本地的信任证书相匹配
双向验证：服务器和客户端都需要向对方发送证书进行认证
SSL/TSL:   SSL是为了在传输层对网络连接进行加密，TSL是把SSL标准化后修改的名字，是同一个东西的不同阶段。
HTTP/HTTPS: HTTP和HTTPS是两种不同的连接方式，端口也不一样。HTTP的连接简单、无状态。HTTPS在连接时需要进行身份认证，传输的数据会进行加密，更安全。实质是在HTTP和TCP中间加了个SSL。
SSL Pinning (证书绑定): 是指客户端直接保存服务端的证书，建立https连接时直接对比服务端返回的和客户端保存的两个证书是否一样，一样就表明证书是真的，不再去系统的信任证书机构里寻找验证。`(CA机构颁发证书比较昂贵，很多时候会选择自签名证书来进行证书验证。)`

#### AFSecurityPolicy
一个遵守NSSecureCoding、NSCoding协议的对象`AFSecurityPolicy`。

- 用于安全连接上的X.509证书验证和公钥管理。添加了SSL证书验证来防止中间人攻击和其它安全隐患。
- 主要作用就是验证HTTPS请求的证书是否有效。

##### 验证模式

	 enum {
	 AFSSLPinningModeNone,//不验证
	 AFSSLPinningModePublicKey,//只验证主机和服务器证书中的公钥
	 AFSSLPinningModeCertificate,//完整验证主机和服务器的证书
	 }

##### 实现NSCopying协议

	- (instancetype)copyWithZone:(NSZone *)zone {
	    
	    AFSecurityPolicy *securityPolicy = [[[self class] allocWithZone:zone] init];
	    securityPolicy.SSLPinningMode = self.SSLPinningMode;//验证模式
	    securityPolicy.allowInvalidCertificates = self.allowInvalidCertificates;//是否验证证书
	    securityPolicy.validatesDomainName = self.validatesDomainName;//验证domain name
	    securityPolicy.pinnedCertificates = [self.pinnedCertificates copyWithZone:zone];//NSSet<NSData*>本地证书集合
	
	    return securityPolicy;
	}
	
##### 实现NSSecureCoding协议

NSSecureCoding继承NSCoding协议，需要实现下面三个方法

	+ (BOOL)supportsSecureCoding {
    	return YES;
	}
	
	- (instancetype)initWithCoder:(NSCoder *)decoder {
	
	    self = [self init];
	    if (!self) {
	        return nil;
	    }
	
	    self.SSLPinningMode = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(SSLPinningMode))] unsignedIntegerValue];
	    self.allowInvalidCertificates = [decoder decodeBoolForKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
	    self.validatesDomainName = [decoder decodeBoolForKey:NSStringFromSelector(@selector(validatesDomainName))];
	    self.pinnedCertificates = [decoder decodeObjectOfClass:[NSArray class] forKey:NSStringFromSelector(@selector(pinnedCertificates))];
	
	    return self;
	}
	
	- (void)encodeWithCoder:(NSCoder *)coder {
	    [coder encodeObject:[NSNumber numberWithUnsignedInteger:self.SSLPinningMode] forKey:NSStringFromSelector(@selector(SSLPinningMode))];
	    [coder encodeBool:self.allowInvalidCertificates forKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
	    [coder encodeBool:self.validatesDomainName forKey:NSStringFromSelector(@selector(validatesDomainName))];
	    [coder encodeObject:self.pinnedCertificates forKey:NSStringFromSelector(@selector(pinnedCertificates))];
	}
	
##### keyPath绑定
	#pragma mark - NSKeyValueObserving
	// PinnedPublicKeys 关联于 pinnedCertificates 的改变，
	// 貌似没啥用，在pinnedCertificates的set方法中已经存在更新pinnedPublicKeys的操作
	+ (NSSet *)keyPathsForValuesAffectingPinnedPublicKeys {
	    return [NSSet setWithObject:@"pinnedCertificates"];
	}

##### 获取本地证书
	
	//如果采用的AFNetworking是以framework的形式引入，证书需要从bundle中获取
	+ (NSSet *)certificatesInBundle:(NSBundle *)bundle {
	    NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];
	
	    NSMutableSet *certificates = [NSMutableSet setWithCapacity:[paths count]];
	    for (NSString *path in paths) {
	        NSData *certificateData = [NSData dataWithContentsOfFile:path];
	        [certificates addObject:certificateData];
	    }
	
	    return [NSSet setWithSet:certificates];
	}

	//采用dispatch_once，实现本地证书的懒加载，只会查询一次
	+ (NSSet *)defaultPinnedCertificates {
	    static NSSet *_defaultPinnedCertificates = nil;
	    static dispatch_once_t onceToken;
	    dispatch_once(&onceToken, ^{
	        NSBundle *bundle = [NSBundle bundleForClass:[self class]];//返回该类文件所在的bundle
	        _defaultPinnedCertificates = [self certificatesInBundle:bundle];
	    });
	
	    return _defaultPinnedCertificates;
	}

##### 设置本地证书

设置本地证书时，同时也提取所有证书的publicKey到self.pinnedPublicKeys中

    - (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
        _pinnedCertificates = pinnedCertificates;

        if (_pinnedCertificates) {

            NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:_pinnedCertificates.count];
            for (NSData *certificate in _pinnedCertificates) {
                id publickKey = AFPublicKeyForCertificate(certificate);
                if (publickKey) {
                    [mutablePinnedPublicKeys addObject:publickKey];
                }
            }

            self.pinnedPublicKeys = [mutablePinnedPublicKeys copy];
        }else{
            self.pinnedPublicKeys = nil;
        }
    }
##### 对 serverTrust 的操作

操作函数采用全局C的API，都是定义在Security框架。

- 多处使用了__Require_noErr_Quiet函数，作用是当前面的执行结果出错则直接goto到exceptionLabel后面的执行语句

```
#ifndef __Require_noErr_Quiet
#define __Require_noErr_Quiet(errorCode, exceptionLabel)                      \
  do                                                                          \
  {                                                                           \
	  if ( __builtin_expect(0 != (errorCode), 0) )                            \
	  {                                                                       \
		  goto exceptionLabel;                                                \
	  }                                                                       \
  } while ( 0 )
#endif
```

- 获取证书中的公钥 publicKey
    `static id AFPublicKeyForCertificate(NSData *certificate)`

- 服务器信任是否有效
    `static BOOL AFServerTrustIsValid(SecTrustRef serverTrust)`
    
- 获取服务器信托的证书信任链
    `static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust)`

- 获取服务器信托的公钥信任链
    `static NSArray * AFPublicKeyTrustChainForServerTrust(SecTrustRef serverTrust)`

##### 验证服务器证书(重点)

	- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
	                  forDomain:(NSString *)domain
	{
	    //1.验证自我签名的证书域名信息，必须用pinning的方式。不允许隐式信任自己签发的证书
	    if (domain
	        && self.allowInvalidCertificates
	        && self.validatesDomainName
	        && (self.SSLPinningMode == AFSSLPinningModeNone
	            || [self.pinnedCertificates count] == 0)) {
	        NSLog(@"In order to validate a domain name for self signed certificates, you MUST use pinning.");
	        return NO;
	    }
	
	    //2.设置安全策略
          //需要验证域名，则使用domain创建一个SecPolicyRef，否者创建一个符合X509标准的默认SecPolicyRef对象。
	    NSMutableArray *policies = [NSMutableArray array];
	    if (self.validatesDomainName) {
	        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
	    } else {
	        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
	    }
	    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
	
	    3.验证证书是否有效
	    if (self.SSLPinningMode == AFSSLPinningModeNone) {//只根据证书信任列表来进行验证
	        //准许无效的证书或者证书有效，则验证通过
	        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
	    } else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
	        //证书无效
	        return NO;
	    }
	
          4.根据 SSLPinningMode 对服务器进行验证
	    switch (self.SSLPinningMode) {
	        case AFSSLPinningModeNone:
	        default:
	            return NO;
	        case AFSSLPinningModeCertificate: {//证书验证
            
	            //从self.pinnedCertificates中获取证书
	            NSMutableArray *pinnedCertificates = [NSMutableArray array];
	            for (NSData *certificateData in self.pinnedCertificates) {
	                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
	            }
	            
	            //告诉serverTrust只信任pinnedCertificates中的证书 ？？？
	            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
	            if (!AFServerTrustIsValid(serverTrust)) {
	                return NO;
	            }
                
                  //获取服务器信托中的证书集合进行验证
	            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
	            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
	                
	                //本地证书数据集包含 该证书链中的证书
	                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
	                    return YES;
	                }
	            }
	            
	            return NO;
	        }
	        case AFSSLPinningModePublicKey: {//证书公钥验证
	            
	            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
	
	            for (id trustChainPublicKey in publicKeys) {
	                for (id pinnedPublicKey in self.pinnedPublicKeys) {
	                    
	                    //服务器证书和本地证书中的公钥匹配
	                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
	                        return YES;
	                    }
	                    
	                }
	            }
	        }
	    }
	    
	    return NO;
	}

