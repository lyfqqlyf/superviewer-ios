import UIKit
import UniformTypeIdentifiers   // UTType.item 需要显式导入, 否则编译失败

/// 远程文件管理（列表/下载/上传/删除/新建，对齐向日葵远程文件）
final class FilesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var path = ""                 // 空 = 盘符列表
    private var items: [[String: Any]] = []
    private var drives: [String] = []
    private var parentPath: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .svBackground
        title = "远程文件"
        navigationItem.leftBarButtonItem = .init(
            image: .init(systemName: "chevron.up"), style: .plain,
            target: self, action: #selector(goUp))
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .svBackground
        view.addSubview(table)

        navigationItem.rightBarButtonItems = [
            .init(image: .init(systemName: "plus.folder"), style: .plain,
                  target: self, action: #selector(mkdir)),
            .init(image: .init(systemName: "square.and.arrow.up"), style: .plain,
                  target: self, action: #selector(upload)),
        ]
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.frame = view.bounds
    }

    // MARK: - 数据
    private func load() {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        API.shared.getJSON("api/fs/list?path=\(p)") { [weak self] (r: Result<JSONDict, APIError>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch r {
                case .success(let d):
                    self.drives = d["drives"] as? [String] ?? []
                    self.items = d["items"] as? [[String: Any]] ?? []
                    self.parentPath = d["parent"] as? String
                    if let cur = d["path"] as? String, !cur.isEmpty { self.path = cur }
                    self.title = self.path.isEmpty ? "远程文件" : (self.path as NSString).lastPathComponent
                    self.table.reloadData()
                case .failure(let e):
                    self.alert(e.message)
                }
            }
        }
    }

    private func itemPath(_ idx: Int) -> String {
        let name = items[idx]["name"] as? String ?? ""
        return (path as NSString).appendingPathComponent(name)
    }

    // MARK: - Table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        path.isEmpty ? drives.count : items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // .default 样式的 detailTextLabel 为 nil，用 .subtitle 才能显示文件大小
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        if path.isEmpty {
            cell.textLabel?.text = "💽 \(drives[indexPath.row])"
            cell.detailTextLabel?.text = nil
        } else {
            let it = items[indexPath.row]
            let name = it["name"] as? String ?? ""
            let isDir = it["is_dir"] as? Bool ?? false
            cell.textLabel?.text = (isDir ? "📁 " : "📄 ") + name
            if let size = it["size"] as? Int, !isDir {
                cell.detailTextLabel?.text = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            } else { cell.detailTextLabel?.text = nil }
        }
        cell.textLabel?.textColor = .svText
        cell.detailTextLabel?.textColor = .svDim
        cell.backgroundColor = .svPanel
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if path.isEmpty {
            path = drives[indexPath.row]
            load()
        } else {
            let it = items[indexPath.row]
            if it["is_dir"] as? Bool == true {
                path = itemPath(indexPath.row)
                load()
            } else {
                download(at: itemPath(indexPath.row))
            }
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !path.isEmpty else { return nil }
        let del = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self = self else { return }
            let a = UIAlertController(title: "确定删除？", message: self.itemPath(indexPath.row), preferredStyle: .alert)
            a.addAction(.init(title: "删除", style: .destructive) { _ in
                API.shared.postJSON("api/fs/delete", body: ["path": self.itemPath(indexPath.row)]) { _ in
                    DispatchQueue.main.async { self.load() }
                }
            })
            a.addAction(.init(title: "取消", style: .cancel))
            self.present(a, animated: true)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [del])
    }

    // MARK: - 导航
    @objc private func goUp() {
        guard !path.isEmpty else { return }
        if let p = parentPath, !p.isEmpty {
            path = p
            load()
        } else {
            // 回到盘符列表（本地缓存, 不需要请求）
            path = ""
            items = []
            parentPath = nil
            title = "远程文件"
            table.reloadData()
        }
    }

    // MARK: - 下载/分享
    private func download(at remotePath: String) {
        guard let base = API.shared.base else { return }
        let p = remotePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: base.absoluteString + "/api/fs/download?path=\(p)")!
        alert("开始下载...")
        URLSession.shared.downloadTask(with: url) { [weak self] local, resp, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let local = local, err == nil,
                      (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    self.alert("下载失败"); return
                }
                let name = (remotePath as NSString).lastPathComponent
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: local, to: dest)
                let share = UIActivityViewController(activityItems: [dest], applicationActivities: nil)
                self.present(share, animated: true)
            }
        }.resume()
    }

    // MARK: - 上传
    @objc private func upload() {
        guard !path.isEmpty else { alert("请先进入一个文件夹"); return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func mkdir() {
        guard !path.isEmpty else { alert("请先进入一个文件夹"); return }
        let a = UIAlertController(title: "新建文件夹", message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "名称" }
        a.addAction(.init(title: "创建", style: .default) { _ in
            let n = a.textFields?.first?.text ?? ""
            guard !n.isEmpty else { return }
            let full = (self.path as NSString).appendingPathComponent(n)
            API.shared.postJSON("api/fs/mkdir", body: ["path": full]) { _ in
                DispatchQueue.main.async { self.load() }
            }
        })
        a.addAction(.init(title: "取消", style: .cancel))
        present(a, animated: true)
    }

    private func alert(_ msg: String) {
        let a = UIAlertController(title: msg, message: nil, preferredStyle: .alert)
        a.addAction(.init(title: "好", style: .default))
        present(a, animated: true)
    }
}

extension FilesViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for u in urls {
            API.shared.upload(path: "api/fs/upload", remoteDir: path, fileURL: u) { (r: Result<Bool, APIError>) in
                DispatchQueue.main.async {
                    self.alert((try? r.get()) != nil ? "上传完成" : "上传失败")
                    self.load()
                }
            }
        }
    }
}
