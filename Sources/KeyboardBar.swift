import UIKit

/// 底部快捷键盘条（对齐向日葵 RDNaviKeyboard / RDComboCommandsKeyboard）
final class KeyboardBar: UIInputView {

    var onText: ((String) -> Void)?
    var onKey: ((String) -> Void)?        // 特殊键 code
    var onCombo: (([String]) -> Void)?    // 组合键
    var onClose: (() -> Void)?

    private var scroll = UIScrollView()
    private var buttons: [UIButton] = []
    private var sticky: Set<String> = []   // 激活的修饰键

    private let modifiers: [(String, String)] = [("Ctrl", "ControlLeft"), ("Alt", "AltLeft"), ("Shift", "ShiftLeft"), ("Win", "MetaLeft")]
    private let special: [(String, String)] = [
        ("Esc", "Escape"), ("Tab", "Tab"), ("⏎", "Enter"), ("⌫", "Backspace"),
        ("←", "ArrowLeft"), ("↑", "ArrowUp"), ("↓", "ArrowDown"), ("→", "ArrowRight"),
        ("Home", "Home"), ("End", "End"), ("PgUp", "PageUp"), ("PgDn", "PageDown"),
        ("Del", "Delete"),
    ]

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = .svPanel2
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        var x: CGFloat = 8
        let h: CGFloat = 38
        @discardableResult
        func addBtn(_ title: String, _ action: @escaping (UIButton) -> Void) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(.svText, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            b.backgroundColor = .svPanel
            b.layer.cornerRadius = 7
            b.layer.borderWidth = 1
            b.layer.borderColor = UIColor.svBorder.cgColor
            b.frame = CGRect(x: x, y: 8, width: max(38, title.size(withAttributes: [.font: b.titleLabel!.font!]).width + 18), height: h)
            x += b.frame.width + 6
            b.addAction(.init(handler: { [weak b] _ in action(b!) }), for: .touchUpInside)
            scroll.addSubview(b)
            buttons.append(b)
            return b
        }

        // 修饰键（粘滞）
        for (label, code) in modifiers {
            addBtn(label) { [weak self] b in
                guard let self = self else { return }
                if self.sticky.contains(code) {
                    self.sticky.remove(code)
                    b.backgroundColor = .svPanel
                    b.layer.borderColor = UIColor.svBorder.cgColor
                } else {
                    self.sticky.insert(code)
                    b.backgroundColor = .svBlue
                }
                svHaptic()
            }
        }
        // 分隔
        addBtn("｜") { _ in }
        // 特殊键
        for (label, code) in special {
            addBtn(label) { [weak self] _ in
                guard let self = self else { return }
                let mods = Array(self.sticky)
                if mods.isEmpty {
                    self.onKey?(code)
                } else {
                    self.onCombo?(mods + [code])
                    self.clearSticky()
                }
            }
        }
        addBtn("｜") { _ in }
        // Ctrl+Alt+Del / 任务管理器
        addBtn("CAD") { [weak self] _ in
            self?.onCombo?(["ControlLeft", "AltLeft", "Delete"])
            self?.clearSticky()
        }
        addBtn("任务管理器") { [weak self] _ in
            self?.onCombo?(["ControlLeft", "ShiftLeft", "Escape"])
            self?.clearSticky()
        }
        // 关闭
        addBtn("完成") { [weak self] _ in self?.onClose?() }
        scroll.contentSize = CGSize(width: x + 8, height: 54)
    }

    private func clearSticky() {
        sticky.removeAll()
        for b in buttons where b.backgroundColor == .svBlue { b.backgroundColor = .svPanel }
    }

    /// 把修饰键与输入文字合成（Ctrl+C → 组合键）
    func consume(_ text: String) {
        guard let ch = text.first else { return }
        if sticky.isEmpty {
            onText?(String(ch))
        } else if let code = Self.charCode(ch) {
            onCombo?(Array(sticky) + [code])
            clearSticky()
        } else {
            onText?(String(ch))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
    }

    static func charCode(_ ch: Character) -> String? {
        let s = String(ch).lowercased()
        if s >= "a" && s <= "z" { return "Key" + s.uppercased() }
        if s >= "0" && s <= "9" { return "Digit" + s }
        if ch == " " { return "Space" }
        return nil
    }
}
