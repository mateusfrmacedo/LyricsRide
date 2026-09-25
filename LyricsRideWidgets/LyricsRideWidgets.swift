import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
@main
struct LyricsRideWidgets: WidgetBundle {
    var body: some Widget {
        LyricsRideHomeWidget()
        LyricsRideLiveActivity()
    }
}

/// A normal Home Screen widget. Unlike the Live Activity it refreshes only
/// when the app sends a new snapshot, respecting the system widget budget.
@available(iOS 18.0, *)
struct LyricsRideHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LyricsRideWidgetStore.kind, provider: LyricsRideHomeProvider()) { entry in
            LyricsRideHomeView(state: entry.state)
        }
        .configurationDisplayName("Lyrics Ride")
        .description("Veja a música e a última linha sincronizada.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@available(iOS 18.0, *)
private struct LyricsRideHomeEntry: TimelineEntry {
    let date: Date
    let state: WidgetMusicState
}

@available(iOS 18.0, *)
private struct LyricsRideHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricsRideHomeEntry {
        LyricsRideHomeEntry(date: .now, state: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsRideHomeEntry) -> Void) {
        completion(LyricsRideHomeEntry(date: .now, state: LyricsRideWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsRideHomeEntry>) -> Void) {
        let entry = LyricsRideHomeEntry(date: .now, state: LyricsRideWidgetStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

@available(iOS 18.0, *)
private struct LyricsRideHomeView: View {
    let state: WidgetMusicState
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                small
            case .systemLarge:
                large
            default:
                medium
            }
        }
        .containerBackground(.black.gradient, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: state.isPlaying ? "music.note" : "music.note.house")
                .foregroundStyle(.pink)
            Spacer(minLength: 0)
            Text(state.currentLine.isEmpty ? "Lyrics Ride" : state.currentLine)
                .font(.headline)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(state.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding()
    }

    private var medium: some View {
        HStack(spacing: 14) {
            Image(systemName: state.isPlaying ? "waveform" : "music.note")
                .font(.title)
                .foregroundStyle(.pink)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text(state.title).font(.headline).lineLimit(1)
                Text(state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(state.currentLine)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.isPlaying ? "Tocando agora" : "Lyrics Ride", systemImage: state.isPlaying ? "waveform" : "music.note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                Spacer()
                Text(state.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(state.previousLine ?? " ")
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(state.currentLine)
                .font(.title2.bold())
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(state.nextLine ?? " ")
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding()
    }
}

@available(iOS 18.0, *)
struct LyricsRideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LockScreenLyricsView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.22))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LyricsTrioView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(.pink)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(.pink)
            }
        }
        // CarPlay uses the small family. Without this opt-in, iOS combines
        // the compact Dynamic Island icon views and no lyric text is shown.
        .supplementalActivityFamilies([.small])
    }
}

@available(iOS 18.0, *)
private struct LockScreenLyricsView: View {
    let state: LyricsActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        Group {
            if family == .small {
                CarPlayLyricsView(state: state)
            } else {
                LockScreenLyricsContent(state: state)
                    // The lyric chooses its natural height. This avoids clipping
                    // words just to hold the card at a fixed height; iOS still
                    // determines the final available Live Activity space.
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
        }
    }
}

/// The CarPlay Dashboard tile has little room. Prioritize the line being sung
/// and the next one instead of reusing the iPhone's three-line Lock Screen UI.
@available(iOS 18.0, *)
private struct CarPlayLyricsView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.lyric)
                .id(state.lyric)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
            Text(state.nextLyric ?? "")
                .id(state.nextLyric)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .animation(.easeInOut(duration: 0.45), value: state.lyric)
    }
}

@available(iOS 18.0, *)
private struct LockScreenLyricsContent: View {
    let state: LyricsActivityAttributes.ContentState

    private var highContrast: Bool { state.highContrast ?? false }
    private var showsThreeLines: Bool { state.displayLineCount != 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsThreeLines, let previous = state.previousLyric, !previous.isEmpty {
                lyricText(previous, size: 18, color: .white.opacity(highContrast ? 0.82 : 0.52))
                    .contentTransition(.opacity)
            }

            lyricText(state.lyric, size: 26, color: .white, weight: .bold)
                .id(state.lyricTimestamp ?? state.position)
                .contentTransition(.opacity)

            if showsThreeLines, let next = state.nextLyric, !next.isEmpty {
                lyricText(next, size: 18, color: .white.opacity(highContrast ? 0.9 : 0.68))
                    .id(state.nextTimestamp.map { String(describing: $0) } ?? state.nextLyric)
                    .transition(.push(from: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.45), value: state.lyricTimestamp ?? state.position)
    }

    private func lyricText(_ text: String, size: CGFloat, color: Color, weight: Font.Weight = .medium) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            // Do not set lineLimit or a fixed height: every word remains visible.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 18.0, *)
private struct LyricsTrioView: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.previousLyric ?? " ")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                .contentTransition(.opacity)

            Text(state.lyric)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70, alignment: .leading)
                .contentTransition(.opacity)

            Text(state.nextLyric ?? "")
                .id(state.nextTimestamp.map { String($0) } ?? state.nextLyric ?? "")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
                .truncationMode(.tail)
                .transition(.push(from: .bottom))
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.5), value: state.lyricTimestamp ?? state.position)
    }
}
