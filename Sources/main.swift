import Cocoa
import Carbon.HIToolbox
import QuartzCore

// MARK: - Settings

enum Tool: Int, CaseIterable {
    case box, spotlight, arrow, pen
    var name: String { ["Box", "Spotlight", "Arrow", "Pen"][rawValue] }
}

struct Palette {
    let name: String
    let hex: [UInt32]
    var colors: [CGColor] {
        hex.map { CGColor(srgbRed: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1) }
    }
}

// First and last colour match so the conic gradient has no seam.
let palettes = [
    Palette(name: "Rainbow", hex: [0xFF375F, 0xFF9F0A, 0xFFD60A, 0x30D158, 0x40C8E0, 0x0A84FF, 0xBF5AF2, 0xFF375F]),
    Palette(name: "Ice", hex: [0xE8FBFF, 0x5AC8FA, 0x0A84FF, 0x64D2FF, 0xE8FBFF]),
    Palette(name: "Ember", hex: [0xFF453A, 0xFF9F0A, 0xFFD60A, 0xFF6B3D, 0xFF453A]),
    Palette(name: "Signal", hex: [0xC6FF3D, 0xC6FF3D]),
    Palette(name: "Mono", hex: [0xFFFFFF, 0xFFFFFF]),
]
let thicknesses: [(String, CGFloat)] = [("Thin", 2.5), ("Regular", 4), ("Bold", 7)]
let motions: [(String, Double)] = [("Off", 0), ("Calm", 5), ("Lively", 1.8)]
let fades: [(String, Double)] = [("Never", 0), ("After 3s", 3), ("After 6s", 6), ("After 10s", 10)]

final class Settings {
    private let d = UserDefaults.standard
    init() { d.register(defaults: ["palette": 0, "thickness": 1, "glow": true, "motion": 1, "fade": 0, "clicks": false]) }
    var palette: Int { get { d.integer(forKey: "palette") } set { d.set(newValue, forKey: "palette") } }
    var thickness: Int { get { d.integer(forKey: "thickness") } set { d.set(newValue, forKey: "thickness") } }
    var glow: Bool { get { d.bool(forKey: "glow") } set { d.set(newValue, forKey: "glow") } }
    var motion: Int { get { d.integer(forKey: "motion") } set { d.set(newValue, forKey: "motion") } }
    var fade: Int { get { d.integer(forKey: "fade") } set { d.set(newValue, forKey: "fade") } }
    var clicks: Bool { get { d.bool(forKey: "clicks") } set { d.set(newValue, forKey: "clicks") } }
    var drawKey: HotKey {
        get { HotKey(d.dictionary(forKey: "drawKey")) ?? HotKey(code: kVK_ANSI_D, mods: [.control, .option], name: "D") }
        set { d.set(newValue.dict, forKey: "drawKey") }
    }
    var clearKey: HotKey {
        get { HotKey(d.dictionary(forKey: "clearKey")) ?? HotKey(code: kVK_ANSI_X, mods: [.control, .option], name: "X") }
        set { d.set(newValue.dict, forKey: "clearKey") }
    }

    var style: Style {
        Style(colors: palettes[palette].colors, width: thicknesses[thickness].1, glow: glow, period: motions[motion].1)
    }
    var fadeDelay: Double { fades[fade].1 }
}

struct Style {
    var colors: [CGColor]
    var width: CGFloat
    var glow: Bool
    var period: Double
}

// MARK: - Glow stroke
// A gradient behind a stroked-path mask, plus a blurred copy for the glow.
// Closed shapes spin a conic gradient; open lines (flow) slide a linear one along the stroke.

final class GlowStroke {
    let root = CALayer()
    private let coreHolder = CALayer(), coreMask = CAShapeLayer(), coreGrad = CAGradientLayer()
    private let glowBlur = CALayer(), glowHolder = CALayer(), glowMask = CAShapeLayer(), glowGrad = CAGradientLayer()
    private let coreRotor = CALayer(), glowRotor = CALayer()
    private let width: CGFloat
    private let flow: Bool
    private let period: Double

    init(style: Style, scale: CGFloat, flow: Bool = false) {
        width = style.width
        self.flow = flow
        period = style.period
        for g in [coreGrad, glowGrad] {
            g.contentsScale = scale
            if flow {
                g.type = .axial
                g.colors = style.colors + style.colors.dropFirst()
                g.startPoint = CGPoint(x: 0, y: 0.5)
                g.endPoint = CGPoint(x: 1, y: 0.5)
            } else {
                g.type = .conic
                g.colors = style.colors
                g.startPoint = CGPoint(x: 0.5, y: 0.5)
                g.endPoint = CGPoint(x: 0.5, y: 0)
                if style.period > 0 {
                    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                    spin.fromValue = 0
                    spin.toValue = -2 * Double.pi
                    spin.duration = style.period
                    spin.repeatCount = .infinity
                    g.add(spin, forKey: "spin")
                }
            }
        }
        coreRotor.addSublayer(coreGrad)
        glowRotor.addSublayer(glowGrad)
        for (m, w) in [(coreMask, width), (glowMask, width * 2.4)] {
            m.fillColor = nil
            m.strokeColor = .white
            m.lineWidth = w
            m.lineCap = .round
            m.lineJoin = .round
            m.contentsScale = scale
        }
        coreHolder.mask = coreMask
        coreHolder.addSublayer(coreRotor)
        glowHolder.mask = glowMask
        glowHolder.addSublayer(glowRotor)
        glowBlur.addSublayer(glowHolder)
        glowBlur.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: width * 2.5])!]
        glowBlur.opacity = 0.9
        if style.glow { root.addSublayer(glowBlur) }
        root.addSublayer(coreHolder)
    }

    func setPath(_ path: CGPath, angle: CGFloat = 0) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pad = width * 8 + 24
        let box = path.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad)
        root.frame = box
        var t = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        let local = path.copy(using: &t)
        let b = CGRect(origin: .zero, size: box.size)
        for l in [coreHolder, glowBlur, glowHolder, coreMask, glowMask] { l.frame = b }
        coreMask.path = local
        glowMask.path = local
        let side = hypot(b.width, b.height)
        for r in [coreRotor, glowRotor] {
            r.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            r.position = CGPoint(x: b.midX, y: b.midY)
            r.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        }
        for g in [coreGrad, glowGrad] {
            if flow {
                // Two colour cycles across 2×side; sliding by one side loops seamlessly.
                g.bounds = CGRect(x: 0, y: 0, width: side * 2, height: side)
                g.position = CGPoint(x: side, y: side / 2)
                if period > 0 {
                    g.removeAnimation(forKey: "flow")
                    let slide = CABasicAnimation(keyPath: "position.x")
                    slide.fromValue = 0
                    slide.toValue = side
                    slide.duration = period * 0.6
                    slide.repeatCount = .infinity
                    g.add(slide, forKey: "flow")
                }
            } else {
                g.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                g.position = CGPoint(x: side / 2, y: side / 2)
            }
        }
        CATransaction.commit()
    }
}

// MARK: - Marks

final class Mark {
    let tool: Tool
    let layer = CALayer()
    let stroke: GlowStroke
    var dim: CAShapeLayer?

    init(tool: Tool, style: Style, bounds: CGRect, scale: CGFloat) {
        self.tool = tool
        stroke = GlowStroke(style: style, scale: scale, flow: tool == .arrow || tool == .pen)
        layer.frame = bounds
        if tool == .spotlight {
            let dim = CAShapeLayer()
            dim.frame = bounds
            dim.fillColor = CGColor(gray: 0, alpha: 0.55)
            dim.fillRule = .evenOdd
            dim.path = CGPath(rect: bounds, transform: nil)
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.duration = 0.25
            dim.add(fadeIn, forKey: "in")
            layer.addSublayer(dim)
            self.dim = dim
        }
        layer.addSublayer(stroke.root)
    }

    func update(_ path: CGPath, hole: CGPath? = nil, angle: CGFloat = 0) {
        stroke.setPath(path, angle: angle)
        if let dim, let hole {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = CGMutablePath()
            p.addRect(layer.bounds)
            p.addPath(hole)
            dim.path = p
            CATransaction.commit()
        }
    }

    func pop() {
        let s = CASpringAnimation(keyPath: "transform.scale")
        s.fromValue = 0.5
        s.toValue = 1
        s.damping = 11
        s.initialVelocity = 6
        s.duration = s.settlingDuration
        stroke.root.add(s, forKey: "pop")
    }

    func remove() {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [layer] in layer.removeFromSuperlayer() }
        let a = CABasicAnimation(keyPath: "opacity")
        a.toValue = 0
        a.duration = 0.3
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        layer.add(a, forKey: "out")
        CATransaction.commit()
    }
}

enum Shapes {
    static func box(_ a: CGPoint, _ b: CGPoint) -> CGPath {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        let radius = min(12, r.width / 2, r.height / 2)
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func ring(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }

    static func arrow(_ a: CGPoint, _ b: CGPoint, width: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: a)
        p.addLine(to: b)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let len = min(max(16, width * 5), hypot(b.x - a.x, b.y - a.y) * 0.5)
        for side: CGFloat in [-1, 1] {
            let t = angle + .pi - side * 0.5
            p.move(to: b)
            p.addLine(to: CGPoint(x: b.x + cos(t) * len, y: b.y + sin(t) * len))
        }
        return p
    }

    static func pen(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let first = pts.first else { return p }
        p.move(to: first)
        if pts.count < 3 {
            pts.dropFirst().forEach { p.addLine(to: $0) }
            return p
        }
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }
}

// MARK: - Toolbar

func symbol(_ name: String, _ color: NSColor, size: CGFloat = 14) -> NSImage? {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return nil }
    let tinted = NSImage(size: img.size)
    tinted.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: img.size))
    color.set()
    NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

final class TBButton: NSView {
    var selected = false
    private var hovering = false
    private let paint: (NSRect, Bool) -> Void
    private let onClick: () -> Void

    init(width: CGFloat = 32, tip: String, paint: @escaping (NSRect, Bool) -> Void, onClick: @escaping () -> Void) {
        self.paint = paint
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 32))
        toolTip = tip
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    convenience init(symbol name: String, tip: String, selected: Bool = false, onClick: @escaping () -> Void) {
        self.init(tip: tip, paint: { r, on in
            guard let img = symbol(name, NSColor(white: 1, alpha: on ? 1 : 0.62)) else { return }
            img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }, onClick: onClick)
        self.selected = selected
    }

    override var intrinsicContentSize: NSSize { frame.size }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) {
        if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        if selected || hovering {
            NSColor(white: 1, alpha: selected ? 0.16 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        paint(bounds, selected || hovering)
    }
}

final class Toolbar: NSView {
    unowned let app: AppDelegate
    private let stack = NSStackView()
    private var dragOrigin: NSPoint?

    init(app: AppDelegate) {
        self.app = app
        super.init(frame: .zero)
        wantsLayer = true
        layer?.zPosition = 1000
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 6)
        addSubview(stack)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let st = app.settings
        stack.addArrangedSubview(grip())

        let icons = ["rectangle", "light.max", "arrow.up.right", "scribble"]
        for t in Tool.allCases {
            stack.addArrangedSubview(TBButton(symbol: icons[t.rawValue], tip: "\(t.name)  (\(t.rawValue + 1))", selected: app.tool == t) { [weak self] in self?.app.select(t) })
        }
        stack.addArrangedSubview(divider())

        for (i, pal) in palettes.enumerated() {
            let b = TBButton(width: 26, tip: pal.name, paint: { r, _ in Toolbar.swatch(pal, in: r, selected: i == st.palette) }) { [weak self] in
                self?.app.settings.palette = i; self?.app.settingsChanged()
            }
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(divider())

        for (i, (name, w)) in thicknesses.enumerated() {
            let b = TBButton(width: 28, tip: name, paint: { r, on in
                let path = NSBezierPath()
                path.move(to: NSPoint(x: r.midX - 7, y: r.midY))
                path.line(to: NSPoint(x: r.midX + 7, y: r.midY))
                path.lineWidth = w * 0.8
                path.lineCapStyle = .round
                NSColor(white: 1, alpha: on ? 1 : 0.62).setStroke()
                path.stroke()
            }) { [weak self] in self?.app.settings.thickness = i; self?.app.settingsChanged() }
            b.selected = i == st.thickness
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(divider())

        let motionIcons = ["pause.circle", "arrow.clockwise", "hare"]
        let motion = TBButton(symbol: motionIcons[st.motion], tip: "Motion: \(motions[st.motion].0)", selected: st.motion > 0) { [weak self] in
            guard let self else { return }
            self.app.settings.motion = (st.motion + 1) % motions.count; self.app.settingsChanged()
        }
        stack.addArrangedSubview(motion)
        stack.addArrangedSubview(TBButton(symbol: st.glow ? "sun.max.fill" : "sun.max", tip: "Glow", selected: st.glow) { [weak self] in
            self?.app.settings.glow.toggle(); self?.app.settingsChanged()
        })
        let fadeLabel = fades[st.fade].1 > 0 ? "\(Int(fades[st.fade].1))s" : "∞"
        stack.addArrangedSubview(TBButton(width: 44, tip: "Auto-fade: \(fades[st.fade].0)", paint: { r, on in
            let c = NSColor(white: 1, alpha: on ? 1 : 0.62)
            if let img = symbol("timer", c, size: 12) {
                img.draw(in: NSRect(x: r.minX + 6, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
            }
            let s = NSAttributedString(string: fadeLabel, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: c])
            s.draw(at: NSPoint(x: r.minX + 23, y: r.midY - s.size().height / 2))
        }) { [weak self] in
            guard let self else { return }
            self.app.settings.fade = (st.fade + 1) % fades.count; self.app.settingsChanged()
        })
        stack.addArrangedSubview(TBButton(symbol: "cursorarrow.click.2", tip: "Show clicks: \(st.clicks ? "On" : "Off")", selected: st.clicks) { [weak self] in
            self?.app.settings.clicks.toggle(); self?.app.settingsChanged()
        })
        stack.addArrangedSubview(divider())

        stack.addArrangedSubview(TBButton(symbol: "arrow.uturn.backward", tip: "Undo  (⌫)") { [weak self] in self?.app.undo() })
        stack.addArrangedSubview(TBButton(symbol: "trash", tip: "Clear  (C)") { [weak self] in self?.app.clearAll() })
        stack.addArrangedSubview(TBButton(symbol: "xmark", tip: "Done  (Esc clears)") { [weak self] in self?.app.setDrawing(false) })

        let size = stack.fittingSize
        let origin = frame.origin
        setFrameSize(size)
        stack.frame = bounds
        setFrameOrigin(origin)
        needsDisplay = true
    }

    private func divider() -> NSView {
        let v = NSBox()
        v.boxType = .custom
        v.borderWidth = 0
        v.fillColor = NSColor(white: 1, alpha: 0.12)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let pad = NSView()
        pad.translatesAutoresizingMaskIntoConstraints = false
        pad.widthAnchor.constraint(equalToConstant: 13).isActive = true
        pad.heightAnchor.constraint(equalToConstant: 18).isActive = true
        pad.addSubview(v)
        v.centerXAnchor.constraint(equalTo: pad.centerXAnchor).isActive = true
        v.centerYAnchor.constraint(equalTo: pad.centerYAnchor).isActive = true
        return pad
    }

    // Grip area passes clicks to the toolbar so it can be dragged.
    private func grip() -> NSView {
        let g = GripView(frame: NSRect(x: 0, y: 0, width: 14, height: 32))
        g.translatesAutoresizingMaskIntoConstraints = false
        g.widthAnchor.constraint(equalToConstant: 14).isActive = true
        g.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return g
    }

    static func swatch(_ pal: Palette, in r: NSRect, selected: Bool) {
        let c = NSPoint(x: r.midX, y: r.midY)
        let radius: CGFloat = 8
        let cols = pal.hex.count > 2 ? Array(pal.colors.dropLast()) : [pal.colors[0]]
        let ctx = NSGraphicsContext.current!.cgContext
        for (i, col) in cols.enumerated() {
            let a0 = CGFloat(i) / CGFloat(cols.count) * 2 * .pi + .pi / 2
            let a1 = CGFloat(i + 1) / CGFloat(cols.count) * 2 * .pi + .pi / 2 + 0.02
            ctx.move(to: c)
            ctx.addArc(center: c, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.closePath()
            ctx.setFillColor(col)
            ctx.fillPath()
        }
        if selected {
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - radius - 3.5, y: c.y - radius - 3.5, width: 2 * radius + 7, height: 2 * radius + 7))
            ring.lineWidth = 1.5
            NSColor.white.setStroke()
            ring.stroke()
        }
    }

    override func mouseDown(with e: NSEvent) { dragOrigin = e.locationInWindow }
    override func mouseDragged(with e: NSEvent) {
        guard let o = dragOrigin else { return }
        let p = e.locationInWindow
        setFrameOrigin(NSPoint(x: frame.minX + p.x - o.x, y: frame.minY + p.y - o.y))
        dragOrigin = p
    }
    override func mouseUp(with e: NSEvent) { dragOrigin = nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        NSColor(white: 0.07, alpha: 0.92).setFill()
        bg.fill()
        NSColor(white: 1, alpha: 0.1).setStroke()
        bg.lineWidth = 1
        bg.stroke()
    }
}

final class GripView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.28).setFill()
        for row in 0..<3 {
            for col in 0..<2 {
                NSBezierPath(ovalIn: NSRect(x: 3 + CGFloat(col) * 5, y: bounds.midY - 6 + CGFloat(row) * 5, width: 2.2, height: 2.2)).fill()
            }
        }
    }
}

// MARK: - Canvas

final class Canvas: NSView {
    unowned let app: AppDelegate
    var marks: [Mark] = []
    private var current: Mark?
    private var start = CGPoint.zero
    private var points: [CGPoint] = []
    lazy var toolbar = Toolbar(app: app)
    private var placedToolbar = false

    init(frame: NSRect, app: AppDelegate) {
        self.app = app
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
    }
    required init?(coder: NSCoder) { fatalError() }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    func showToolbar() {
        if toolbar.superview == nil { addSubview(toolbar) }
        toolbar.rebuild()
        if !placedToolbar {
            placedToolbar = true
            toolbar.setFrameOrigin(NSPoint(x: (bounds.width - toolbar.frame.width) / 2, y: bounds.height - toolbar.frame.height - 72))
        }
        toolbar.isHidden = false
        toolbar.alphaValue = 1
    }

    func hideToolbar() { toolbar.isHidden = true }

    func add(_ mark: Mark) {
        layer?.addSublayer(mark.layer)
        marks.append(mark)
    }

    func removeMark(_ mark: Mark) {
        guard let i = marks.firstIndex(where: { $0 === mark }) else { return }
        marks.remove(at: i)
        mark.remove()
    }

    func clear() {
        marks.forEach { $0.remove() }
        marks.removeAll()
        current?.layer.removeFromSuperlayer()
        current = nil
        toolbar.alphaValue = 1
    }
    func undo() { if let m = marks.last { removeMark(m) } }

    // Drawing

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let tool = app.tool
        if tool == .spotlight, let old = marks.first(where: { $0.tool == .spotlight }) { removeMark(old) }
        start = p
        points = [p]
        toolbar.animator().alphaValue = 0.25
        let m = Mark(tool: tool, style: app.settings.style, bounds: bounds, scale: scale)
        layer?.addSublayer(m.layer)
        current = m
        update(to: p)
    }

    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        points.append(p)
        update(to: p)
    }

    override func mouseUp(with e: NSEvent) {
        guard let m = current else { return }
        current = nil
        toolbar.animator().alphaValue = 1
        let p = convert(e.locationInWindow, from: nil)
        let tiny = hypot(p.x - start.x, p.y - start.y) < 8 && (m.tool != .pen || points.count < 4)
        if tiny {
            // A plain click drops a ring marker where you clicked.
            m.layer.removeFromSuperlayer()
            let ring = Mark(tool: .box, style: app.settings.style, bounds: bounds, scale: scale)
            ring.update(Shapes.ring(start, 30))
            add(ring)
            ring.pop()
            app.scheduleFade(ring, on: self)
            return
        }
        marks.append(m)
        app.scheduleFade(m, on: self)
    }

    private func update(to p: CGPoint) {
        guard let m = current else { return }
        switch m.tool {
        case .box: m.update(Shapes.box(start, p))
        case .spotlight: let b = Shapes.box(start, p); m.update(b, hole: b)
        case .arrow: m.update(Shapes.arrow(start, p, width: app.settings.style.width), angle: atan2(p.y - start.y, p.x - start.x))
        case .pen: m.update(Shapes.pen(points))
        }
    }

    // Holding ⌃ turns clicks into right-clicks; draw with them all the same.
    override func rightMouseDown(with e: NSEvent) { mouseDown(with: e) }
    override func rightMouseDragged(with e: NSEvent) { mouseDragged(with: e) }
    override func rightMouseUp(with e: NSEvent) { mouseUp(with: e) }
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func keyDown(with e: NSEvent) {
        switch Int(e.keyCode) {
        case kVK_Escape: app.clearAll(); app.setDrawing(false)
        case kVK_Delete, kVK_ANSI_Z: app.undo()
        case kVK_ANSI_C: app.clearAll()
        case kVK_ANSI_1: app.select(.box)
        case kVK_ANSI_2: app.select(.spotlight)
        case kVK_ANSI_3: app.select(.arrow)
        case kVK_ANSI_4: app.select(.pen)
        case kVK_Return: app.setDrawing(false)
        case kVK_ANSI_T: toolbar.isHidden.toggle()
        default: super.keyDown(with: e)
        }
    }

    // Click ripple (used when "Show Clicks" is on).
    func ripple(at p: CGPoint) {
        var style = app.settings.style
        style.width = 3
        let m = Mark(tool: .box, style: style, bounds: bounds, scale: scale)
        m.update(Shapes.ring(p, 22))
        layer?.addSublayer(m.layer)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.3
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [grow, fade]
        g.duration = 0.55
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        g.fillMode = .forwards
        g.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { m.layer.removeFromSuperlayer() }
        m.stroke.root.add(g, forKey: "ripple")
        CATransaction.commit()
    }
}

// MARK: - Overlay window

final class Overlay: NSWindow {
    let canvas: Canvas
    init(screen: NSScreen, app: AppDelegate) {
        canvas = Canvas(frame: NSRect(origin: .zero, size: screen.frame.size), app: app)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = canvas
        orderFrontRegardless()
    }
    override var canBecomeKey: Bool { true }
}

// MARK: - Hotkeys

struct HotKey {
    var code: Int
    var mods: NSEvent.ModifierFlags
    var name: String

    static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var carbonMods: UInt32 {
        var m = 0
        if mods.contains(.control) { m |= controlKey }
        if mods.contains(.option) { m |= optionKey }
        if mods.contains(.shift) { m |= shiftKey }
        if mods.contains(.command) { m |= cmdKey }
        return UInt32(m)
    }

    var display: String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s + name
    }

    var dict: [String: Any] { ["code": code, "mods": mods.rawValue, "name": name] }

    init(code: Int, mods: NSEvent.ModifierFlags, name: String) {
        self.code = code
        self.mods = mods.intersection(HotKey.relevant)
        self.name = name
    }

    init?(_ d: Any?) {
        guard let d = d as? [String: Any], let code = d["code"] as? Int, let mods = d["mods"] as? UInt, let name = d["name"] as? String else { return nil }
        self.init(code: code, mods: NSEvent.ModifierFlags(rawValue: mods), name: name)
    }

    init?(event e: NSEvent) {
        let mods = e.modifierFlags.intersection(HotKey.relevant)
        guard !mods.isEmpty else { return nil }
        let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                                      kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        let code = Int(e.keyCode)
        let name = special[code] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
        self.init(code: code, mods: mods, name: name)
    }
}

var hotKeyActions: [UInt32: () -> Void] = [:]
var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]

func installHotKeys() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        DispatchQueue.main.async { hotKeyActions[id.id]?() }
        return noErr
    }, 1, &spec, nil, nil)
}

@discardableResult
func registerHotKey(_ id: UInt32, _ hk: HotKey, _ action: @escaping () -> Void) -> Bool {
    unregisterHotKey(id)
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(UInt32(hk.code), hk.carbonMods, EventHotKeyID(signature: OSType(0x48414C4F), id: id), GetApplicationEventTarget(), 0, &ref)
    hotKeyActions[id] = action
    if status == noErr, let ref { hotKeyRefs[id] = ref; return true }
    return false
}

func unregisterHotKey(_ id: UInt32) {
    if let ref = hotKeyRefs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
}

// MARK: - Toolbox (menu-bar panel)

final class HotKeyField: NSView {
    var hotKey: HotKey { didSet { needsDisplay = true } }
    var onChange: (HotKey) -> Void = { _ in }
    var onRecording: (Bool) -> Void = { _ in }
    private var recording = false { didSet { needsDisplay = true; onRecording(recording) } }
    private var monitor: Any?

    init(_ hk: HotKey) {
        hotKey = hk
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 120).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        toolTip = "Click, then press a shortcut with ⌃, ⌥, ⇧ or ⌘"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with e: NSEvent) { recording ? stop() : start() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if Int(e.keyCode) == kVK_Escape { self.stop(); return nil }
            if let hk = HotKey(event: e) { self.hotKey = hk; self.stop(); self.onChange(hk) } else { NSSound.beep() }
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if recording { recording = false }
    }

    override func viewDidMoveToWindow() { if window == nil { stop() } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let bg = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        NSColor(white: 1, alpha: recording ? 0.14 : 0.07).setFill()
        bg.fill()
        (recording ? NSColor.controlAccentColor : NSColor(white: 1, alpha: 0.12)).setStroke()
        bg.lineWidth = recording ? 1.5 : 1
        bg.stroke()
        let text = recording ? "Press keys…" : hotKey.display
        let s = NSAttributedString(string: text, attributes: [
            .font: recording ? NSFont.systemFont(ofSize: 12, weight: .medium) : NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: recording ? 0.6 : 0.95),
        ])
        s.draw(at: NSPoint(x: bounds.midX - s.size().width / 2, y: bounds.midY - s.size().height / 2))
    }
}

final class Toolbox: NSView {
    unowned let app: AppDelegate
    private let stack = NSStackView()
    private var glowSwitch: NSSwitch?, clicksSwitch: NSSwitch?
    private var fields: [HotKeyField] = []

    init(app: AppDelegate) {
        self.app = app
        super.init(frame: NSRect(x: 0, y: 0, width: 316, height: 100))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 316),
        ])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    func stopRecording() { fields.forEach { $0.stop() } }

    func rebuild() {
        stopRecording()
        fields = []
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let st = app.settings

        // Header
        let title = NSTextField(labelWithString: "Halo")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let drawing = app.drawing
        let start = TBButton(width: 150, tip: "Start drawing", paint: { r, on in
            NSColor(white: 1, alpha: on ? 0.2 : 0.12).setFill()
            NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9).fill()
            let s = NSMutableAttributedString(string: drawing ? "Stop drawing  " : "Start drawing  ", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
            s.append(NSAttributedString(string: st.drawKey.display, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.5)]))
            s.draw(at: NSPoint(x: r.midX - s.size().width / 2, y: r.midY - s.size().height / 2))
        }) { [weak self] in self?.app.closeToolbox(); self?.app.toggleDrawing() }
        start.translatesAutoresizingMaskIntoConstraints = false
        start.widthAnchor.constraint(equalToConstant: 150).isActive = true
        start.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [title, spacer, start])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalToConstant: 288).isActive = true
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(rule())

        // Style
        stack.addArrangedSubview(row("Colour", palettes.enumerated().map { i, pal in
            TBButton(width: 28, tip: pal.name, paint: { r, _ in Toolbar.swatch(pal, in: r, selected: i == st.palette) }) { [weak self] in self?.set { $0.palette = i } }
        }))
        stack.addArrangedSubview(row("Thickness", thicknesses.enumerated().map { i, t in
            let b = TBButton(width: 34, tip: t.0, paint: { r, on in
                let p = NSBezierPath()
                p.move(to: NSPoint(x: r.midX - 8, y: r.midY))
                p.line(to: NSPoint(x: r.midX + 8, y: r.midY))
                p.lineWidth = t.1 * 0.8
                p.lineCapStyle = .round
                NSColor(white: 1, alpha: on ? 1 : 0.62).setStroke()
                p.stroke()
            }) { [weak self] in self?.set { $0.thickness = i } }
            b.selected = i == st.thickness
            return b
        }))
        stack.addArrangedSubview(row("Motion", motions.enumerated().map { i, m in text(m.0, selected: i == st.motion) { $0.motion = i } }))
        stack.addArrangedSubview(row("Auto-fade", fades.enumerated().map { i, f in
            text(f.1 > 0 ? "\(Int(f.1))s" : "Never", selected: i == st.fade) { $0.fade = i }
        }))
        let glow = NSSwitch()
        glow.controlSize = .small
        glow.state = st.glow ? .on : .off
        glow.target = self
        glow.action = #selector(toggleGlow)
        stack.addArrangedSubview(row("Glow", [glow]))
        let clicks = NSSwitch()
        clicks.controlSize = .small
        clicks.state = st.clicks ? .on : .off
        clicks.target = self
        clicks.action = #selector(toggleClicks)
        stack.addArrangedSubview(row("Show clicks", [clicks]))
        stack.addArrangedSubview(rule())

        // Shortcuts
        let drawField = HotKeyField(st.drawKey)
        drawField.onChange = { [weak self] hk in self?.app.setHotKey(draw: hk) }
        drawField.onRecording = { [weak self] r in self?.app.suspendHotKeys(r) }
        let clearField = HotKeyField(st.clearKey)
        clearField.onChange = { [weak self] hk in self?.app.setHotKey(clear: hk) }
        clearField.onRecording = { [weak self] r in self?.app.suspendHotKeys(r) }
        fields = [drawField, clearField]
        stack.addArrangedSubview(row("Draw", [drawField]))
        stack.addArrangedSubview(row("Clear", [clearField]))
        stack.addArrangedSubview(note("Tap to toggle with toolbar · hold to draw, release to clear"))
        if let warning = app.hotKeyWarning {
            let w = note(warning)
            w.textColor = .systemOrange
            stack.addArrangedSubview(w)
        }
        stack.addArrangedSubview(rule())

        let quit = TBButton(width: 288, tip: "Quit Halo", paint: { r, on in
            let s = NSAttributedString(string: "Quit Halo", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: on ? 0.9 : 0.5)])
            s.draw(at: NSPoint(x: r.minX + 6, y: r.midY - s.size().height / 2))
        }) { NSApp.terminate(nil) }
        quit.translatesAutoresizingMaskIntoConstraints = false
        quit.widthAnchor.constraint(equalToConstant: 288).isActive = true
        quit.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.addArrangedSubview(quit)
    }

    private func set(_ change: (Settings) -> Void) {
        change(app.settings)
        app.settingsChanged()
    }

    @objc private func toggleGlow(_ s: NSSwitch) { set { $0.glow = s.state == .on } }
    @objc private func toggleClicks(_ s: NSSwitch) { set { $0.clicks = s.state == .on } }

    private func text(_ label: String, selected: Bool, _ change: @escaping (Settings) -> Void) -> TBButton {
        let w = max(44, NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).size().width + 20)
        let b = TBButton(width: w, tip: label, paint: { r, on in
            let s = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: on ? 1 : 0.6)])
            s.draw(at: NSPoint(x: r.midX - s.size().width / 2, y: r.midY - s.size().height / 2))
        }) { [weak self] in self?.set(change) }
        b.selected = selected
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: w).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func row(_ label: String, _ controls: [NSView]) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 12)
        l.textColor = NSColor(white: 1, alpha: 0.55)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 84).isActive = true
        for c in controls where c is TBButton && c.constraints.isEmpty {
            c.translatesAutoresizingMaskIntoConstraints = false
            c.widthAnchor.constraint(equalToConstant: c.frame.width).isActive = true
            c.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let controlsStack = NSStackView(views: controls)
        controlsStack.spacing = 2
        let r = NSStackView(views: [l, controlsStack])
        r.spacing = 6
        return r
    }

    private func note(_ s: String) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = .systemFont(ofSize: 11)
        t.textColor = NSColor(white: 1, alpha: 0.4)
        t.preferredMaxLayoutWidth = 288
        return t
    }

    private func rule() -> NSView {
        let b = NSBox()
        b.boxType = .custom
        b.borderWidth = 0
        b.fillColor = NSColor(white: 1, alpha: 0.08)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 288).isActive = true
        b.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return b
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let settings = Settings()
    var tool: Tool = .box
    private var overlays: [Overlay] = []
    private var statusItem: NSStatusItem!
    private(set) var drawing = false
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?
    private let popover = NSPopover()
    private var toolbox: Toolbox?
    private(set) var hotKeyWarning: String?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        buildOverlays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.buildOverlays() }

        installHotKeys()
        registerHotKeys()
        updateClickMonitor()
        refreshUI()

        if ProcessInfo.processInfo.environment["HALO_DEMO"] != nil { demo() }
        if let out = ProcessInfo.processInfo.environment["HALO_TOOLBOX"] {
            let tb = Toolbox(app: self)
            tb.appearance = NSAppearance(named: .darkAqua)
            tb.layoutSubtreeIfNeeded()
            tb.setFrameSize(tb.fittingSize)
            tb.layoutSubtreeIfNeeded()
            let rep = tb.bitmapImageRepForCachingDisplay(in: tb.bounds)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(white: 0.16, alpha: 1).setFill()
            tb.bounds.fill()
            NSGraphicsContext.restoreGraphicsState()
            tb.cacheDisplay(in: tb.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
            NSApp.terminate(nil)
        }
    }

    private func registerHotKeys() {
        var failed: [String] = []
        if !registerHotKey(1, settings.drawKey, { [weak self] in self?.hotKeyPressed() }) { failed.append(settings.drawKey.display) }
        if !registerHotKey(2, settings.clearKey, { [weak self] in self?.clearAll() }) { failed.append(settings.clearKey.display) }
        hotKeyWarning = failed.isEmpty ? nil : "\(failed.joined(separator: ", ")) is taken by another app. Pick another."
    }

    func suspendHotKeys(_ suspend: Bool) {
        if suspend { unregisterHotKey(1); unregisterHotKey(2) } else { registerHotKeys() }
    }

    func setHotKey(draw: HotKey? = nil, clear: HotKey? = nil) {
        if let draw { settings.drawKey = draw }
        if let clear { settings.clearKey = clear }
        registerHotKeys()
        toolbox?.rebuild()
        fitToolbox()
    }

    @objc private func statusClicked() {
        if popover.isShown { closeToolbox(); return }
        let tb = Toolbox(app: self)
        let vc = NSViewController()
        vc.view = tb
        toolbox = tb
        popover.contentViewController = vc
        fitToolbox()
        NSApp.activate(ignoringOtherApps: true)
        if let b = statusItem.button { popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }

    func closeToolbox() { popover.performClose(nil) }

    private func fitToolbox() {
        guard let tb = toolbox else { return }
        tb.layoutSubtreeIfNeeded()
        popover.contentSize = tb.fittingSize
    }

    func popoverDidClose(_ notification: Notification) {
        toolbox?.stopRecording()
        toolbox = nil
    }

    private func buildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { Overlay(screen: $0, app: self) }
    }

    private var overlayUnderMouse: Overlay? {
        let p = NSEvent.mouseLocation
        return overlays.first { NSMouseInRect(p, $0.frame, false) } ?? overlays.first
    }

    // Tap the draw shortcut: stay in drawing mode with the toolbar.
    // Hold it: draw while the modifiers are held, clear on release.
    private var holdTimer: Timer?
    private var pressedAt = Date()

    private func hotKeyPressed() {
        if holdTimer != nil { return } // key repeat while holding
        if drawing { setDrawing(false); return }
        pressedAt = Date()
        setDrawing(true, toolbar: false)
        // Polling the modifier state needs no Input Monitoring permission.
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in self?.checkHold() }
    }

    private func checkHold() {
        if NSEvent.modifierFlags.intersection(HotKey.relevant).isSuperset(of: settings.drawKey.mods) { return }
        holdTimer?.invalidate()
        holdTimer = nil
        guard drawing else { return }
        if Date().timeIntervalSince(pressedAt) < 0.3 {
            overlayUnderMouse?.canvas.showToolbar()
        } else {
            clearAll()
            setDrawing(false)
        }
    }

    func toggleDrawing() { setDrawing(!drawing) }

    func setDrawing(_ on: Bool, toolbar: Bool = true) {
        guard on != drawing else { return }
        drawing = on
        overlays.forEach { $0.ignoresMouseEvents = !on }
        if on {
            let front = NSWorkspace.shared.frontmostApplication
            if front != .current { previousApp = front }
            NSApp.activate(ignoringOtherApps: true)
            if let o = overlayUnderMouse {
                o.makeKeyAndOrderFront(nil)
                o.makeFirstResponder(o.canvas)
                if toolbar { o.canvas.showToolbar() }
            }
            NSCursor.crosshair.set()
        } else {
            holdTimer?.invalidate()
            holdTimer = nil
            overlays.forEach { $0.canvas.hideToolbar(); $0.orderFrontRegardless() }
            NSCursor.arrow.set()
            previousApp?.activate()
        }
        refreshUI()
    }

    func select(_ t: Tool) {
        tool = t
        refreshUI()
    }

    func undo() { overlays.first { $0.isKeyWindow }?.canvas.undo() ?? overlayUnderMouse?.canvas.undo() }

    func settingsChanged() {
        updateClickMonitor()
        refreshUI()
    }

    private func refreshUI() {
        statusItem.button?.image = NSImage(systemSymbolName: drawing ? "highlighter" : "scribble.variable", accessibilityDescription: "Halo")
        overlays.forEach { if !$0.canvas.toolbar.isHidden && $0.canvas.toolbar.superview != nil { $0.canvas.toolbar.rebuild() } }
        toolbox?.rebuild()
        fitToolbox()
    }

    func clearAll() { overlays.forEach { $0.canvas.clear() } }

    func scheduleFade(_ m: Mark, on canvas: Canvas) {
        let delay = settings.fadeDelay
        guard delay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak canvas, weak m] in
            if let canvas, let m { canvas.removeMark(m) }
        }
    }

    private func updateClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        guard settings.clicks else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, !self.drawing, let o = self.overlayUnderMouse else { return }
            let p = NSEvent.mouseLocation
            o.canvas.ripple(at: CGPoint(x: p.x - o.frame.minX, y: p.y - o.frame.minY))
        }
    }

    // Draws sample marks for screenshots: HALO_DEMO=1
    private func demo() {
        guard let c = overlays.first?.canvas else { return }
        let s = settings.style
        let b = c.bounds
        let box = Mark(tool: .box, style: s, bounds: b, scale: 2)
        box.update(Shapes.box(CGPoint(x: b.width * 0.12, y: b.height * 0.55), CGPoint(x: b.width * 0.42, y: b.height * 0.8)))
        c.add(box)
        let arrow = Mark(tool: .arrow, style: s, bounds: b, scale: 2)
        let a0 = CGPoint(x: b.width * 0.62, y: b.height * 0.25), a1 = CGPoint(x: b.width * 0.45, y: b.height * 0.5)
        arrow.update(Shapes.arrow(a0, a1, width: s.width), angle: atan2(a1.y - a0.y, a1.x - a0.x))
        c.add(arrow)
        let ring = Mark(tool: .box, style: s, bounds: b, scale: 2)
        ring.update(Shapes.ring(CGPoint(x: b.width * 0.75, y: b.height * 0.7), 30))
        c.add(ring)
        let pts = stride(from: 0.0, through: 1.0, by: 0.02).map { t in CGPoint(x: b.width * (0.15 + 0.3 * t), y: b.height * (0.3 + 0.05 * sin(t * 12))) }
        let pen = Mark(tool: .pen, style: s, bounds: b, scale: 2)
        pen.update(Shapes.pen(pts))
        c.add(pen)
        c.showToolbar()
        if let out = ProcessInfo.processInfo.environment["HALO_RENDER"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let rep = c.bitmapImageRepForCachingDisplay(in: c.bounds)!
                let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
                ctx.setFillColor(CGColor(gray: 0.93, alpha: 1)); ctx.fill(c.bounds)
                ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: c.bounds.width / 2, height: c.bounds.height))
                c.layer!.render(in: ctx)
                try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
                NSApp.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
