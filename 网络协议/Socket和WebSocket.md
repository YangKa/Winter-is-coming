## Socket和WebSocket

### 区别

- Socket并不是协议，它是方便直接使用传输层协议而存在的一个抽象层。Socket是对TCP/IP协议的封装，是一个调用接口。
- Socket和WebSocket都支持一次连接，双向通信。都是通过心跳机制进行保活。
- 基于WebSocket和Socket都可以开发实时性功能。

### 主要用途

1.社交聊天
2.弹幕
3.多玩家游戏
4.协同编辑
5.股票基金实时报价
6.体育实况更新
7.视频会议/聊天
8.基于位置的应用
9.在线教育
10.智能家居

### 实时性进化史

轮询Polling -> 长轮询Long polling -> Socket -> webSocket

### Socket

三方库：CocoaAsyncSocket

Socket在通讯过程中，服务端监听某个端口是否有连接请求，客户端向服务端发送连接请求，服务端收到连接请求并向客户端发出接收消息，这样一个连接就建立起来了。客户端和服务端也都可以相互发送消息与对方进行通讯，直到双方连接断开。

### WebSocket

三方库：facebook开源的RocketSocket

#### 数据传输

数据以frame形式传递，每条消息会被分割，然后有序传递出去。

好处：
1.大数据的传输可以分片传输，不用考虑数据大小导致的长度标志位不足够的情况。
2.和http的chunk一样，可以边生成数据边传递消息，即提高传输效率。

##### Frame头部

```
0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-------+-+-------------+-------------------------------+
 |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
 |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
 |N|V|V|V|       |S|             |   (if payload len==126/127)   |
 | |1|2|3|       |K|             |                               |
 +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
 |     Extended payload length continued, if payload len == 127  |
 + - - - - - - - - - - - - - - - +-------------------------------+
 |                               |Masking-key, if MASK set to 1  |
 +-------------------------------+-------------------------------+
 | Masking-key (continued)       |          Payload Data         |
 +-------------------------------- - - - - - - - - - - - - - - - +
 :                     Payload Data continued ...                :
 + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
 |                     Payload Data continued ...                |
 +---------------------------------------------------------------+



FIN      1bit 表示信息的最后一帧，flag，也就是标记符
RSV 1-3  1bit each 以后备用的 默认都为 0
Opcode   4bit 帧类型，稍后细说
Mask     1bit 掩码，是否加密数据，默认必须置为1 （这里很蛋疼）
Payload  7bit 数据的长度
Masking-key      1 or 4 bit 掩码
Payload data     (x + y) bytes 数据
Extension data   x bytes  扩展数据
Application data y bytes  程序数据
```

### 其它实时协议

#### WebRTC

WebRTC：`网页实时通讯（Web Real-Time Communication）`，支持跨平台网页端进行`实时语音对话`和`视频对话`的技术，还可以进行`广播文件和消息`。

WebRTC是一个开源项目，旨在使得浏览器能为实时通信（RTC）提供简单的`JavaScript接口`。
说的简单明了一点就是让浏览器提供JS的即时通信接口。这个接口所创立的信道并不是像WebSocket一样，打通一个浏览器与WebSocket服务器之间的通信，而是通过一系列的信令，建立一个浏览器与浏览器之间（peer-to-peer）的信道，这个信道可以发送任何数据，而不需要经过服务器。并且WebRTC通过实现MediaStream，通过浏览器调用设备的摄像头、话筒，使得浏览器之间可以传递音频和视频

WebRTC实现了`三个API`，分别是:

* MediaStream：通过MediaStream的API能够通过设备的摄像头及话筒获得视频、音频的同步流
* RTCPeerConnection：RTCPeerConnection是WebRTC用于构建点对点之间稳定、高效的流传输的组件
* RTCDataChannel：RTCDataChannel使得浏览器之间（点对点）建立一个高吞吐量、低延时的信道，用于传输任意数据