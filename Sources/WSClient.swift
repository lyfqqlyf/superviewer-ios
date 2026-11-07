import Foundation

/// WebSocket 封装（复用 HTTPCookieStorage.shared 的登录会话）
final class WSClient: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onText: ((String) -> Void)?
    var onBinary: ((Data) -> Void)?
    var onClose: ((String?) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var closedByUser = false
    private var pingTimer: Timer?

    func connect(to url: URL) {
        closedByUser = false
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session?.webSocketTask(with: url)
        task?.resume()
        receive()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.task?.sendPing { _ in }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self = self, self.task != nil else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let s):  self.onText?(s)
                case .data(let d):    self.onBinary?(d)
                @unknown default:     break
                }
                self.receive()
            case .failure(let e):
                if !self.closedByUser { self.onClose?(e.localizedDescription) }
            }
        }
    }

    func send(json obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    func close() {
        closedByUser = true
        pingTimer?.invalidate()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        onOpen?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if !closedByUser { onClose?(nil) }
    }
}
