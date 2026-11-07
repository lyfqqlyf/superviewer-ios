import UIKit

/// 远程控制主界面（手势与向日葵 controlclient 一致）
final class RemoteViewController: UIViewController, CanvasDelegate, UITextFieldDelegate {

    private let serverBase: URL
    private let deviceName: String
    private var ws = WSClient()
    private var canvas = ScreenCanvasView()
    private var toolbar = UIScrollView()
    private var toolbarBtns: [UIButton] = []
    private var statusLabel = UILabel()
    private var hiddenField = UITextField()
    private var keyboardBar: KeyboardBar!

    private var pointer = CGPoint(x: 640, y: 400)   // 虚拟指针（画面坐标）
    private var pointerInit = false
    private var streamSize: CGSize = .zero
    private var monitors = 1
    private var monitorIndex = 1
    private var lastMoveSent = Date.distantPast
    private var frameCount = 0
    private var fpsTimer: Timer?
    private var reconnectTimer: Timer?
    private var sensitivity: CGFloat = 1.0

    init(serverBase: URL, deviceName: String) {
        self.serverBase = serverBase
        self.deviceName = deviceName
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        UIApplication.shared.isIdleTimerDisabled = true   // 远控时保持常亮
        navigationItem.hidesBackButton = true
        title = deviceName

        canvas.delegate = self
        canvas.backgroundColor = .black
        view.addSubview(canvas)

        buildToolbar()
        buildStatus()

        keyboardBar = KeyboardBar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 54),
                                  inputViewStyle: .keyboard)
        keyboardBar.onText = { [weak self] t in self?.send(["t": "key", "text": t]) }
        keyboardBar.onKey = { [weak self] code in
            self?.send(["t": "key", "k": code, "a": "down"])
            self?.send(["t": "key", "k": code, "a": "up"])
        }
        keyboardBar.onCombo = { [weak self] keys in self?.send(["t": "combo", "keys": keys]) }
        keyboardBar.onClose = { [weak self] in self?.hiddenField.resignFirstResponder() }

        hiddenField.delegate = self
        hiddenField.autocorrectionType = .no
        hiddenField.autocapitalizationType = .none
        hiddenField.inputAccessoryView = keyboardBar
        hiddenField.textColor = .clear
        hiddenField.backgroundColor = .clear
        hiddenField.alpha = 0.02        // 不可见但保持可响应（键盘捕获）
        hiddenField.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        view.addSubview(hiddenField)

        connect()
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.statusLabel.text = "  \(self.deviceName) · \(self.frameCount)fps "
            self.frameCount = 0
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let barH: CGFloat = 46
        toolbar.frame = CGRect(x: 0, y: view.bounds.height - safe.bottom - barH,
                               width: view.bounds.width, height: barH + safe.bottom)
        canvas.frame = CGRect(x: 0, y: 0, width: view.bounds.width,
                              height: view.bounds.height - barH - safe.bottom)
    }

    deinit {
        UIApplication.shared.isIdleTimerDisabled = false
        ws.close()
        fpsTimer?.invalidate()
        reconnectTimer?.invalidate()
    }

    // MARK: - 工具栏（对齐向日葵远控工具条）
    private func buildToolbar() {
        toolbar.backgroundColor = .svPanel
        toolbar.showsHorizontalScrollIndicator = false
        view.addSubview(toolbar)
        var x: CGFloat = 6
        let h: CGFloat = 36
        func add(_ title: String, action: @escaping () -> Void) {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(.svText, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.backgroundColor = .svPanel2
            b.svRounded(7)
            b.frame = CGRect(x: x, y: 5, width: max(44, title.size(withAttributes: [.font: b.titleLabel!.font!]).width + 20), height: h)
            x += b.frame.width + 6
            b.addAction(.init(handler: { _ in action() }), for: .touchUpInside)
            toolbar.addSubview(b)
            toolbarBtns.append(b)
        }
        add("⌨ 键盘") { [weak self] in self?.toggleKeyboard() }
        add("🖱 指针模式") { [weak self] in self?.toggleMode() }
        add("🖥 显示器") { [weak self] in self?.pickMonitor() }
        add("🎚 画质") { [weak self] in self?.pickQuality() }
        add("⇅ 剪贴板") { [weak self] in self?.clipboardMenu() }
        add("⌨ 终端") { [weak self] in self?.openTerminal() }
        add("📁 文件") { [weak self] in self?.openFiles() }
        add("⏻ 电源") { [weak self] in self?.powerMenu() }
        add("✕ 断开") { [weak self] in self?.disconnect() }
        toolbar.contentSize = CGSize(width: x + 6, height: 46)
    }

    private func buildStatus() {
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .svGreen
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        statusLabel.svRounded(4)
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        statusLabel.frame = CGRect(x: 8, y: 8, width: 190, height: 22)
        statusLabel.autoresizingMask = [.flexibleRightMargin]
    }

    // MARK: - 连接
    private func connect() {
        guard let wsBase = API.shared.wsBase else { return }
        let url = wsBase.appendingPathComponent("ws/screen")
        ws.onOpen = { [weak self] in
            DispatchQueue.main.async { self?.statusLabel.textColor = .svGreen }
        }
        ws.onText = { [weak self] s in self?.handleText(s) }
        ws.onBinary = { [weak self] data in self?.handleFrame(data) }
        ws.onClose = { [weak self] err in
            DispatchQueue.main.async {
                guard let self = self, self.presentedViewController == nil else { return }
                self.statusLabel.textColor = .svRed
                self.statusLabel.text = "  连接断开，重连中... "
                self.scheduleReconnect()
            }
        }
        ws.connect(to: url)
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.ws.close()
            self?.connect()
        }
    }

    private func send(_ obj: [String: Any]) { ws.send(json: obj) }

    private func handleText(_ s: String) {
        guard let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              d["type"] as? String == "hello" else { return }
        DispatchQueue.main.async {
            if let size = d["size"] as? [CGFloat], size.count == 2 {
                self.streamSize = CGSize(width: size[0], height: size[1])
                self.canvas.streamSize = self.streamSize
                if !self.pointerInit {
                    self.pointer = CGPoint(x: self.streamSize.width / 2, y: self.streamSize.height / 2)
                    self.canvas.pointer = self.pointer
                    self.pointerInit = true
                }
            }
            if let m = d["monitors"] as? Int { self.monitors = max(1, m) }
        }
    }

    private func handleFrame(_ data: Data) {
        frameCount += 1
        guard let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.canvas.image = img }
    }

    // MARK: - 工具栏动作
    private func toggleKeyboard() {
        svHaptic()
        if hiddenField.isFirstResponder {
            hiddenField.resignFirstResponder()
        } else {
            hiddenField.becomeFirstResponder()
        }
    }

    /// 向日葵"鼠标模式/触摸模式"切换
    private func toggleMode() {
        svHaptic()
        canvas.mouseMode.toggle()
        canvas.setNeedsDisplay()
        let name = canvas.mouseMode ? "🖱 指针模式" : "👆 触摸模式"
        toolbarBtns[1].setTitle(name, for: .normal)
        let alert = UIAlertController(title: canvas.mouseMode ? "鼠标模式(触摸板)" : "触摸模式",
            message: canvas.mouseMode
                ? "单指滑动=移动指针\n单指点击=左键\n长按拖动=左键拖动\n双指点按=右键\n双指滑动=滚轮\n双指捏合=缩放"
                : "单指点按=左键(点到哪点到哪)\n长按=右键\n单指按下拖动=左键拖动\n双指点按=右键\n双指滑动=滚轮\n双指捏合=缩放",
            preferredStyle: .alert)
        alert.addAction(.init(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private func pickMonitor() {
        let alert = UIAlertController(title: "显示器", message: nil, preferredStyle: .actionSheet)
        for i in 1...max(1, monitors) {
            alert.addAction(.init(title: "显示器 \(i)", style: .default) { _ in
                self.monitorIndex = i
                self.send(["t": "monitor", "v": i])
            })
        }
        alert.addAction(.init(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func pickQuality() {
        let alert = UIAlertController(title: "画质 / 灵敏度", message: nil, preferredStyle: .actionSheet)
        for (name, v) in [("高清 90", 90), ("标准 70", 70), ("流畅 50", 50), ("省流 30", 30)] {
            alert.addAction(.init(title: name, style: .default) { _ in
                self.send(["t": "quality", "v": v])
            })
        }
        for s in ["0.75", "1.0", "1.5", "2.0"] {
            alert.addAction(.init(title: "指针灵敏度 \(s)", style: .default) { _ in
                self.sensitivity = CGFloat(Double(s) ?? 1)
            })
        }
        alert.addAction(.init(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func clipboardMenu() {
        let alert = UIAlertController(title: "剪贴板同步", message: nil, preferredStyle: .actionSheet)
        alert.addAction(.init(title: "⬆ 发送文本到远程", style: .default) { _ in
            let a = UIAlertController(title: "发送到远程剪贴板", message: nil, preferredStyle: .alert)
            a.addTextField { $0.placeholder = "输入文本" }
            a.addAction(.init(title: "发送", style: .default) { _ in
                let t = a.textFields?.first?.text ?? ""
                API.shared.postJSON("api/clipboard", body: ["text": t]) { _ in }
            })
            a.addAction(.init(title: "取消", style: .cancel))
            self.present(a, animated: true)
        })
        alert.addAction(.init(title: "⬇ 取回远程剪贴板", style: .default) { _ in
            API.shared.getJSON("api/clipboard") { r in
                DispatchQueue.main.async {
                    if case .success(let d) = r, let t = d["text"] as? String {
                        UIPasteboard.general.string = t
                        svHaptic()
                    }
                }
            }
        })
        alert.addAction(.init(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func openTerminal() {
        navigationController?.pushViewController(TerminalViewController(), animated: true)
    }

    private func openFiles() {
        navigationController?.pushViewController(FilesViewController(), animated: true)
    }

    private func powerMenu() {
        let alert = UIAlertController(title: "远程电源", message: nil, preferredStyle: .actionSheet)
        for (name, action) in [("🔒 锁定", "lock"), ("🌙 睡眠", "sleep"), ("🔄 重启", "reboot"), ("⏻ 关机", "shutdown")] {
            alert.addAction(.init(title: name, style: action == "shutdown" ? .destructive : .default) { _ in
                let c = UIAlertController(title: "确认\(name)远程电脑？", message: nil, preferredStyle: .alert)
                c.addAction(.init(title: "确认", style: .destructive) { _ in
                    API.shared.postJSON("api/power", body: ["action": action]) { _ in }
                })
                c.addAction(.init(title: "取消", style: .cancel))
                self.present(c, animated: true)
            })
        }
        alert.addAction(.init(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func disconnect() {
        let alert = UIAlertController(title: "断开远程连接？", message: nil, preferredStyle: .alert)
        alert.addAction(.init(title: "断开", style: .destructive) { _ in
            self.ws.close()
            UIApplication.shared.isIdleTimerDisabled = false
            self.navigationController?.popToRootViewController(animated: true)
        })
        alert.addAction(.init(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - 键盘输入
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        if !string.isEmpty {
            for ch in string { keyboardBar.consume(String(ch)) }
        }
        return false   // 字段永远保持空，仅作输入捕获
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        keyboardBar.onKey?("Enter")
        return false
    }

    // MARK: - CanvasDelegate（手势 → 协议命令）
    private func clampPointer(_ p: CGPoint) -> CGPoint {
        guard streamSize.width > 0 else { return p }
        return CGPoint(x: min(max(p.x, 0), streamSize.width),
                       y: min(max(p.y, 0), streamSize.height))
    }

    private func sendMove(_ p: CGPoint) {
        // 节流 ~30Hz
        let now = Date()
        guard now.timeIntervalSince(lastMoveSent) > 0.03 else { return }
        lastMoveSent = now
        send(["t": "mouse", "x": p.x, "y": p.y])
    }

    private func click(_ btn: String, at p: CGPoint) {
        send(["t": "mouse", "x": p.x, "y": p.y])
        send(["t": "mouse", "x": p.x, "y": p.y, "b": btn, "a": "down"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.send(["t": "mouse", "x": p.x, "y": p.y, "b": btn, "a": "up"])
        }
        canvas.showClickEffect(at: p, right: btn == "right")
    }

    func canvasPointerMove(_ v: ScreenCanvasView, dxView: CGFloat, dyView: CGFloat) {
        let s = v.totalScale()
        var p = pointer
        p.x += dxView / s * sensitivity
        p.y += dyView / s * sensitivity
        pointer = clampPointer(p)
        canvas.pointer = pointer
        sendMove(pointer)
    }

    func canvasLeftClick(_ v: ScreenCanvasView) {
        click("left", at: pointer)
    }

    func canvasDragStart(_ v: ScreenCanvasView) {
        send(["t": "mouse", "x": pointer.x, "y": pointer.y, "b": "left", "a": "down"])
    }

    func canvasDragMove(_ v: ScreenCanvasView, dxView: CGFloat, dyView: CGFloat) {
        canvasPointerMove(v, dxView: dxView, dyView: dyView)
    }

    func canvasDragEnd(_ v: ScreenCanvasView) {
        send(["t": "mouse", "x": pointer.x, "y": pointer.y, "b": "left", "a": "up"])
    }

    func canvasTapAt(_ v: ScreenCanvasView, at: CGPoint) {
        pointer = clampPointer(at)
        canvas.pointer = pointer
        click("left", at: pointer)
    }

    func canvasRightClickAt(_ v: ScreenCanvasView, at: CGPoint?) {
        let p = clampPointer(at ?? pointer)
        pointer = p
        canvas.pointer = pointer
        click("right", at: p)
    }

    func canvasTouchDragStart(_ v: ScreenCanvasView, at: CGPoint) {
        pointer = clampPointer(at)
        canvas.pointer = pointer
        send(["t": "mouse", "x": pointer.x, "y": pointer.y, "b": "left", "a": "down"])
        canvas.showClickEffect(at: pointer, right: false)
    }

    func canvasTouchDragMove(_ v: ScreenCanvasView, at: CGPoint) {
        pointer = clampPointer(at)
        canvas.pointer = pointer
        sendMove(pointer)
    }

    func canvasTouchDragEnd(_ v: ScreenCanvasView) {
        send(["t": "mouse", "x": pointer.x, "y": pointer.y, "b": "left", "a": "up"])
    }

    func canvasTwoFingerTap(_ v: ScreenCanvasView) {
        if canvas.mouseMode {
            click("right", at: pointer)
        } else {
            click("right", at: pointer)   // 触摸模式双指点按: 在指针最后位置右键
        }
    }

    func canvasScroll(_ v: ScreenCanvasView, direction: Int) {
        send(["t": "wheel", "d": direction])
    }
}
