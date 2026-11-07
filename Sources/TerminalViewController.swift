import UIKit

/// 远程终端（对齐向日葵 CMD/SSH 终端体验）
final class TerminalViewController: UIViewController, UITextFieldDelegate {
    private let output = UITextView()
    private let input = UITextField()
    private let shellBtn = UIButton(type: .system)
    private var ws = WSClient()
    private var shell = "powershell"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .svBackground
        title = "远程终端"
        navigationItem.rightBarButtonItem = .init(title: "清屏", style: .plain,
            target: self, action: #selector(clear))

        output.backgroundColor = UIColor(white: 0.04, alpha: 1)
        output.textColor = UIColor(white: 0.82, alpha: 1)
        output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        output.isEditable = false
        output.layer.cornerRadius = 8
        view.addSubview(output)

        shellBtn.setTitle("PowerShell ▾", for: .normal)
        shellBtn.setTitleColor(.svBlue, for: .normal)
        shellBtn.showsMenuAsPrimaryAction = true
        shellBtn.menu = UIMenu(children: [
            UIAction(title: "PowerShell") { _ in self.setShell("powershell") },
            UIAction(title: "CMD") { _ in self.setShell("cmd") },
        ])
        view.addSubview(shellBtn)

        input.backgroundColor = .svPanel2
        input.textColor = .svText
        input.attributedPlaceholder = NSAttributedString(string: "输入命令回车执行",
            attributes: [.foregroundColor: UIColor.svDim])
        input.delegate = self
        input.svRounded(8)
        input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        input.leftViewMode = .always
        view.addSubview(input)

        connect()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        shellBtn.frame = CGRect(x: 12, y: safe.top + 8, width: 120, height: 32)
        input.frame = CGRect(x: 12, y: view.bounds.height - safe.bottom - 44,
                             width: view.bounds.width - 24, height: 36)
        output.frame = CGRect(x: 12, y: shellBtn.frame.maxY + 6,
                              width: view.bounds.width - 24,
                              height: input.frame.minY - shellBtn.frame.maxY - 16)
    }

    deinit { ws.close() }

    private func setShell(_ s: String) {
        shell = s
        shellBtn.setTitle(s == "cmd" ? "CMD ▾" : "PowerShell ▾", for: .normal)
        ws.close()
        connect()
    }

    @objc private func clear() { output.text = "" }

    private func connect() {
        guard let wsBase = API.shared.wsBase else { return }
        var comps = URLComponents(url: wsBase.appendingPathComponent("ws/term"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "shell", value: shell)]
        output.text += "—— 连接 \(shell) ——\n"
        ws.onText = { [weak self] s in
            guard let self = self,
                  let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return }
            DispatchQueue.main.async {
                if d["type"] as? String == "out" {
                    self.output.text += d["data"] as? String ?? ""
                    self.scrollToBottom()
                }
            }
        }
        ws.connect(to: comps.url!)
    }

    private func scrollToBottom() {
        let end = NSRange(location: (output.text as NSString).length, length: 0)
        output.scrollRangeToVisible(end)
        if output.text.count > 200_000 {
            output.text = String(output.text.suffix(100_000))
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let cmd = input.text ?? ""
        input.text = ""
        guard !cmd.isEmpty else { return false }
        output.text += "» \(cmd)\n"
        scrollToBottom()
        send(["t": "in", "data": cmd])
        return false
    }

    private func send(_ obj: [String: Any]) { ws.send(json: obj) }
}
