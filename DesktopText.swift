// DesktopText.swift — show a quote or poem directly on the macOS desktop.
//
//   Run:   swift DesktopText.swift          (from the folder containing this file)
//   Move:  hold ⌥ Option and drag the text
//   Edit:  hold ⌥ Option and right-click the text (or ⌥⌃-click) to open the editor
//   Saved texts: in the editor, "Save…" stores the text + layout + position under a name;
//          pick it again from "Saved texts" to restore it.
//   Quit:  Ctrl-C in Terminal, or "Quit" in the editor
//
// Everything is saved to DesktopText.settings.json next to this file (plain JSON; you can also
// hand-edit it while the tool isn't running). Only Swift + AppKit: no network, no dependencies.
//
// Why "Option + right-click" instead of a plain right-click: the text is fully click-through in
// normal use, so plain clicks reach your desktop icons and apps. Holding Option temporarily makes
// the text grabbable (a dashed outline appears when you hover it).

import AppKit

// MARK: - Settings file (lives next to this .swift file)

let settingsURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("DesktopText.settings.json")

/// Where the text sits on one display. Stored per display, keyed by the display's UUID.
struct Placement: Codable {
    var display: String   // human-readable display name (for reference only)
    var x: Double         // left edge of the text block, in points from the display's left edge
    var y: Double         // top edge of the text block, in points from the display's top edge
}

struct Settings: Codable {
    var text = "The happiness of your life depends upon the quality of your thoughts.\n— Marcus Aurelius"
    var fontName = "Georgia-Italic"   // PostScript name, e.g. "HelveticaNeue-Light"
    var fontSize = 30.0
    var color = "#FFFFFF"             // hex RGB
    var opacity = 0.85                // 0…1
    var alignment = "center"          // "left" | "center" | "right"
    var lineSpacing = 6.0
    var wrapWidth = 720.0             // long lines wrap at this width (points)
    var shadow = true                 // soft shadow for readability on bright wallpapers
    var placements: [String: Placement] = [:]
    var presets: [String: Preset] = [:]   // saved texts, by name (see Preset below)
    var activePreset = ""                 // name of the last saved/loaded preset ("" = none)

    init() {}

    // Tolerant decoding: any missing key falls back to its default, so a hand-edited file still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        text        = try c.decodeIfPresent(String.self, forKey: .text) ?? d.text
        fontName    = try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName
        fontSize    = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        color       = try c.decodeIfPresent(String.self, forKey: .color) ?? d.color
        opacity     = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        alignment   = try c.decodeIfPresent(String.self, forKey: .alignment) ?? d.alignment
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? d.lineSpacing
        wrapWidth   = try c.decodeIfPresent(Double.self, forKey: .wrapWidth) ?? d.wrapWidth
        shadow      = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? d.shadow
        placements  = try c.decodeIfPresent([String: Placement].self, forKey: .placements) ?? [:]
        presets     = try c.decodeIfPresent([String: Preset].self, forKey: .presets) ?? [:]
        activePreset = try c.decodeIfPresent(String.self, forKey: .activePreset) ?? ""
    }
}

/// A saved text: the text plus every layout setting, including its position on each display.
struct Preset: Codable {
    var text: String
    var fontName: String
    var fontSize: Double
    var color: String
    var opacity: Double
    var alignment: String
    var lineSpacing: Double
    var wrapWidth: Double
    var shadow: Bool
    var placements: [String: Placement]

    /// Snapshot of what is currently shown.
    init(snapshot s: Settings) {
        text = s.text; fontName = s.fontName; fontSize = s.fontSize; color = s.color
        opacity = s.opacity; alignment = s.alignment; lineSpacing = s.lineSpacing
        wrapWidth = s.wrapWidth; shadow = s.shadow; placements = s.placements
    }

    /// Put this preset on screen. Displays the preset doesn't know keep their current position.
    func apply(to s: inout Settings) {
        s.text = text; s.fontName = fontName; s.fontSize = fontSize; s.color = color
        s.opacity = opacity; s.alignment = alignment; s.lineSpacing = lineSpacing
        s.wrapWidth = wrapWidth; s.shadow = shadow
        s.placements.merge(placements) { _, saved in saved }
    }
}

/// Loads/saves Settings. Saves are debounced so dragging sliders doesn't hammer the disk.
final class Store {
    var settings = Settings()
    private var pendingSave: DispatchWorkItem?

    func load() {
        guard let data = try? Data(contentsOf: settingsURL) else { saveNow(); return }  // first run: write defaults
        do {
            settings = try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            // Don't silently lose a hand-edited file: keep a copy before defaults overwrite it.
            let backup = settingsURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: settingsURL, to: backup)
            print("DesktopText: settings file unreadable (\(error.localizedDescription)). Using defaults; old file copied to \(backup.lastPathComponent).")
        }
    }

    func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel(); pendingSave = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do { try encoder.encode(settings).write(to: settingsURL, options: .atomic) }
        catch { print("DesktopText: couldn't save settings: \(error.localizedDescription)") }
    }
}

// MARK: - Small helpers

func color(hex: String) -> NSColor {
    let h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return .white }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func hexString(_ c: NSColor) -> String {
    let c = c.usingColorSpace(.sRGB) ?? .white
    return String(format: "#%02X%02X%02X",
                  Int((c.redComponent * 255).rounded()),
                  Int((c.greenComponent * 255).rounded()),
                  Int((c.blueComponent * 255).rounded()))
}

/// Stable identifier for a display (survives reboots and re-plugging), used as the placement key.
func screenKey(_ screen: NSScreen) -> String {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else { return screen.localizedName }
    let id = CGDirectDisplayID(number.uint32Value)
    if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
        return CFUUIDCreateString(nil, uuid) as String
    }
    return "display-\(id)"
}

let padding: CGFloat = 12
let drawOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

/// Builds the styled string from settings (font, colour, alignment, spacing, shadow).
func styledText(_ s: Settings) -> NSAttributedString {
    let font = NSFont(name: s.fontName, size: s.fontSize) ?? .systemFont(ofSize: s.fontSize)
    let paragraph = NSMutableParagraphStyle()
    let alignments: [String: NSTextAlignment] = ["left": .left, "center": .center, "right": .right]
    paragraph.alignment = alignments[s.alignment] ?? .center
    paragraph.lineSpacing = s.lineSpacing
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph,
                                                .foregroundColor: color(hex: s.color)]
    if s.shadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        attrs[.shadow] = shadow
    }
    return NSAttributedString(string: s.text.isEmpty ? " " : s.text, attributes: attrs)
}

/// Size of the (padded) block the text needs at the given wrap width.
func blockSize(_ text: NSAttributedString, wrapWidth: Double) -> NSSize {
    let r = text.boundingRect(with: NSSize(width: wrapWidth, height: 100_000), options: drawOptions)
    return NSSize(width: max(40, ceil(r.width) + 2 + 2 * padding),
                  height: max(24, ceil(r.height) + 2 + 2 * padding))
}

// Window levels: just above the wallpaper (under Finder's desktop icons) at rest, and just above the
// icons while ⌥ is held so the text can receive the mouse. Both are far below normal app windows.
let restingLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
let grabLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

// MARK: - The text on one display

/// Draws the text. Handles ⌥-drag and ⌥-right-click (the window only gets mouse events while ⌥ is held).
final class TextView: NSView {
    var text = NSAttributedString()
    var showOutline = false { didSet { needsDisplay = true } }
    weak var owner: DisplayText?
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero

    override var isFlipped: Bool { true }                               // lay text out top-down
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true } // react without activating first

    override func draw(_ dirtyRect: NSRect) {
        if showOutline {  // dashed outline = "you can grab this now"
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6)
            path.lineWidth = 1
            path.setLineDash([5, 4], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.8).setStroke(); path.stroke()
            path.setLineDash([5, 4], count: 2, phase: 4.5)
            NSColor.black.withAlphaComponent(0.5).setStroke(); path.stroke()
        }
        text.draw(with: bounds.insetBy(dx: padding, dy: padding), options: drawOptions, context: nil)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { owner?.openEditor(); return }  // ⌥⌃-click = right-click
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        owner?.isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        owner?.move(to: NSPoint(x: dragStartOrigin.x + m.x - dragStartMouse.x,
                                y: dragStartOrigin.y + m.y - dragStartMouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard owner?.isDragging == true else { return }
        owner?.isDragging = false
        owner?.savePlacement()
    }

    override func rightMouseDown(with event: NSEvent) { owner?.openEditor() }
}

/// One borderless, transparent, click-through window per display.
final class DisplayText {
    let key: String
    let screen: NSScreen
    let window: NSWindow
    let view = TextView()
    unowned let app: AppController
    var isDragging = false

    init(screen: NSScreen, app: AppController) {
        self.screen = screen
        self.app = app
        key = screenKey(screen)
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear           // no background, no frame: only the glyphs
        window.hasShadow = false
        window.ignoresMouseEvents = true          // click-through by default
        window.isReleasedWhenClosed = false
        window.level = restingLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]  // every Space, not in ⌘-Tab/Mission Control
        window.contentView = view
        view.owner = self
        refresh()
        window.orderFrontRegardless()
    }

    /// Re-render from current settings and place the block (top-left anchored) on this display.
    func refresh() {
        let s = app.store.settings
        view.text = styledText(s)
        let size = blockSize(view.text, wrapWidth: s.wrapWidth)
        let f = screen.frame
        let p = s.placements[key] ?? Placement(display: screen.localizedName,
                                                x: (f.width - size.width) / 2, y: f.height * 0.3)
        let origin = clamped(NSPoint(x: f.minX + p.x, y: f.maxY - p.y - size.height), size: size)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        window.alphaValue = CGFloat(min(max(s.opacity, 0.05), 1))
        view.needsDisplay = true
    }

    /// Keep the block on its own display.
    func clamped(_ o: NSPoint, size: NSSize) -> NSPoint {
        let f = screen.frame
        return NSPoint(x: min(max(o.x, f.minX), max(f.minX, f.maxX - size.width)),
                       y: min(max(o.y, f.minY), max(f.minY, f.maxY - size.height)))
    }

    func move(to origin: NSPoint) { window.setFrameOrigin(clamped(origin, size: window.frame.size)) }

    /// Where the text is right now on this display (whether or not it was ever dragged).
    func currentPlacement() -> Placement {
        let f = screen.frame, w = window.frame
        return Placement(display: screen.localizedName, x: w.minX - f.minX, y: f.maxY - w.maxY)
    }

    func savePlacement() {
        app.store.settings.placements[key] = currentPlacement()
        app.store.saveSoon()
    }

    /// Called ~20×/s: become grabbable while ⌥ is held; show the outline when hovering.
    func sync(optionDown: Bool, mouse: NSPoint) {
        let interactive = optionDown || isDragging
        if window.ignoresMouseEvents == interactive {
            window.ignoresMouseEvents = !interactive
            window.level = interactive ? grabLevel : restingLevel
        }
        let hover = interactive && window.frame.contains(mouse)
        if view.showOutline != hover { view.showOutline = hover }
    }

    func openEditor() { app.editor.show(for: self) }
}

// MARK: - Editor panel

/// Wraps a closure so it can be an AppKit target/action.
final class Action: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}

final class Editor: NSObject, NSTextViewDelegate {
    unowned let app: AppController
    let panel: NSPanel
    private let textView: NSTextView
    private let presetPopup = NSPopUpButton()
    private let familyPopup = NSPopUpButton()
    private let stylePopup = NSPopUpButton()
    private var actions: [Action] = []
    private var reloaders: [() -> Void] = []   // each copies the current settings into one control
    private var displayKey = ""                // which display "Reset position" applies to

    private var settings: Settings { app.store.settings }

    init(app: AppController) {
        self.app = app
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        super.init()

        panel.title = "DesktopText"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating

        // Saved texts: pick one to restore it (text + layout + position), or save the current one.
        presetPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true
        bind(presetPopup) { [unowned self] _ in self.loadSelectedPreset() }
        let save = NSButton(title: "Save…", target: nil, action: nil)
        bind(save) { [unowned self] _ in self.askToSave() }
        let delete = NSButton(title: "Delete", target: nil, action: nil)
        bind(delete) { [unowned self] _ in self.askToDelete() }
        let presetRow = NSStackView(views: [NSTextField(labelWithString: "Saved texts"), presetPopup, save, delete])

        // Text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.delegate = self
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 430).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        reloaders.append { [unowned self] in
            if self.textView.string != self.settings.text { self.textView.string = self.settings.text }
        }

        // Font family + style
        familyPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies)
        familyPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        stylePopup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        bind(familyPopup) { [unowned self] _ in
            self.fillStyles(family: self.familyPopup.titleOfSelectedItem ?? "Helvetica", selecting: nil)
            self.applyFont()
        }
        bind(stylePopup) { [unowned self] _ in self.applyFont() }
        reloaders.append { [unowned self] in
            let ps = self.settings.fontName
            let family = NSFont(name: ps, size: 12)?.familyName ?? "Helvetica"
            self.familyPopup.selectItem(withTitle: family)
            self.fillStyles(family: family, selecting: ps)
        }

        // Colour (opacity has its own slider, so no alpha in the colour picker)
        let well = NSColorWell()
        NSColorPanel.shared.showsAlpha = false
        bind(well) { [unowned self] c in
            let hex = hexString((c as! NSColorWell).color)
            self.app.update { $0.color = hex }
        }
        reloaders.append { [unowned self] in well.color = color(hex: self.settings.color) }

        // Alignment
        let aligns = ["left", "center", "right"]
        let align = NSSegmentedControl(labels: ["Left", "Centre", "Right"], trackingMode: .selectOne,
                                       target: nil, action: nil)
        bind(align) { [unowned self] c in
            let a = aligns[max(0, (c as! NSSegmentedControl).selectedSegment)]
            self.app.update { $0.alignment = a }
        }
        reloaders.append { [unowned self] in align.selectedSegment = aligns.firstIndex(of: self.settings.alignment) ?? 1 }

        let shadow = NSButton(checkboxWithTitle: "Soft shadow (helps on bright wallpapers)", target: nil, action: nil)
        bind(shadow) { [unowned self] c in
            let on = (c as! NSButton).state == .on
            self.app.update { $0.shadow = on }
        }
        reloaders.append { [unowned self] in shadow.state = self.settings.shadow ? .on : .off }

        let points: (Double) -> String = { String(format: "%.0f pt", $0) }
        func label(_ t: String) -> NSTextField { NSTextField(labelWithString: t) }
        let grid = NSGridView(views: [
            [label("Font"), NSStackView(views: [familyPopup, stylePopup])],
            [label("Size"), sliderRow(8, 160, \.fontSize, points)],
            [label("Colour"), well],
            [label("Opacity"), sliderRow(0.05, 1, \.opacity, { String(format: "%.0f%%", $0 * 100) },
                                         round: { ($0 * 100).rounded() / 100 })],
            [label("Alignment"), align],
            [label("Line spacing"), sliderRow(0, 60, \.lineSpacing, points)],
            [label("Wrap width"), sliderRow(150, 2400, \.wrapWidth, points)],
            [NSGridCell.emptyContentView, shadow],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.columnSpacing = 10

        let hint = NSTextField(labelWithString: "On the desktop: hold ⌥ and drag to move · ⌥ + right-click to open this panel.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        // Buttons
        let reset = NSButton(title: "Reset position", target: nil, action: nil)
        bind(reset) { [unowned self] _ in
            let key = self.displayKey
            self.app.update { $0.placements[key] = nil }
        }
        let quit = NSButton(title: "Quit DesktopText", target: nil, action: nil)
        bind(quit) { _ in NSApp.terminate(nil) }
        let done = NSButton(title: "Done", target: nil, action: nil)
        bind(done) { [unowned self] _ in self.panel.orderOut(nil) }
        let buttons = NSStackView()
        buttons.setViews([reset], in: .leading)
        buttons.setViews([quit, done], in: .trailing)

        let stack = NSStackView(views: [presetRow, scroll, grid, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
        panel.contentView = stack
        reloadControls()
        panel.setContentSize(stack.fittingSize)
    }

    /// Show the panel near the display whose text was clicked.
    func show(for display: DisplayText) {
        displayKey = display.key
        reloadControls()
        if !panel.isVisible {
            let v = display.screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.midX - panel.frame.width / 2, y: v.midY - panel.frame.height / 2))
        }
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(textView)
    }

    /// Copy the current settings into every control (after loading a saved text, or on open).
    func reloadControls() {
        reloaders.forEach { $0() }
        rebuildPresetMenu()
    }

    func textDidChange(_ notification: Notification) {
        let t = textView.string
        app.update { $0.text = t }
    }

    // MARK: Saved texts

    private func rebuildPresetMenu() {
        let menu = NSMenu()
        let placeholder = NSMenuItem(title: settings.presets.isEmpty ? "No saved texts yet" : "Choose a saved text…",
                                     action: nil, keyEquivalent: "")
        menu.addItem(placeholder)
        let names = settings.presets.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in names {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.representedObject = name
            menu.addItem(item)
        }
        presetPopup.menu = menu
        presetPopup.select(menu.items.first { ($0.representedObject as? String) == settings.activePreset } ?? placeholder)
    }

    private func loadSelectedPreset() {
        guard let name = presetPopup.selectedItem?.representedObject as? String,
              let preset = settings.presets[name] else { return }
        app.update { preset.apply(to: &$0); $0.activePreset = name }
        reloadControls()
    }

    /// "Save…": ask for a name (pre-filled), then save — asking before replacing an existing one.
    private func askToSave() {
        let alert = NSAlert()
        alert.messageText = "Save text as"
        alert.informativeText = "Saves the text with its font, colour, spacing and position on each display."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Name"
        field.stringValue = settings.activePreset.isEmpty ? suggestedName() : settings.activePreset
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: panel) { [unowned self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            if self.settings.presets[name] == nil {
                self.save(as: name)
            } else {
                DispatchQueue.main.async { self.confirmReplace(name) }  // let the first sheet close first
            }
        }
    }

    private func confirmReplace(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "“\(name)” already exists. Replace old version?"
        alert.addButton(withTitle: "Replace").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: panel) { [unowned self] response in
            if response == .alertFirstButtonReturn { self.save(as: name) }
        }
    }

    private func save(as name: String) {
        var preset = Preset(snapshot: settings)
        preset.placements = app.currentPlacements()   // where the text actually is on every display right now
        app.update { $0.presets[name] = preset; $0.activePreset = name }
        rebuildPresetMenu()
    }

    private func askToDelete() {
        guard let name = presetPopup.selectedItem?.representedObject as? String else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "The text currently on the desktop stays as it is."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: panel) { [unowned self] response in
            guard response == .alertFirstButtonReturn else { return }
            self.app.update {
                $0.presets[name] = nil
                if $0.activePreset == name { $0.activePreset = "" }
            }
            self.rebuildPresetMenu()
        }
    }

    /// First non-empty line of the text, shortened — a sensible default name.
    private func suggestedName() -> String {
        let first = settings.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled"
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : (trimmed.isEmpty ? "Untitled" : trimmed)
    }

    // MARK: Control helpers

    // Font helpers: families in one popup, that family's styles (Regular, Italic, Bold…) in the other.
    private func fillStyles(family: String, selecting postScriptName: String?) {
        let menu = NSMenu()
        for member in NSFontManager.shared.availableMembers(ofFontFamily: family) ?? [] {
            guard let ps = member[0] as? String, let style = member[1] as? String else { continue }
            let item = NSMenuItem(title: style, action: nil, keyEquivalent: "")
            item.representedObject = ps
            menu.addItem(item)
        }
        stylePopup.menu = menu
        let wanted = menu.items.first { ($0.representedObject as? String) == postScriptName }
            ?? menu.items.first { $0.title == "Regular" } ?? menu.items.first
        if let wanted { stylePopup.select(wanted) }
    }

    private func applyFont() {
        guard let ps = stylePopup.selectedItem?.representedObject as? String else { return }
        app.update { $0.fontName = ps }
    }

    private func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        let action = Action(handler)
        actions.append(action)   // keep it alive (target is weak)
        control.target = action
        control.action = #selector(Action.fire(_:))
    }

    /// Slider + value readout bound to one numeric setting.
    private func sliderRow(_ lo: Double, _ hi: Double, _ key: WritableKeyPath<Settings, Double>,
                           _ format: @escaping (Double) -> String,
                           round: @escaping (Double) -> Double = { $0.rounded() }) -> NSView {
        let slider = NSSlider(value: lo, minValue: lo, maxValue: hi, target: nil, action: nil)
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let readout = NSTextField(labelWithString: "")
        readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        readout.widthAnchor.constraint(equalToConstant: 60).isActive = true
        bind(slider) { [unowned self] c in
            let v = round((c as! NSSlider).doubleValue)
            readout.stringValue = format(v)
            self.app.update { $0[keyPath: key] = v }
        }
        reloaders.append { [unowned self] in
            let v = self.settings[keyPath: key]
            slider.doubleValue = min(max(v, lo), hi)
            readout.stringValue = format(v)
        }
        return NSStackView(views: [slider, readout])
    }
}

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate {
    let store = Store()
    var displays: [DisplayText] = []
    lazy var editor = Editor(app: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()
        installEditMenu()
        buildDisplays()
        // Rebuild when monitors are plugged/unplugged or rearranged.
        NotificationCenter.default.addObserver(self, selector: #selector(buildDisplays),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Poll the Option key. Reading modifier state needs no Accessibility/Input Monitoring permission.
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let optionDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
            let mouse = NSEvent.mouseLocation
            self.displays.forEach { $0.sync(optionDown: optionDown, mouse: mouse) }
        }
        print("DesktopText is running. Hold ⌥ and drag the text to move it; ⌥ + right-click to edit. Ctrl-C to quit.")
        print("Settings: \(settingsURL.path)")
    }

    @objc func buildDisplays() {
        displays.forEach { $0.window.close() }
        displays = NSScreen.screens.map { DisplayText(screen: $0, app: self) }
    }

    /// Change settings, redraw every display, save shortly after.
    func update(_ change: (inout Settings) -> Void) {
        change(&store.settings)
        displays.forEach { $0.refresh() }
        store.saveSoon()
    }

    /// Current position on every connected display — stored with a saved text.
    func currentPlacements() -> [String: Placement] {
        Dictionary(displays.map { ($0.key, $0.currentPlacement()) }, uniquingKeysWith: { first, _ in first })
    }

    func applicationWillTerminate(_ notification: Notification) { store.saveNow() }

    /// Accessory apps have no visible menu bar, but a main menu is still needed for ⌘C/⌘V/⌘Z in the editor.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DesktopText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}

// MARK: - Main

// Only one copy at a time (a second `swift DesktopText.swift` just exits).
let lockFD = open(NSTemporaryDirectory() + "DesktopText.lock", O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    print("DesktopText is already running.")
    exit(0)
}

let controller = AppController()

// Ctrl-C / closing Terminal / kill: flush pending settings, then exit.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { controller.store.saveNow(); exit(0) }
    source.resume()
    signalSources.append(source)
}

let app = NSApplication.shared
app.delegate = controller
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
