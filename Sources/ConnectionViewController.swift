import UIKit

/// 连接页：地址 + 验证码（会话凭据由 Cookie 管理，验证码不落盘）
final class ConnectionViewController: UIViewController {

    private let logoLabel = UILabel()
    private let subLabel = UILabel()
    private let card = UIView()
    private let addrField = UITextField()
    private let codeField = UITextField()
    private let connectBtn = UIButton(type: .system)
    private let errLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .svBackground
        navigationItem.title = "SuperViewer"
        buildUI()
        addrField.text = UserDefaults.standard.string(forKey: "sv_last_addr") ?? ""
    }

    private func buildUI() {
        logoLabel.text = "SuperViewer"
        logoLabel.font = .systemFont(ofSize: 34, weight: .heavy)
        logoLabel.textColor = .svBlue
        logoLabel.textAlignment = .center
        view.addSubview(logoLabel)

        subLabel.text = "远程桌面 · 文件 · 终端 · 与向日葵同款手势"
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .svDim
        subLabel.textAlignment = .center
        view.addSubview(subLabel)

        card.backgroundColor = .svPanel
        card.svRounded(14)
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.svBorder.cgColor
        view.addSubview(card)

        func style(_ f: UITextField, placeholder: String) {
            f.backgroundColor = .svPanel2
            f.textColor = .svText
            f.attributedPlaceholder = NSAttributedString(string: placeholder,
                attributes: [.foregroundColor: UIColor.svDim])
            f.svRounded(8)
            f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            f.leftViewMode = .always
            card.addSubview(f)
        }
        style(addrField, placeholder: "被控端地址 如 192.168.31.77:9443")
        style(codeField, placeholder: "验证码（被控端托盘查看）")
        codeField.textAlignment = .center
        codeField.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)

        connectBtn.setTitle("连 接", for: .normal)
        connectBtn.setTitleColor(.white, for: .normal)
        connectBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        connectBtn.backgroundColor = .svBlue
        connectBtn.svRounded(8)
        connectBtn.addAction(.init(handler: { [weak self] _ in self?.connect() }), for: .touchUpInside)
        card.addSubview(connectBtn)

        spinner.hidesWhenStopped = true
        card.addSubview(spinner)

        errLabel.textColor = .svRed
        errLabel.font = .systemFont(ofSize: 12)
        errLabel.textAlignment = .center
        errLabel.numberOfLines = 0
        card.addSubview(errLabel)

        let helpBtn = UIButton(type: .system)
        helpBtn.setTitle("连接后如何操作？", for: .normal)
        helpBtn.setTitleColor(.svDim, for: .normal)
        helpBtn.titleLabel?.font = .systemFont(ofSize: 12)
        helpBtn.addAction(.init(handler: { [weak self] _ in self?.showHelp() }), for: .touchUpInside)
        view.addSubview(helpBtn)
        self.helpBtn = helpBtn
    }

    private weak var helpBtn: UIButton?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        logoLabel.frame = CGRect(x: 0, y: safe.top + 60, width: view.bounds.width, height: 44)
        subLabel.frame = CGRect(x: 0, y: logoLabel.frame.maxY + 4, width: view.bounds.width, height: 18)
        let cw = min(360, view.bounds.width - 40)
        card.frame = CGRect(x: (view.bounds.width - cw) / 2, y: subLabel.frame.maxY + 36, width: cw, height: 236)
        addrField.frame = CGRect(x: 20, y: 20, width: cw - 40, height: 44)
        codeField.frame = CGRect(x: 20, y: 74, width: cw - 40, height: 50)
        connectBtn.frame = CGRect(x: 20, y: 134, width: cw - 40, height: 46)
        spinner.center = CGPoint(x: cw / 2, y: 192)
        errLabel.frame = CGRect(x: 20, y: 182, width: cw - 40, height: 40)
        if let helpBtn = helpBtn {
            helpBtn.frame = CGRect(x: 0, y: 0, width: 200, height: 30)
            helpBtn.center = CGPoint(x: view.bounds.width / 2, y: card.frame.maxY + 40)
        }
    }

    private func showHelp() {
        let a = UIAlertController(title: "操作手势（与向日葵一致）",
            message: """
            【触摸模式】
            · 单指点按 = 左键（点到哪点到哪）
            · 单指长按 = 右键
            · 单指按下拖动 = 左键拖动
            · 双指点按 = 右键
            · 双指上下滑动 = 滚轮
            · 双指捏合 = 缩放画面
            【指针模式(触摸板)】
            · 单指滑动 = 移动指针
            · 单指点按 = 左键
            · 长按后拖动 = 左键拖动
            """, preferredStyle: .alert)
        a.addAction(.init(title: "知道了", style: .default))
        present(a, animated: true)
    }

    private func connect() {
        let addr = addrField.text ?? ""
        let code = codeField.text ?? ""
        guard let _ = API.shared.setBase(addr) else {
            errLabel.text = "请输入有效地址"; return
        }
        guard !code.isEmpty else { errLabel.text = "请输入验证码"; return }
        errLabel.text = ""
        connectBtn.isEnabled = false
        spinner.startAnimating()

        API.shared.login(code: code) { [weak self] (result: Result<LoginResp, String>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.connectBtn.isEnabled = true
                self.spinner.stopAnimating()
                switch result {
                case .success(let r):
                    UserDefaults.standard.set(addr, forKey: "sv_last_addr")
                    let name = r.hostname ?? "远程主机"
                    self.navigationController?.pushViewController(
                        RemoteViewController(serverBase: API.shared.base!, deviceName: name),
                        animated: true)
                    self.codeField.text = ""
                    self.errLabel.text = ""
                case .failure(let msg):
                    self.errLabel.text = msg
                }
            }
        }
    }
}
