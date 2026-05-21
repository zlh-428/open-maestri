import AppKit
import QuickLookUI
import UniformTypeIdentifiers

// MARK: - FileTreeIconGridView

/// Icon Grid 视图（NSCollectionView 实现，对标 Maestri Grid 模式）
/// - 每列固定展示缩略图网格（图片/PDF/视频显示 Quick Look 预览图标）
/// - 双击文件夹：通过 onNavigateTo 导航进入
/// - 双击文件：Quick Look 预览
final class FileTreeIconGridView: NSView {

    // MARK: - Public API

    var rootPath: String { store.rootPath }

    var onNavigateTo: ((String) -> Void)?

    // MARK: - Private

    private var store: FileTreeStateStore
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private var selectedIndexPaths: Set<IndexPath> = []

    // MARK: - Init

    init(rootPath: String) {
        self.store = FileTreeStateStore(rootPath: rootPath)
        super.init(frame: .zero)
        setupViews()
        Task { @MainActor [weak self] in
            await self?.store.reload()
            self?.collectionView.reloadData()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupViews() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 72, height: 80)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            FileGridItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("FileGridItem")
        )

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        // 双击
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClick)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    // MARK: - Navigation

    func changeRoot(to newPath: String) {
        store = FileTreeStateStore(rootPath: newPath)
        Task { @MainActor [weak self] in
            await self?.store.reload()
            self?.collectionView.reloadData()
        }
    }

    // MARK: - Double Click

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        let pt = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: pt),
              indexPath.item < store.items.count else { return }
        let fi = store.items[indexPath.item]
        if fi.isDirectory {
            onNavigateTo?(fi.id)
        } else {
            QuickLookCoordinator.shared.preview(url: URL(fileURLWithPath: fi.id))
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension FileTreeIconGridView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return store.items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier("FileGridItem"),
            for: indexPath
        ) as! FileGridItem
        if indexPath.item < store.items.count {
            item.configure(with: store.items[indexPath.item])
        }
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension FileTreeIconGridView: NSCollectionViewDelegate {
    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        selectedIndexPaths = indexPaths
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
        selectedIndexPaths.subtract(indexPaths)
    }
}

// MARK: - FileGridItem（NSCollectionViewItem）

/// 单个缩略图格子 Cell
private final class FileGridItem: NSCollectionViewItem {

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 6

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(iconView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
        ])
    }

    func configure(with item: FileTreeItem) {
        nameLabel.stringValue = item.name
        if item.isDirectory {
            iconView.image = NSWorkspace.shared.icon(for: UTType.folder)
        } else {
            iconView.image = NSWorkspace.shared.icon(forFile: item.id)
        }
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor
                : .none
        }
    }
}
