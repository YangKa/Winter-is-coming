
## 近场通信（蓝牙开发、WIFI开发）

### 1 AirDrop (UIActivityViewController类)

功能：实现iOS设备间的文件和数据分享。AirDrop使用蓝牙来扫描周围的设备，当两台设备通过蓝牙建立起了连接，考虑到更快速的数据传输，它就会创建点对点的WiFi网络来连接两部iOS 设备。但并不意味着为了使用AirDrop而需要把设备连接至WiFi网络。

传输方式：蓝牙、WiFi

支持系统：iOS

http://www.cocoachina.com/industry/20131105/7295.html

### 2 GameKit 框架

功能：GameKit主要是完成iOS设备间联网的相关功能，包括蓝牙和Internet两种方式。

传输方式：蓝牙、WiFi

支持系统：iOS

http://www.cocoachina.com/bbs/read.php?tid=97953

### 3 MultipeerConnectivity 框架

功能：利用Multipeer Connectivity框架，即使在没有连接到WiFi（WLAN）或移动网络（xG）的情况下，距离较近的Apple设备（iMac/iPad/iPhone）之间可基于蓝牙和WiFi（P2P WiFi）技术进行发现和连接实现近场通信。

传输方式：蓝牙、WiFi

支持系统：iOS

http://blog.csdn.net/phunxm/article/details/43450167

### 4 ExternalAccessory 框架

功能：External Accessory Framework提供了配件连接iOS设备的通道。开发者可以通过它来开发连接配件的app。配件可以通过30pin、蓝牙、USB的方式连接iOS设备。

传输方式：蓝牙、WiFi

支持系统：iOS

http://www.cnblogs.com/evangwt/archive/2013/04/04/2999661.html

### 5 CoreBluetooth 框架

功能：蓝牙4.0协议之间信息传输，支持iOS和Android设备。

传输方式：蓝牙

支持系统：iOS、Android

http://blog.csdn.net/pony_maggie/article/details/26740237

### 6 Socket

功能：通过TCP或UDP进行相同局域网内信息传输，支持iOS和Android设备。

传输方式：WiFi

支持系统：iOS、Android

http://blog.csdn.net/kesalin/article/details/8798039

### 7 Bonjour

功能：Bonjour是一种能够自动查询接入网络中的设备或应用程序的协议。Bonjour 抽象掉 ip 和 port 的概念，让我们聚焦于更容易为人类思维理解的 service。通过 Bonjour，一个应用程序 publish 一个网络服务 service，然后网络中的其他程序就能自动发现这个 service，从而可以向这个 service 查询其 ip 和 port，然后通过获得的 ip 和 port 建立 socket 链接进行通信，支持iOS和Android设备。

传输方式：WiFi

支持系统：iOS、Android

http://www.cnblogs.com/kesalin/archive/2011/09/15/cocoa_bonjour.html

### 8 AllJoyn

功能:AllJoyn，由高通公司主导的高创新中心的开源项目开发的，主要用于近距离无线传输，通过WiFi或蓝牙技术，定位和点对点文件传输。支持平台：RTOS、Arduino、Linux、Android、iOS、Windows、Mac。

传输方式：蓝牙、WiFi

支持系统：RTOS、Arduino、Linux、Android、iOS、Windows、Mac

https://allseenalliance.org/framework/documentation/develop/tutorial/ios