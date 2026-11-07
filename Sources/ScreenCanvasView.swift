import UIKit

/// 手势回调（操作方式与向日葵 controlclient 一致）
protocol CanvasDelegate: AnyObject {
    /// 鼠标模式：单指相对移动（虚拟指针）
    func canvasPointerMove(_ v: ScreenCanvasView, dxView: CGFloat, dyView: CGFloat)
    /// 鼠标模式：单指轻点 = 左键（在指针处）
    func canvasLeftClick(_ v: ScreenCanvasView)
    /// 鼠标模式：长按后拖动 = 左键按住
    func canvasDragStart(_ v: ScreenCanvasView)
    func canvasDragMove(_ v: ScreenCanvasView, dxView: CGFloat, dyView: CGFloat)
    func canvasDragEnd(_ v: ScreenCanvasView)
    /// 触摸模式：在指定画面坐标操作
    func canvasTapAt(_ v: ScreenCanvasView, at: CGPoint)
    func canvasRightClickAt(_ v: ScreenCanvasView, at: CGPoint?)
    func canvasTouchDragStart(_ v: ScreenCanvasView, at: CGPoint)
    func canvasTouchDragMove(_ v: ScreenCanvasView, at: CGPoint)
    func canvasTouchDragEnd(_ v: ScreenCanvasView)
    /// 通用：双指轻点 = 右键（鼠标模式下在指针处）
    func canvasTwoFingerTap(_ v: ScreenCanvasView)
    /// 通用：双指滑动 = 滚轮（+1 向上 / -1 向下）
    func canvasScroll(_ v: ScreenCanvasView, direction: Int)
}

/// 远程桌面画布：绘制 JPEG 帧 + 虚拟指针 + 点击涟漪 + 双指捏合缩放
final class ScreenCanvasView: UIView {

    weak var delegate: CanvasDelegate?
    var mouseMode = true   // true=鼠标模式(触摸板) false=触摸模式

    var image: UIImage? { didSet { setNeedsDisplay() } }
    var streamSize: CGSize = .zero { didSet { setNeedsDisplay() } }
    /// 虚拟指针（画面坐标，仅鼠标模式绘制）
    var pointer: CGPoint? { didSet { setNeedsDisplay() } }

    private var zoomScale: CGFloat = 1
    private var zoomOffset: CGPoint = .zero

    // ---- 手势状态 ----
    private var touchPoints: [UITouch: CGPoint] = [:]
    private var primary: UITouch?
    private var primaryPrev: CGPoint = .zero
    private var t0 = Date()
    private var origin: CGPoint = .zero          // 视图坐标
    private var moved = false
    private var dragging = false                 // 鼠标模式长按拖动
    private var touchDrag = false                // 触摸模式拖动
    private var longPressFired = false           // 触摸模式长按=右键
    private var longPressTimer: Timer?
    private var twoActive = false
    private var twoDistLast: CGFloat = 0
    private var twoMidLast: CGPoint = .zero
    private var twoMoved = false
    private var scrollAccum: CGFloat = 0
    private var pinchAccum: CGFloat = 1
    private let slop: CGFloat = 12

    override var canBecomeFirstResponder: Bool { true }

    // MARK: - 坐标转换
    func fittedScale() -> CGFloat {
        guard streamSize.width > 1, bounds.width > 1, bounds.height > 1 else { return 1 }
        return min(bounds.width / streamSize.width, bounds.height / streamSize.height)
    }
    func totalScale() -> CGFloat { fittedScale() * zoomScale }

    /// 视图坐标 → 画面坐标
    func toStream(_ p: CGPoint) -> CGPoint? {
        guard streamSize.width > 1 else { return nil }
        let s = totalScale()
        let c = CGPoint(x: bounds.midX + zoomOffset.x, y: bounds.midY + zoomOffset.y)
        return CGPoint(x: (p.x - c.x) / s + streamSize.width / 2,
                       y: (p.y - c.y) / s + streamSize.height / 2)
    }

    // MARK: - 缩放
    private func applyZoom(factor: CGFloat, around p: CGPoint) {
        let old = totalScale()
        zoomScale = min(max(zoomScale * factor, 1), 6)
        let newTotal = totalScale()
        if newTotal != old && streamSize.width > 1 {
            let mb = CGPoint(x: bounds.midX, y: bounds.midY)
            let c = CGPoint(x: mb.x + zoomOffset.x, y: mb.y + zoomOffset.y)
            let f = newTotal / old
            let nc = CGPoint(x: p.x - (p.x - c.x) * f, y: p.y - (p.y - c.y) * f)
            zoomOffset = CGPoint(x: nc.x - mb.x, y: nc.y - mb.y)
            clampOffset()
            setNeedsDisplay()
        }
    }

    private func clampOffset() {
        let w = streamSize.width * totalScale()
        let h = streamSize.height * totalScale()
        var ox = zoomOffset.x, oy = zoomOffset.y
        if w <= bounds.width { ox = 0 }
        else { ox = min(max(ox, -(w - bounds.width) / 2), (w - bounds.width) / 2) }
        if h <= bounds.height { oy = 0 }
        else { oy = min(max(oy, -(h - bounds.height) / 2), (h - bounds.height) / 2) }
        zoomOffset = CGPoint(x: ox, y: oy)
    }

    /// 双击重置缩放
    func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
        setNeedsDisplay()
    }

    // MARK: - 绘制
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(bounds)
        guard let img = image, streamSize.width > 1 else {
            let para = NSMutableParagraphStyle(); para.alignment = .center
            ("等待画面 ..." as NSString).draw(
                in: CGRect(x: 0, y: bounds.midY - 12, width: bounds.width, height: 24),
                withAttributes: [.font: UIFont.systemFont(ofSize: 15),
                                 .foregroundColor: UIColor.svDim,
                                 .paragraphStyle: para])
            return
        }
        let s = totalScale()
        let w = streamSize.width * s, h = streamSize.height * s
        let c = CGPoint(x: bounds.midX + zoomOffset.x, y: bounds.midY + zoomOffset.y)
        let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        ctx.saveGState()
        ctx.clip(to: bounds)
        img.draw(in: rect)
        // 虚拟指针（鼠标模式）
        if mouseMode, let p = pointer {
            let pt = CGPoint(x: c.x - w / 2 + p.x * s, y: c.y - h / 2 + p.y * s)
            drawCursor(ctx: ctx, at: pt)
        }
        ctx.restoreGState()
    }

    private func drawCursor(ctx: CGContext, at p: CGPoint) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: p.x, y: p.y))
        path.addLine(to: CGPoint(x: p.x, y: p.y + 15))
        path.addLine(to: CGPoint(x: p.x + 4.2, y: p.y + 10.6))
        path.addLine(to: CGPoint(x: p.x + 10.5, y: p.y + 12.0))
        path.close()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.setStrokeColor(UIColor.black.cgColor)
        path.fill()
        path.stroke()
    }

    /// 点击涟漪（对齐向日葵 EffectCursorClickView）
    func showClickEffect(at streamPoint: CGPoint, right: Bool) {
        guard streamSize.width > 1 else { return }
        let s = totalScale()
        let c = CGPoint(x: bounds.midX + zoomOffset.x, y: bounds.midY + zoomOffset.y)
        let pt = CGPoint(x: c.x - streamSize.width * s / 2 + streamPoint.x * s,
                         y: c.y - streamSize.height * s / 2 + streamPoint.y * s)
        let ring = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        ring.center = pt
        ring.layer.cornerRadius = 18
        ring.layer.borderWidth = 2.5
        ring.layer.borderColor = right ? UIColor.svOrange.cgColor : UIColor.svBlue.cgColor
        ring.alpha = 0.9
        addSubview(ring)
        UIView.animate(withDuration: 0.35, animations: {
            ring.transform = CGAffineTransform(scaleX: 1.8, y: 1.8)
            ring.alpha = 0
        }) { _ in ring.removeFromSuperview() }
    }

    // MARK: - 触摸
    private func cancelTimers() { longPressTimer?.invalidate(); longPressTimer = nil }

    private func firstPoint() -> CGPoint {
        if let p = primary { return touchPoints[p] ?? p.location(in: self) }
        return touchPoints.values.first ?? .zero
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { touchPoints[t] = t.location(in: self) }
        if touchPoints.count == 1 {
            primary = touches.first
            primaryPrev = firstPoint()
            t0 = Date()
            origin = primaryPrev
            moved = false; dragging = false; touchDrag = false; longPressFired = false
            twoActive = false
            // 长按定时器：鼠标模式=左键拖动开始；触摸模式=右键
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
                guard let self = self, self.touchPoints.count == 1, !self.moved else { return }
                svHaptic(.medium)
                if self.mouseMode {
                    self.dragging = true
                    self.delegate?.canvasDragStart(self)
                } else {
                    self.longPressFired = true
                    let sp = self.toStream(self.origin)
                    self.delegate?.canvasRightClickAt(self, at: sp)
                    if let sp = sp { self.showClickEffect(at: sp, right: true) }
                }
            }
        } else if touchPoints.count == 2 {
            cancelTimers()
            moved = true
            if dragging { delegate?.canvasDragEnd(self); dragging = false }
            if touchDrag { delegate?.canvasTouchDragEnd(self); touchDrag = false }
            let pts = Array(touchPoints.values)
            twoDistLast = hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y)
            twoMidLast = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
            twoActive = true
            twoMoved = false
            pinchAccum = 1
            scrollAccum = 0
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { touchPoints[t] = t.location(in: self) }
        if touchPoints.count == 1, let p = primary, let cur = touchPoints[p] {
            let dx = cur.x - primaryPrev.x
            let dy = cur.y - primaryPrev.y
            primaryPrev = cur
            if !moved && hypot(cur.x - origin.x, cur.y - origin.y) > slop {
                moved = true
                cancelTimers()
                if !mouseMode && !longPressFired {
                    // 向日葵"单指短按移动" = 按下拖动
                    touchDrag = true
                    if let sp = toStream(origin) { delegate?.canvasTouchDragStart(self, at: sp) }
                }
            }
            if mouseMode {
                if dragging {
                    delegate?.canvasDragMove(self, dxView: dx, dyView: dy)
                } else if moved {
                    delegate?.canvasPointerMove(self, dxView: dx, dyView: dy)
                }
            } else if touchDrag {
                if let sp = toStream(cur) { delegate?.canvasTouchDragMove(self, at: sp) }
            }
        } else if touchPoints.count >= 2 {
            let pts = Array(touchPoints.values.prefix(2))
            guard pts.count == 2 else { return }
            let d = hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y)
            let mid = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
            let distDelta = d - twoDistLast
            let midDelta = CGPoint(x: mid.x - twoMidLast.x, y: mid.y - twoMidLast.y)
            if abs(distDelta) > 5 || (abs(distDelta) > abs(midDelta.y) * 1.5 && abs(distDelta) > 1.5) {
                // 双指捏合 → 缩放画面
                twoMoved = true
                pinchAccum *= d / max(twoDistLast, 1)
                if abs(pinchAccum - 1) > 0.04 {
                    applyZoom(factor: pinchAccum, around: mid)
                    pinchAccum = 1
                }
            } else if abs(midDelta.y) > 1.2 {
                // 向日葵"双指移动 = 鼠标滚轮"
                twoMoved = true
                scrollAccum += midDelta.y
                while abs(scrollAccum) >= 28 {
                    delegate?.canvasScroll(self, direction: scrollAccum > 0 ? -1 : 1)
                    scrollAccum += scrollAccum > 0 ? -28 : 28
                }
            }
            twoDistLast = d
            twoMidLast = mid
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelTimers()
        for t in touches {
            touchPoints[t] = nil
            if t == primary { primary = nil }
        }
        if touchPoints.count == 0 {
            let dur = Date().timeIntervalSince(t0)
            if twoActive && !twoMoved && dur < 0.6 {
                // 向日葵"双指轻点 = 鼠标右键"
                delegate?.canvasTwoFingerTap(self)
            } else if mouseMode {
                if dragging {
                    dragging = false
                    delegate?.canvasDragEnd(self)
                } else if !moved && dur < 0.35 {
                    // 向日葵"单指点击 = 鼠标左键"
                    delegate?.canvasLeftClick(self)
                }
            } else {
                if touchDrag {
                    touchDrag = false
                    delegate?.canvasTouchDragEnd(self)
                } else if !moved && !longPressFired && dur < 0.35 {
                    // 向日葵"单指点击 = 鼠标左键"(点在哪点到哪)
                    if let sp = toStream(origin) { delegate?.canvasTapAt(self, at: sp) }
                }
            }
            twoActive = false
        } else if touchPoints.count == 1 {
            // 从双指回到单指：重置基线，防误触发点击
            twoActive = false
            moved = true
            primary = touchPoints.keys.first
            primaryPrev = firstPoint()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelTimers()
        for t in touches {
            touchPoints[t] = nil
            if t == primary { primary = nil }
        }
        if dragging { dragging = false; delegate?.canvasDragEnd(self) }
        if touchDrag { touchDrag = false; delegate?.canvasTouchDragEnd(self) }
        if touchPoints.isEmpty { twoActive = false }
    }
}
