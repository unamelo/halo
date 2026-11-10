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
        stack.addArrangedSubview(divider())

        stack.addArrangedSubview(TBButton(symbol: "arrow.uturn.backward", tip: "Undo  (⌫)") { [weak self] in self?.app.undo() })
        stack.addArrangedSubview(TBButton(symbol: "trash", tip: "Clear  (C)") { [weak self] in self?.app.clearAll() })
        stack.addArrangedSubview(TBButton(symbol: "xmark", tip: "Done  (Esc clears · ⌃⌥D keeps drawings)") { [weak self] in self?.app.setDrawing(false) })

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

// MARK: - Global hotkeys

var hotKeyActions: [UInt32: () -> Void] = [:]

func installHotKeys() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        DispatchQueue.main.async { hotKeyActions[id.id]?() }
        return noErr
    }, 1, &spec, nil, nil)
}

func registerHotKey(_ id: UInt32, key: Int, _ action: @escaping () -> Void) {
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x48414C4F), id: id), GetApplicationEventTarget(), 0, &ref)
    hotKeyActions[id] = action
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    var tool: Tool = .box
    private var overlays: [Overlay] = []
    private var statusItem: NSStatusItem!
    private var drawing = false
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        rebuildMenu()
        buildOverlays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.buildOverlays() }

        installHotKeys()
        registerHotKey(1, key: kVK_ANSI_D) { [weak self] in self?.hotKeyPressed() }
        registerHotKey(2, key: kVK_ANSI_X) { [weak self] in self?.clearAll() }
        updateClickMonitor()

        if ProcessInfo.processInfo.environment["HALO_DEMO"] != nil { demo() }
    }

    private func buildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { Overlay(screen: $0, app: self) }
    }

    private var overlayUnderMouse: Overlay? {
        let p = NSEvent.mouseLocation
        return overlays.first { NSMouseInRect(p, $0.frame, false) } ?? overlays.first
    }

    // Tap ⌃⌥D: stay in drawing mode with the toolbar. Hold ⌃⌥D: draw while held, clear on release.
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
        let flags = NSEvent.modifierFlags
        if flags.contains(.control) && flags.contains(.option) { return }
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
        rebuildMenu()
    }

    func select(_ t: Tool) {
        tool = t
        refreshToolbars()
    }

    func undo() { overlays.first { $0.isKeyWindow }?.canvas.undo() ?? overlayUnderMouse?.canvas.undo() }

    func settingsChanged() {
        updateClickMonitor()
        rebuildMenu()
    }

    private func refreshToolbars() {
        overlays.forEach { if !$0.canvas.toolbar.isHidden && $0.canvas.toolbar.superview != nil { $0.canvas.toolbar.rebuild() } }
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

    // Menu

    private func rebuildMenu() {
        refreshToolbars()
        statusItem.button?.image = NSImage(systemSymbolName: drawing ? "highlighter" : "scribble.variable", accessibilityDescription: "Halo")
        let menu = NSMenu()
        let draw = item(drawing ? "Stop Drawing" : "Start Drawing") { [weak self] in self.map { $0.setDrawing(!$0.drawing) } }
        draw.keyEquivalent = "d"
        draw.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(draw)
        let clear = item("Clear") { [weak self] in self?.clearAll() }
        clear.keyEquivalent = "x"
        clear.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(clear)
        menu.addItem(.separator())

        menu.addItem(submenu("Colour", palettes.map(\.name), settings.palette) { [weak self] in self?.settings.palette = $0 })
        menu.addItem(submenu("Thickness", thicknesses.map(\.0), settings.thickness) { [weak self] in self?.settings.thickness = $0 })
        menu.addItem(submenu("Motion", motions.map(\.0), settings.motion) { [weak self] in self?.settings.motion = $0 })
        menu.addItem(submenu("Auto-fade", fades.map(\.0), settings.fade) { [weak self] in self?.settings.fade = $0 })
        let glow = item("Glow") { [weak self] in self.map { $0.settings.glow.toggle() } }
        glow.state = settings.glow ? .on : .off
        menu.addItem(glow)
        let clicks = item("Show Clicks") { [weak self] in self.map { $0.settings.clicks.toggle(); $0.updateClickMonitor() } }
        clicks.state = settings.clicks ? .on : .off
        menu.addItem(clicks)
        menu.addItem(.separator())
        menu.addItem(item("Quit Halo") { NSApp.terminate(nil) })
        statusItem.menu = menu
    }

    private func submenu(_ title: String, _ names: [String], _ selected: Int, _ pick: @escaping (Int) -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, name) in names.enumerated() {
            let it = item(name) { pick(i) }
            it.state = i == selected ? .on : .off
            sub.addItem(it)
        }
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let it = ClosureItem(title: title, action: #selector(ClosureItem.fire), keyEquivalent: "")
        it.target = it
        it.closure = { [weak self] in action(); self?.rebuildMenu() }
        return it
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

final class ClosureItem: NSMenuItem {
    var closure: (() -> Void)?
    @objc func fire() { closure?() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
