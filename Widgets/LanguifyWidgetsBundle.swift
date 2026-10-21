import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LanguifyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ListeningLiveActivity()
    }
}

struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningActivityAttributes.self) { context in
            LockScreenListeningView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.status.label, systemImage: symbol(for: context.state.status))
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.rewindSeconds)s rewind")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let answer = context.state.lastAnswer {
                            Text(answer).font(.caption).lineLimit(2)
                        } else {
                            Text("Ask Siri: \u{201C}Ask Languify what that word meant\u{201D}")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button(intent: StopListeningIntent()) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .tint(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(for: context.state.status))
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }
}

private func symbol(for status: ListeningActivityAttributes.Status) -> String {
    switch status {
    case .listening: "waveform"
    case .paused: "pause.fill"
    case .interrupted: "mic.slash"
    case .processing: "ellipsis.bubble"
    }
}

private struct LockScreenListeningView: View {
    let context: ActivityViewContext<ListeningActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol(for: context.state.status))
                .font(.title2)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Languify \u{00B7} \(context.attributes.languageName)")
                    .font(.headline)
                Text(context.state.lastAnswer ?? "\(context.state.status.label) \u{00B7} keeping the last \(context.state.rewindSeconds) seconds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(intent: StopListeningIntent()) {
                Image(systemName: "stop.fill")
                    .accessibilityLabel("Stop listening")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }
}
