import SwiftUI
import AppKit
import NaturalLanguage

struct ReaderSentence: Identifiable {
    let range: NSRange
    let text: String
    var id: Int { range.location }

    static func split(_ text: String) -> [ReaderSentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [ReaderSentence] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(ReaderSentence(range: NSRange(range, in: text), text: String(text[range])))
            return true
        }
        return sentences
    }
}

/// The reading surface uses its own text colors so every background stays legible.
private enum ReaderBackground: String, CaseIterable, Identifiable {
    case system, paper, sepia, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }
    var color: Color {
        switch self {
        case .system: return Color(nsColor: .windowBackgroundColor)
        case .paper: return Color(red: 0.98, green: 0.98, blue: 0.97)
        case .sepia: return Color(red: 0.96, green: 0.91, blue: 0.81)
        case .dark: return Color(red: 0.10, green: 0.11, blue: 0.13)
        }
    }
    var textColor: Color {
        switch self {
        case .system: return .primary
        case .paper, .sepia: return Color(red: 0.16, green: 0.14, blue: 0.12)
        case .dark: return Color(red: 0.94, green: 0.94, blue: 0.95)
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .paper, .sepia: return .light
        case .dark: return .dark
        }
    }
}

private final class ReaderHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

/// Paint only the native title bar. A clear window background is still needed
/// for the reader's adjustable opacity, but newer macOS versions also expose
/// that clear background behind the traffic lights unless we supply a surface.
private final class ReaderTitlebarBackground: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class PlaybackReaderWindow {
    static let shared = PlaybackReaderWindow()
    private var window: NSWindow?

    func show(audio: AudioController) {
        if window == nil {
            let hosting = ReaderHostingView(rootView: PlaybackReaderView(audio: audio))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 490),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            // Extend a transparent container behind the native title bar, then
            // back only that strip with an opaque, appearance-aware surface.
            // Use AppKit's layout guide rather than a fixed title-bar height.
            w.titlebarAppearsTransparent = true
            let container = NSView()
            let titlebar = ReaderTitlebarBackground()
            w.contentView = container
            let layoutGuide = w.contentLayoutGuide as! NSLayoutGuide
            for view in [titlebar, hosting] {
                view.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(view)
            }
            NSLayoutConstraint.activate([
                titlebar.topAnchor.constraint(equalTo: container.topAnchor),
                titlebar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                titlebar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                titlebar.bottomAnchor.constraint(equalTo: layoutGuide.topAnchor),
                hosting.topAnchor.constraint(equalTo: layoutGuide.topAnchor),
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            w.isOpaque = false
            w.backgroundColor = .clear
            w.title = "Narrateify Reader"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.contentMinSize = NSSize(width: 530, height: 330)
            if !w.setFrameUsingName("NarrateifyPlaybackReader") { w.center() }
            w.setFrameAutosaveName("NarrateifyPlaybackReader")
            window = w
        }
        window?.orderFrontRegardless()
    }
}

private struct PlaybackReaderView: View {
    @ObservedObject var audio: AudioController
    @AppStorage("readerSentenceHighlight") private var sentenceMode = false
    @AppStorage("readerHighlightColor") private var colorRaw = ReaderHighlightColor.yellow.rawValue
    @AppStorage("readerFollowPlayback") private var follow = true
    @AppStorage("readerFontSize") private var fontSize = 20.0
    @AppStorage("readerBackground") private var backgroundRaw = ReaderBackground.system.rawValue
    @AppStorage("readerBackgroundOpacity") private var backgroundOpacity = 1.0
    @AppStorage("readerHighlightOpacity") private var highlightOpacity = 0.38
    @State private var showAppearance = false

    private var background: ReaderBackground { ReaderBackground(rawValue: backgroundRaw) ?? .system }
    private var readingFontSize: Double { min(40, max(14, fontSize)) }

    private var active: SpeechTiming? { SpeechTimeline.active(at: audio.currentTime, in: audio.wordTimings) }
    private var sentenceID: Int? {
        guard let active else { return nil }
        return audio.readerSentences.first { NSIntersectionRange($0.range, active.range).length > 0 }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reader").font(.headline)
                Spacer()
                Button { showAppearance.toggle() } label: {
                    Label("Appearance", systemImage: "textformat.size")
                }
                .help("Change font size, highlighting, background, and transparency")
                .popover(isPresented: $showAppearance, arrowEdge: .bottom) { appearanceControls }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    if audio.readerSentences.isEmpty {
                        Text("Narrate text with Kokoro to follow along here.")
                            .foregroundStyle(.secondary).padding(28)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(audio.readerSentences) { sentence in
                                Text(styled(sentence))
                                    .font(.system(size: readingFontSize)).lineSpacing(readingFontSize * 0.3)
                                    .foregroundStyle(background.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(sentence.id)
                            }
                        }.padding(24)
                    }
                }
                .onChange(of: sentenceID) { _, id in
                    if follow, let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background.color.opacity(min(1, max(0.25, backgroundOpacity))))
            Divider()
            VStack(spacing: 12) {
                Slider(value: Binding(get: { audio.currentTime }, set: { audio.seek(to: $0) }),
                       in: 0...max(0.01, audio.duration))
                    .disabled(!audio.hasAudio)
                    .accessibilityLabel("Playback position")
                HStack(spacing: 14) {
                    Button { audio.togglePlayPause() } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    }.help("Play or pause").disabled(!audio.hasAudio)
                    Button { AppState.shared.stop() } label: { Image(systemName: "stop.fill") }
                        .help("Stop narration")
                    Picker("Highlight", selection: $sentenceMode) {
                        Text("Word").tag(false)
                        Text("Sentence").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 155)
                    Picker("Speed", selection: $audio.rate) {
                        ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in
                            Text(String(format: "%g×", rate)).tag(rate)
                        }
                    }.labelsHidden().frame(width: 80)
                    Toggle("Follow", isOn: $follow).toggleStyle(.checkbox)
                    Spacer(minLength: 0)
                }
                Text("\(clock(audio.currentTime)) / \(clock(audio.duration)) · Closing this window keeps audio playing")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
                .background(.regularMaterial)
        }
        .frame(minWidth: 530, minHeight: 330)
        .preferredColorScheme(background.scheme)
    }

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Reader appearance").font(.headline)
                Spacer()
                Button { showAppearance = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close appearance controls")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Font size")
                    Spacer()
                    Text("\(Int(readingFontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $fontSize, in: 14...40, step: 1)
                    .accessibilityLabel("Reader font size")
            }
            Picker("Highlight color", selection: $colorRaw) {
                ForEach(ReaderHighlightColor.allCases) { color in
                    Text(color.label).tag(color.rawValue)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Highlight intensity")
                    Spacer()
                    Text("\(Int(highlightOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $highlightOpacity, in: 0.15...0.75, step: 0.05)
                    .accessibilityLabel("Highlight intensity")
            }
            Picker("Background", selection: $backgroundRaw) {
                ForEach(ReaderBackground.allCases) { background in
                    Text(background.label).tag(background.rawValue)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Background opacity")
                    Spacer()
                    Text("\(Int(backgroundOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $backgroundOpacity, in: 0.25...1, step: 0.05)
                    .accessibilityLabel("Reader background opacity")
                Text("Lower values reveal windows behind the text. Text and controls stay fully visible.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Changes apply immediately and are saved.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    fontSize = 20
                    colorRaw = ReaderHighlightColor.yellow.rawValue
                    highlightOpacity = 0.38
                    backgroundRaw = ReaderBackground.system.rawValue
                    backgroundOpacity = 1
                }.help("Restore the default appearance")
            }
        }
        .padding(20).frame(width: 350)
        .preferredColorScheme(background.scheme)
    }

    private func clock(_ value: Double) -> String {
        let seconds = Int(max(0, value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func styled(_ sentence: ReaderSentence) -> AttributedString {
        var attr = AttributedString(sentence.text)
        guard let active, NSIntersectionRange(active.range, sentence.range).length > 0 else { return attr }
        let overlap = NSIntersectionRange(active.range, sentence.range)
        let range = sentenceMode ? NSRange(location: 0, length: (sentence.text as NSString).length)
            : NSRange(location: overlap.location - sentence.range.location, length: overlap.length)
        if let swift = Range(range, in: sentence.text),
           let lo = AttributedString.Index(swift.lowerBound, within: attr),
           let hi = AttributedString.Index(swift.upperBound, within: attr) {
            let color = (ReaderHighlightColor(rawValue: colorRaw) ?? .yellow).color
            attr[lo..<hi].backgroundColor = color.opacity(min(0.75, max(0.15, highlightOpacity)))
            attr[lo..<hi].foregroundColor = background.textColor
        }
        return attr
    }
}
