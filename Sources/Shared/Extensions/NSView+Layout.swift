import AppKit

extension NSView {
    /// 将子视图四边约束到父视图边缘（translatesAutoresizingMaskIntoConstraints 已在调用前设为 false）
    func pinEdges(to parent: NSView) {
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }

    /// 将子视图添加到父视图并固定四边（自动设置 translatesAutoresizingMaskIntoConstraints = false）
    func addSubviewFillingBounds(_ subview: NSView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        subview.pinEdges(to: self)
    }
}
