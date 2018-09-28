## WebSocket

可以把 WebSocket 看成是 HTTP 协议为了支持长连接所打的一个大补丁，它和 HTTP 有一些共性，是为了解决 HTTP 本身无法解决的某些问题而做出的一个改良设计。

#### 原由：
HTTP 协议中所谓的 keep-alive connection 是指在一次 TCP 连接中完成多个 HTTP 请求，但是对每个请求仍然要单独发 header；所谓的 polling 是指从客户端（一般就是浏览器）不断主动的向服务器发 HTTP 请求查询是否有新数据。这两种模式有一个共同的缺点，就是除了真正的数据部分外，服务器和客户端还要大量交换 HTTP header，信息交换效率很低。它们建立的“长连接”都是伪.长连接，只不过好处是不需要对现有的 HTTP server 和浏览器架构做修改就能实现。

#### 改进：
WebSocket 解决的第一个问题是，通过第一个 HTTP request 建立了 TCP 连接之后，之后的交换数据都不需要再发 HTTP request了，使得这个长连接变成了一个真.长连接。但是不需要发送 HTTP header就能交换数据显然和原有的 HTTP 协议是有区别的，所以它需要对服务器和客户端都进行升级才能实现

WebSocket 还是一个双通道的连接，在同一个 TCP 连接上既可以发也可以收信息。此外还有 multiplexing 功能，几个不同的 URI 可以复用同一个 WebSocket 连接。这些都是原来的 HTTP 不能做到的。

#### 补充：
为了防止因为传输线路某个因素受影响，可以使用发送 Ping/Pong Frame（RFC 6455 - The WebSocket Protocol）。这种 Frame 是一种特殊的数据包，它只包含一些元数据而不需要真正的 Data Payload，可以在不影响 Application 的情况下维持住中间网络的连接状态。

### WebSocket握手过程

#### 客户端发起
GET /chat HTTP/1.1
Host: server.example.com
//告诉服务器发起的是websocket协议
Upgrade: websocket
Connection: Upgrade
//客户端随机生成的base64字符串，用于验证服务器身份
Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==
//用户定义的字符串，用来区分同URL下，不同的服务所需要的协议。也即是确定所需服务
Sec-WebSocket-Protocol: chat, superchat
//协议版本
Sec-WebSocket-Version: 13
Origin: http://example.com


#### 服务器返回
HTTP/1.1 101 Switching Protocols
//告诉客户端我切换到这个协议了
Upgrade: websocket
Connection: Upgrade
//经过服务器确认，并且加密过后的 Sec-WebSocket-Key
Sec-WebSocket-Accept: HSmrc0sMlYUkAGmm5OPpG2HaGWk=
Sec-WebSocket-Protocol: chat

#### ping/pong

用来了检测连接两端是否在线，我们使用ping pong的方式实现心跳机制。流程如下：
- Client每隔一段时间执行ping操作
- 往socket的outputStream中写入ping数据
- 服务器读取数据判断是个是ping操作
- 是ping指令则服务器会更新心跳线程的时间，并执行pong操作
- 客户端读取指令判断是pong操作，更新心跳线程的时间

#### 控制帧
WebSocket控制帧有3种：Close(关闭帧)、Ping以及Pong。

Close关闭帧很容易理解，客户端如果接受到了就关闭连接，客户端也可以发送关闭帧给服务端。
****Ping和Pong是websocket里的心跳，用来保证客户端是在线的，一般来说只有服务端给客户端发送Ping，然后客户端发送Pong来回应，表明自己仍然在线。

#### 数据传输结束

通过TCP头部帧中的FIN字段进行判断字节流是否传输结束。