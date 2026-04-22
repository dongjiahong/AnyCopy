import Foundation
import Network
import AppKit
import CommonCrypto

/// 本地 Web 服务器，用于手机/电脑共享剪贴板
class LocalServerService: ObservableObject {
    static let shared = LocalServerService()
    
    @Published var isRunning: Bool = false
    @Published var port: UInt16 = 17582
    @Published var localIPAddress: String = "未知"
    
    private var listener: NWListener?
    private var wsConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.anycopy.server", qos: .userInitiated)
    
    /// 接收到手机发来的文字时的回调
    var onReceiveText: ((String) -> Void)?
    
    private init() {
        localIPAddress = getLocalIPAddress() ?? "未知"
    }
    
    // MARK: - 启动 / 停止
    
    func start() {
        guard !isRunning else { return }
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("[Server] 无法创建监听器: \(error)")
            return
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.localIPAddress = self?.getLocalIPAddress() ?? "未知"
                    print("[Server] 服务已启动 端口:\(self?.port ?? 0)")
                case .failed(let error):
                    print("[Server] 服务失败: \(error)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        
        queue.async { [weak self] in
            guard let self = self else { return }
            for conn in self.wsConnections {
                conn.cancel()
            }
            self.wsConnections.removeAll()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
    
    // MARK: - 推送剪贴板内容到所有 WebSocket 客户端
    
    func broadcast(_ item: ClipboardItem) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let payload: [String: Any]
            switch item.type {
            case .text:
                payload = ["type": "clipboard", "contentType": "text", "content": item.textContent ?? "", "time": item.fullDateTime]
            case .image:
                if let data = item.imageData {
                    let base64 = data.base64EncodedString()
                    payload = ["type": "clipboard", "contentType": "image", "content": base64, "time": item.fullDateTime]
                } else {
                    return
                }
            }
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            
            let frame = self.makeWebSocketFrame(text: jsonString)
            for conn in self.wsConnections {
                conn.send(content: frame, completion: .idempotent)
            }
        }
    }
    
    // MARK: - 连接处理
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        
        // 读取第一个请求来判断是 HTTP 还是 WebSocket 升级
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }
            
            let request = String(data: data, encoding: .utf8) ?? ""
            
            if request.lowercased().contains("upgrade: websocket") {
                self.handleWebSocketUpgrade(connection: connection, request: request)
            } else {
                self.handleHTTPRequest(connection: connection, request: request)
            }
        }
    }
    
    // MARK: - HTTP 请求处理
    
    private func handleHTTPRequest(connection: NWConnection, request: String) {
        let html = self.generateHTML()
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(html)
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // MARK: - WebSocket 握手
    
    private func handleWebSocketUpgrade(connection: NWConnection, request: String) {
        guard let key = extractWebSocketKey(from: request) else {
            connection.cancel()
            return
        }
        
        let acceptKey = computeAcceptKey(key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r\n
        """
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            
            self?.queue.async {
                self?.wsConnections.append(connection)
                self?.readWebSocketFrames(connection: connection)
            }
        })
    }
    
    private func extractWebSocketKey(from request: String) -> String? {
        for line in request.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("sec-websocket-key:") {
                return line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func computeAcceptKey(_ key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magic
        let data = combined.data(using: .utf8)!
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest).base64EncodedString()
    }
    
    // MARK: - WebSocket 帧读取
    
    private func readWebSocketFrames(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[WS] 读取错误: \(error)")
                self.removeConnection(connection)
                return
            }
            
            if isComplete {
                self.removeConnection(connection)
                return
            }
            
            if let data = data, !data.isEmpty {
                self.parseWebSocketFrame(data: data, connection: connection)
            }
            
            // 继续读取
            self.readWebSocketFrames(connection: connection)
        }
    }
    
    private func parseWebSocketFrame(data: Data, connection: NWConnection) {
        guard data.count >= 2 else { return }
        
        let opcode = data[0] & 0x0F
        let isMasked = (data[1] & 0x80) != 0
        var payloadLength = UInt64(data[1] & 0x7F)
        var offset = 2
        
        if payloadLength == 126 {
            guard data.count >= 4 else { return }
            payloadLength = UInt64(data[2]) << 8 | UInt64(data[3])
            offset = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else { return }
            payloadLength = 0
            for i in 0..<8 {
                payloadLength = payloadLength << 8 | UInt64(data[2 + i])
            }
            offset = 10
        }
        
        var maskKey: [UInt8] = []
        if isMasked {
            guard data.count >= offset + 4 else { return }
            maskKey = Array(data[offset..<offset+4])
            offset += 4
        }
        
        guard data.count >= offset + Int(payloadLength) else { return }
        var payload = Array(data[offset..<offset+Int(payloadLength)])
        
        if isMasked {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }
        
        switch opcode {
        case 0x01: // Text frame
            if let text = String(bytes: payload, encoding: .utf8) {
                handleWebSocketMessage(text, connection: connection)
            }
        case 0x08: // Close
            removeConnection(connection)
        case 0x09: // Ping → Pong
            let pong = makeWebSocketPong(payload: Data(payload))
            connection.send(content: pong, completion: .idempotent)
        default:
            break
        }
    }
    
    private func handleWebSocketMessage(_ text: String, connection: NWConnection) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        let msgType = json["type"] as? String ?? ""
        
        if msgType == "send" {
            // 手机发来的文字，写入电脑剪贴板
            if let content = json["content"] as? String, !content.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onReceiveText?(content)
                }
                
                // 广播给所有其他客户端
                let ack: [String: Any] = [
                    "type": "clipboard",
                    "contentType": "text",
                    "content": content,
                    "time": currentTimeString(),
                    "source": "phone"
                ]
                if let ackData = try? JSONSerialization.data(withJSONObject: ack),
                   let ackStr = String(data: ackData, encoding: .utf8) {
                    let frame = makeWebSocketFrame(text: ackStr)
                    for conn in wsConnections {
                        conn.send(content: frame, completion: .idempotent)
                    }
                }
            }
        } else if msgType == "ping" {
            // 心跳
            let pong = "{\"type\":\"pong\"}"
            let frame = makeWebSocketFrame(text: pong)
            connection.send(content: frame, completion: .idempotent)
        }
    }
    
    // MARK: - WebSocket 帧构建
    
    private func makeWebSocketFrame(text: String) -> Data {
        let payload = Array(text.utf8)
        var frame = Data()
        
        frame.append(0x81) // FIN + Text opcode
        
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65536 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            for i in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((payload.count >> i) & 0xFF))
            }
        }
        
        frame.append(contentsOf: payload)
        return frame
    }
    
    private func makeWebSocketPong(payload: Data) -> Data {
        var frame = Data()
        frame.append(0x8A) // FIN + Pong opcode
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        }
        frame.append(payload)
        return frame
    }
    
    // MARK: - 工具方法
    
    private func removeConnection(_ connection: NWConnection) {
        connection.cancel()
        queue.async { [weak self] in
            self?.wsConnections.removeAll { $0 === connection }
        }
    }
    
    private func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
    
    // MARK: - HTML 页面生成
    
    private func generateHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <title>AnyCopy - 共享剪贴板</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; -webkit-tap-highlight-color: transparent; }

        :root {
          --bg: #0f0f17;
          --card: #1a1a2e;
          --card-hover: #222240;
          --border: rgba(255,255,255,0.06);
          --accent: #6c63ff;
          --accent2: #00d2ff;
          --text: #e8e8f0;
          --text2: #8888a0;
          --success: #4caf50;
          --danger: #ff5252;
          --radius: 16px;
        }

        body {
          font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif;
          background: var(--bg);
          color: var(--text);
          min-height: 100vh;
          overflow-x: hidden;
        }

        /* HEADER */
        .header {
          position: sticky; top: 0; z-index: 100;
          backdrop-filter: blur(20px) saturate(180%);
          -webkit-backdrop-filter: blur(20px) saturate(180%);
          background: rgba(15, 15, 23, 0.75);
          border-bottom: 1px solid var(--border);
          padding: 16px 20px;
        }
        .header-inner { max-width: 600px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; }
        .logo { display: flex; align-items: center; gap: 10px; }
        .logo-icon {
          width: 36px; height: 36px; border-radius: 10px;
          background: linear-gradient(135deg, var(--accent), var(--accent2));
          display: flex; align-items: center; justify-content: center;
          font-size: 18px; box-shadow: 0 4px 15px rgba(108,99,255,0.3);
        }
        .logo-text { font-size: 18px; font-weight: 700; letter-spacing: -0.5px; }
        .status-badge {
          display: flex; align-items: center; gap: 6px;
          padding: 5px 12px; border-radius: 20px; font-size: 12px; font-weight: 500;
          background: rgba(76,175,80,0.12); color: var(--success);
        }
        .status-dot {
          width: 7px; height: 7px; border-radius: 50%; background: var(--success);
          animation: pulse 2s infinite;
        }
        @keyframes pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.5; transform: scale(0.8); }
        }

        /* CONTAINER */
        .container { max-width: 600px; margin: 0 auto; padding: 16px 16px 120px; }

        /* SEND AREA */
        .send-area {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 16px;
          margin-bottom: 20px;
          transition: border-color 0.3s;
        }
        .send-area:focus-within {
          border-color: rgba(108,99,255,0.4);
          box-shadow: 0 0 0 3px rgba(108,99,255,0.08);
        }
        .send-label { font-size: 13px; font-weight: 600; color: var(--text2); margin-bottom: 10px; display: flex; align-items: center; gap: 6px; }
        .send-row { display: flex; gap: 10px; }
        .send-input {
          flex: 1; background: rgba(255,255,255,0.04); border: 1px solid var(--border);
          border-radius: 12px; padding: 12px 16px; color: var(--text); font-size: 15px;
          outline: none; transition: all 0.3s; resize: none; min-height: 44px; max-height: 120px;
          font-family: inherit;
        }
        .send-input::placeholder { color: var(--text2); }
        .send-input:focus { border-color: rgba(108,99,255,0.5); background: rgba(255,255,255,0.06); }
        .send-btn {
          background: linear-gradient(135deg, var(--accent), #8b5cf6);
          border: none; border-radius: 12px; padding: 12px 20px;
          color: #fff; font-size: 15px; font-weight: 600; cursor: pointer;
          transition: all 0.2s; white-space: nowrap;
          display: flex; align-items: center; gap: 6px;
          box-shadow: 0 4px 15px rgba(108,99,255,0.25);
        }
        .send-btn:active { transform: scale(0.95); }
        .send-btn:disabled { opacity: 0.5; }

        /* SECTION TITLE */
        .section-title {
          font-size: 13px; font-weight: 600; color: var(--text2);
          margin-bottom: 12px; display: flex; align-items: center; gap: 6px;
        }
        .count-tag {
          background: rgba(108,99,255,0.12); color: var(--accent);
          padding: 2px 8px; border-radius: 10px; font-size: 11px;
        }

        /* CLIPBOARD LIST */
        .clip-list { display: flex; flex-direction: column; gap: 8px; }
        .clip-card {
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: 14px 16px;
          transition: all 0.25s;
          animation: slideIn 0.3s ease;
          cursor: pointer;
          position: relative;
          overflow: hidden;
        }
        .clip-card::before {
          content: '';
          position: absolute; left: 0; top: 0; bottom: 0; width: 3px;
          background: linear-gradient(180deg, var(--accent), var(--accent2));
          opacity: 0; transition: opacity 0.25s;
        }
        .clip-card:active, .clip-card.copied { transform: scale(0.98); }
        .clip-card.copied::before { opacity: 1; }
        @keyframes slideIn {
          from { opacity: 0; transform: translateY(8px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .clip-meta {
          display: flex; align-items: center; justify-content: space-between;
          margin-bottom: 8px;
        }
        .clip-type {
          font-size: 11px; font-weight: 600; padding: 3px 8px;
          border-radius: 6px; text-transform: uppercase; letter-spacing: 0.5px;
        }
        .clip-type.text { background: rgba(108,99,255,0.12); color: var(--accent); }
        .clip-type.image { background: rgba(0,210,255,0.12); color: var(--accent2); }
        .clip-type.phone { background: rgba(76,175,80,0.12); color: var(--success); }
        .clip-time { font-size: 11px; color: var(--text2); }
        .clip-content {
          font-size: 14px; line-height: 1.6; color: var(--text);
          word-break: break-all; white-space: pre-wrap;
          max-height: 120px; overflow: hidden;
          position: relative;
        }
        .clip-content.faded::after {
          content: ''; position: absolute; bottom: 0; left: 0; right: 0; height: 40px;
          background: linear-gradient(transparent, var(--card));
        }
        .clip-img {
          max-width: 100%; max-height: 200px; border-radius: 10px;
          object-fit: contain;
        }
        .clip-actions {
          display: flex; gap: 8px; margin-top: 10px; justify-content: flex-end;
        }
        .copy-btn {
          background: rgba(108,99,255,0.1); border: 1px solid rgba(108,99,255,0.2);
          border-radius: 8px; padding: 6px 14px; color: var(--accent);
          font-size: 12px; font-weight: 600; cursor: pointer; transition: all 0.2s;
          display: flex; align-items: center; gap: 4px;
        }
        .copy-btn:active { transform: scale(0.95); }
        .copy-btn.copied { background: rgba(76,175,80,0.15); border-color: rgba(76,175,80,0.3); color: var(--success); }

        /* TOAST */
        .toast {
          position: fixed; top: 80px; left: 50%; transform: translateX(-50%) translateY(-20px);
          background: rgba(30, 30, 50, 0.95); backdrop-filter: blur(10px);
          border: 1px solid rgba(108,99,255,0.25); border-radius: 12px;
          padding: 10px 20px; font-size: 13px; font-weight: 500; color: var(--text);
          opacity: 0; transition: all 0.3s; pointer-events: none; z-index: 200;
          box-shadow: 0 10px 30px rgba(0,0,0,0.4);
        }
        .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

        /* EMPTY STATE */
        .empty {
          text-align: center; padding: 60px 20px; color: var(--text2);
        }
        .empty-icon { font-size: 48px; margin-bottom: 12px; opacity: 0.3; }
        .empty-text { font-size: 14px; }

        /* DISCONNECTED */
        .disconnected {
          position: fixed; bottom: 0; left: 0; right: 0;
          background: rgba(255,82,82,0.12); border-top: 1px solid rgba(255,82,82,0.3);
          padding: 12px; text-align: center; z-index: 200;
          color: var(--danger); font-size: 13px; font-weight: 500;
          backdrop-filter: blur(10px);
          display: none;
        }
        .disconnected.show { display: block; }
        </style>
        </head>
        <body>
          <div class="header">
            <div class="header-inner">
              <div class="logo">
                <div class="logo-icon">📋</div>
                <div class="logo-text">AnyCopy</div>
              </div>
              <div class="status-badge" id="statusBadge">
                <div class="status-dot"></div>
                <span>已连接</span>
              </div>
            </div>
          </div>

          <div class="container">
            <div class="send-area">
              <div class="send-label">📤 发送到电脑</div>
              <div class="send-row">
                <textarea class="send-input" id="sendInput" placeholder="输入要发送的文字..." rows="1"></textarea>
                <button class="send-btn" id="sendBtn" onclick="sendText()">
                  <span>发送</span>
                  <span>→</span>
                </button>
              </div>
            </div>

            <div class="section-title">
              📥 剪贴板历史
              <span class="count-tag" id="countTag">0</span>
            </div>
            <div class="clip-list" id="clipList">
              <div class="empty">
                <div class="empty-icon">📋</div>
                <div class="empty-text">等待剪贴板内容...</div>
              </div>
            </div>
          </div>

          <div class="toast" id="toast"></div>
          <div class="disconnected" id="disconnected">⚠️ 连接已断开，正在重连...</div>

        <script>
        let ws;
        let clips = [];
        let reconnectTimer;

        function connect() {
          const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
          ws = new WebSocket(proto + '//' + location.host + '/ws');

          ws.onopen = () => {
            document.getElementById('statusBadge').innerHTML = '<div class="status-dot"></div><span>已连接</span>';
            document.getElementById('disconnected').classList.remove('show');
            clearTimeout(reconnectTimer);
          };

          ws.onclose = () => {
            document.getElementById('statusBadge').innerHTML = '<span style="color:var(--danger)">已断开</span>';
            document.getElementById('disconnected').classList.add('show');
            reconnectTimer = setTimeout(connect, 3000);
          };

          ws.onerror = () => { ws.close(); };

          ws.onmessage = (e) => {
            try {
              const msg = JSON.parse(e.data);
              if (msg.type === 'clipboard') {
                addClip(msg);
              }
            } catch(err) {}
          };
        }

        function addClip(msg) {
          clips.unshift(msg);
          if (clips.length > 100) clips = clips.slice(0, 100);
          renderClips();
          showToast(msg.source === 'phone' ? '✅ 已发送到电脑' : '📥 收到新内容');
        }

        function renderClips() {
          const list = document.getElementById('clipList');
          const count = document.getElementById('countTag');
          count.textContent = clips.length;

          if (clips.length === 0) {
            list.innerHTML = '<div class="empty"><div class="empty-icon">📋</div><div class="empty-text">等待剪贴板内容...</div></div>';
            return;
          }

          list.innerHTML = clips.map((c, i) => {
            const typeClass = c.source === 'phone' ? 'phone' : c.contentType;
            const typeLabel = c.source === 'phone' ? '📱 手机' : (c.contentType === 'text' ? '📄 文本' : '🖼️ 图片');
            let contentHtml;
            if (c.contentType === 'image') {
              contentHtml = '<img class="clip-img" src="data:image/png;base64,' + c.content + '">';
            } else {
              const text = escapeHtml(c.content);
              const needFade = text.length > 300;
              contentHtml = '<div class="clip-content' + (needFade ? ' faded' : '') + '">' + text + '</div>';
            }

            return '<div class="clip-card" id="card-' + i + '">' +
              '<div class="clip-meta">' +
                '<span class="clip-type ' + typeClass + '">' + typeLabel + '</span>' +
                '<span class="clip-time">' + (c.time || '') + '</span>' +
              '</div>' +
              contentHtml +
              '<div class="clip-actions">' +
                '<button class="copy-btn" id="cbtn-' + i + '" onclick="copyClip(' + i + ')">' +
                  '<span>复制</span>' +
                '</button>' +
              '</div>' +
            '</div>';
          }).join('');
        }

        function copyClip(idx) {
          const c = clips[idx];
          if (!c) return;

          if (c.contentType === 'image') {
            // 将 base64 图片转为 blob 写入剪贴板
            fetch('data:image/png;base64,' + c.content)
              .then(r => r.blob())
              .then(blob => {
                const item = new ClipboardItem({ 'image/png': blob });
                navigator.clipboard.write([item]).then(() => {
                  markCopied(idx);
                }).catch(() => { showToast('❌ 复制失败'); });
              });
          } else {
            navigator.clipboard.writeText(c.content).then(() => {
              markCopied(idx);
            }).catch(() => {
              // fallback
              const ta = document.createElement('textarea');
              ta.value = c.content;
              document.body.appendChild(ta);
              ta.select();
              document.execCommand('copy');
              document.body.removeChild(ta);
              markCopied(idx);
            });
          }
        }

        function markCopied(idx) {
          const btn = document.getElementById('cbtn-' + idx);
          const card = document.getElementById('card-' + idx);
          if (btn) { btn.classList.add('copied'); btn.innerHTML = '<span>✓ 已复制</span>'; }
          if (card) card.classList.add('copied');
          showToast('✅ 已复制到剪贴板');
          setTimeout(() => {
            if (btn) { btn.classList.remove('copied'); btn.innerHTML = '<span>复制</span>'; }
            if (card) card.classList.remove('copied');
          }, 2000);
        }

        function sendText() {
          const input = document.getElementById('sendInput');
          const text = input.value.trim();
          if (!text || !ws || ws.readyState !== WebSocket.OPEN) return;

          ws.send(JSON.stringify({ type: 'send', content: text }));
          input.value = '';
          input.style.height = 'auto';
        }

        function showToast(msg) {
          const t = document.getElementById('toast');
          t.textContent = msg;
          t.classList.add('show');
          setTimeout(() => t.classList.remove('show'), 2000);
        }

        function escapeHtml(str) {
          const d = document.createElement('div');
          d.textContent = str;
          return d.innerHTML;
        }

        // Enter to send
        document.getElementById('sendInput').addEventListener('keydown', (e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendText();
          }
        });

        // Auto-resize textarea
        document.getElementById('sendInput').addEventListener('input', function() {
          this.style.height = 'auto';
          this.style.height = Math.min(this.scrollHeight, 120) + 'px';
        });

        // Heartbeat
        setInterval(() => {
          if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'ping' }));
          }
        }, 30000);

        connect();
        </script>
        </body>
        </html>
        """
    }
}
