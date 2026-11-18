import SwiftUI
import WidgetKitCore

/// What the crop step returns (ADR-024).
enum CropChoice {
    /// One widget: the crop rectangle (image pixels), its card shape and the size it suggests.
    case one(rect: CGRect?, shape: WidgetCardShape?, size: SizeChoice)
    /// Every detected widget, one design each ("Create all").
    case all([DetectedWidget])
}

/// The crop step after picking an image (ADR-024): the detected widgets are outlined and the
/// first is selected; drag its corners or pick another, constrain it to a widget size, or use
/// the whole image. With several widgets, "Create all" makes one design per widget.
struct CropView: View {
    let image: CGImage
    let detected: [DetectedWidget]
    /// False in Use another AI, where each crop is shared on its own.
    var allowsAll = true
    let onDone: (CropChoice) -> Void
    let onCancel: () -> Void

    @State private var selection: CGRect
    @State private var selectedIndex: Int?
    @State private var preset: Preset = .free

    enum Preset: Hashable, CaseIterable {
        case free, small, medium, large, xlarge
        /// Width over height (small 1:1, medium about 2.1:1, large about 0.95:1).
        var aspect: CGFloat? {
            switch self {
            case .free: nil
            case .small: 1
            case .medium: 2.14
            case .large: 0.95
            case .xlarge: 0.64
            }
        }
    }

    init(image: CGImage, detected: [DetectedWidget], allowsAll: Bool = true,
         onDone: @escaping (CropChoice) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.detected = detected
        self.allowsAll = allowsAll
        self.onDone = onDone
        self.onCancel = onCancel
        let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // The biggest detection is most likely the widget the user means; the list stays in reading order.
        let biggest = detected.indices.max { detected[$0].rect.width * detected[$0].rect.height < detected[$1].rect.width * detected[$1].rect.height }
        _selection = State(initialValue: biggest.map { detected[$0].rect } ?? whole)
        _selectedIndex = State(initialValue: biggest)
    }

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                canvas
                Picker("crop.preset", selection: $preset) {
                    Text("crop.preset.free").tag(Preset.free)
                    Text("detail.size.small").tag(Preset.small)
                    Text("detail.size.medium").tag(Preset.medium)
                    Text("detail.size.large").tag(Preset.large)
                    Text("detail.size.xlarge").tag(Preset.xlarge)
                }
                .pickerStyle(.segmented)
                .onChange(of: preset) { _, preset in applyPreset(preset) }
                .accessibilityIdentifier("ax.crop.preset")
                Text(detected.isEmpty ? LocalizedStringKey("crop.none") : detected.count > 1 ? "crop.several \(detected.count)" : "crop.found")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    Button {
                        onDone(.one(rect: selection, shape: shape, size: suggestedSize))
                    } label: {
                        Text("crop.use").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("ax.crop.use")
                    if allowsAll, detected.count > 1 {
                        Button {
                            onDone(.all(detected))
                        } label: {
                            Text("crop.all \(detected.count)").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("ax.crop.all")
                    }
                    Button("crop.whole") {
                        onDone(.one(rect: nil, shape: nil, size: .auto))
                    }
                    .accessibilityIdentifier("ax.crop.whole")
                }
            }
            .padding(16)
            .navigationTitle("crop.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onCancel)
                }
            }
        }
    }

    /// The detected shape while the selection is still the detected box; a hand-made crop has none.
    private var shape: WidgetCardShape? {
        guard let selectedIndex, detected.indices.contains(selectedIndex), detected[selectedIndex].rect == selection else { return nil }
        return detected[selectedIndex].shape
    }

    private var suggestedSize: SizeChoice {
        switch preset {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xlarge: return .xlarge
        case .free: return DetectedWidget(rect: selection, shape: shape ?? .roundedRect).suggestedSize(imageWidth: image.width)
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / imageSize.width, proxy.size.height / imageSize.height)
            let shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(x: (proxy.size.width - shown.width) / 2, y: (proxy.size.height - shown.height) / 2)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: origin.x, y: origin.y)
                // Outside the selection is dimmed.
                Path { path in
                    path.addRect(CGRect(origin: origin, size: shown))
                    path.addRect(view(selection, scale: scale, origin: origin))
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                ForEach(Array(detected.enumerated()), id: \.offset) { index, widget in
                    outline(widget.shape)
                        .stroke(index == selectedIndex ? Color.accentColor : Color.white.opacity(0.8),
                                style: StrokeStyle(lineWidth: index == selectedIndex ? 3 : 2, dash: index == selectedIndex ? [] : [6, 4]))
                        .frame(width: widget.rect.width * scale, height: widget.rect.height * scale)
                        .offset(x: origin.x + widget.rect.minX * scale, y: origin.y + widget.rect.minY * scale)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            selection = widget.rect
                            preset = .free
                        }
                        .accessibilityLabel(Text("crop.widget \(index + 1)"))
                        .accessibilityAddTraits(.isButton)
                }
                let box = view(selection, scale: scale, origin: origin)
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .allowsHitTesting(false)
                ForEach(Corner.allCases, id: \.self) { corner in
                    handle(corner, box: box, scale: scale)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("ax.crop.canvas")
    }

    private func outline(_ shape: WidgetCardShape) -> AnyShape {
        switch shape {
        case .circle: AnyShape(Ellipse())
        case .capsule: AnyShape(Capsule())
        case .roundedRect: AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .none: AnyShape(Rectangle())
        }
    }

    private func view(_ rect: CGRect, scale: CGFloat, origin: CGPoint) -> CGRect {
        CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private func handle(_ corner: Corner, box: CGRect, scale: CGFloat) -> some View {
        let point: CGPoint = switch corner {
        case .topLeft: CGPoint(x: box.minX, y: box.minY)
        case .topRight: CGPoint(x: box.maxX, y: box.minY)
        case .bottomLeft: CGPoint(x: box.minX, y: box.maxY)
        case .bottomRight: CGPoint(x: box.maxX, y: box.maxY)
        }
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 26, height: 26)
            .position(point)
            .gesture(DragGesture().onChanged { value in
                let start = dragStart ?? selection
                if dragStart == nil { dragStart = start }
                drag(corner, by: CGSize(width: value.translation.width / scale, height: value.translation.height / scale), from: start)
            }.onEnded { _ in dragStart = nil })
            .accessibilityHidden(true)
    }

    @State private var dragStart: CGRect?

    /// Moves one corner; the opposite corner stays, the box keeps at least 40 px and the preset's shape.
    private func drag(_ corner: Corner, by delta: CGSize, from start: CGRect) {
        var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
        switch corner {
        case .topLeft: minX += delta.width; minY += delta.height
        case .topRight: maxX += delta.width; minY += delta.height
        case .bottomLeft: minX += delta.width; maxY += delta.height
        case .bottomRight: maxX += delta.width; maxY += delta.height
        }
        minX = max(0, min(minX, maxX - 40)); maxX = min(imageSize.width, max(maxX, minX + 40))
        minY = max(0, min(minY, maxY - 40)); maxY = min(imageSize.height, max(maxY, minY + 40))
        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if let aspect = preset.aspect {
            let height = rect.width / aspect
            switch corner {
            case .topLeft, .topRight: rect = CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)
            case .bottomLeft, .bottomRight: rect.size.height = height
            }
        }
        selection = rect.intersection(CGRect(origin: .zero, size: imageSize))
        selectedIndex = detected.firstIndex { $0.rect == selection }
    }

    /// Fits the preset's shape inside the current selection, centered.
    private func applyPreset(_ preset: Preset) {
        guard let aspect = preset.aspect else { return }
        var rect = selection
        if rect.width / rect.height > aspect {
            let width = rect.height * aspect
            rect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        } else {
            let height = rect.width / aspect
            rect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        selection = rect
    }
}
