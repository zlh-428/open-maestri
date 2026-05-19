import AppKit

/// 画布背景层（点阵/纯色/透明），替代 CanvasViewportView.drawLineGrid。
/// 使用 CGPattern 实现网格绘制：每个 tile 只绘制一个网格单元，Core Graphics 自动平铺。
/// pan 时仅更新 pattern phase offset（O(1)），zoom 变化时重建 pattern。
final class CanvasBackground: NSView {
    override var isFlipped: Bool { true }

    var canvasOrigin: CGPoint = .zero { didSet { needsDisplay = true } }
    var zoom: CGFloat = 1.0 {
        didSet {
            if oldValue != zoom {
                cachedPattern = nil  // zoom 变化时 tile 大小改变，需要重建 pattern
            }
            needsDisplay = true
        }
    }
    var backgroundMode: String = "dotGrid" {
        didSet {
            cachedPattern = nil
            needsDisplay = true
        }
    }

    /// 缓存当前 zoom 下的 CGPattern，避免每帧重建
    private var cachedPattern: CGPattern?
    private var cachedPatternZoom: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch backgroundMode {
        case "dotGrid":
            drawLineGridWithPattern(in: dirtyRect)
        case "solid":
            NSColor(white: 0.98, alpha: 1).setFill()
            dirtyRect.fill()
        case "transparent":
            NSColor.clear.setFill()
            dirtyRect.fill()
        default:
            drawLineGridWithPattern(in: dirtyRect)
        }
    }

    // MARK: - CGPattern 网格绘制

    private func drawLineGridWithPattern(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 白色背景
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)

        let gridSpacing = Constants.canvasGridSpacing * zoom

        // 如果 gridSpacing 太小（zoom 非常小），跳过网格绘制避免性能问题
        guard gridSpacing >= 4.0 else { return }

        // 构建或复用 pattern
        let pattern: CGPattern
        if let cached = cachedPattern, cachedPatternZoom == zoom {
            pattern = cached
        } else {
            guard let newPattern = makeGridPattern(tileSize: gridSpacing) else { return }
            cachedPattern = newPattern
            cachedPatternZoom = zoom
            pattern = newPattern
        }

        // 计算 pattern phase：通过 offset 实现 pan 跟随
        // phase 使得 pattern 随 canvasOrigin 移动
        let phaseX = -(canvasOrigin.x * zoom).truncatingRemainder(dividingBy: gridSpacing)
        let phaseY = -(canvasOrigin.y * zoom).truncatingRemainder(dividingBy: gridSpacing)

        // 使用 pattern 颜色空间绘制
        var alpha: CGFloat = 1.0
        let patternSpace = CGColorSpace(patternBaseSpace: nil)!
        ctx.setFillColorSpace(patternSpace)
        ctx.setFillPattern(pattern, colorComponents: &alpha)
        ctx.setPatternPhase(CGSize(width: phaseX, height: phaseY))
        ctx.fill(rect)
    }

    /// 创建一个 tileSize × tileSize 的网格 pattern tile
    /// tile 内容：右边缘竖线 + 底边缘横线（平铺后形成完整网格）
    private func makeGridPattern(tileSize: CGFloat) -> CGPattern? {
        var callbacks = CGPatternCallbacks(
            version: 0,
            drawPattern: { info, ctx in
                guard let info else { return }
                let size = info.load(as: CGFloat.self)
                let lineWidth = Constants.canvasGridLineWidth
                let color = Constants.canvasGridLineColor.cgColor

                ctx.setStrokeColor(color)
                ctx.setLineWidth(lineWidth)

                // 绘制 tile 右边缘竖线
                ctx.move(to: CGPoint(x: size, y: 0))
                ctx.addLine(to: CGPoint(x: size, y: size))

                // 绘制 tile 底边缘横线
                ctx.move(to: CGPoint(x: 0, y: size))
                ctx.addLine(to: CGPoint(x: size, y: size))

                ctx.strokePath()
            },
            releaseInfo: { info in
                info?.deallocate()
            }
        )

        // 传递 tileSize 给 callback
        let infoPtr = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<CGFloat>.size, alignment: MemoryLayout<CGFloat>.alignment)
        infoPtr.storeBytes(of: tileSize, as: CGFloat.self)

        let patternBounds = CGRect(x: 0, y: 0, width: tileSize, height: tileSize)

        return CGPattern(
            info: infoPtr,
            bounds: patternBounds,
            matrix: .identity,
            xStep: tileSize,
            yStep: tileSize,
            tiling: .constantSpacing,
            isColored: true,
            callbacks: &callbacks
        )
    }
}
