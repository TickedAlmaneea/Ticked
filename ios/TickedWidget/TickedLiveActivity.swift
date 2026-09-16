import ActivityKit
import WidgetKit
import SwiftUI
import UIKit

// MARK: - Attributes
//
// This struct's name is a hard requirement of the `live_activities`
// Flutter plugin — it must be exactly "LiveActivitiesAppAttributes" or
// activities created from Dart silently never appear. ContentState is
// deliberately empty: the plugin doesn't push typed fields through
// ActivityKit's own content state, it writes every field Dart passes to
// createActivity/updateActivity into the shared App Group's UserDefaults
// instead, keyed by this activity's id — see TickedActivityData below.

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  public struct ContentState: Codable, Hashable {}
  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    return "\(id)_\(key)"
  }
}

// MARK: - Ticked's palette, mirrored from lib/constants/app_colors.dart
// (a widget extension can't import the app's Dart constants, so these
// are the same hex values by hand — keep them in sync if the palette
// in app_colors.dart ever changes).

private extension Color {
  static let tickedBg = Color(red: 0x07 / 255, green: 0x04 / 255, blue: 0x02 / 255)
  static let tickedGold = Color(red: 0xEE / 255, green: 0xB1 / 255, blue: 0x54 / 255)
  static let tickedTextPrimary = Color(red: 0xF3 / 255, green: 0xEE / 255, blue: 0xE6 / 255)
  static let tickedTextTertiary = Color(red: 0x95 / 255, green: 0x8E / 255, blue: 0x88 / 255)
}

// MARK: - Reading Dart's data out of the shared App Group
//
// IMPORTANT: "group.com.example.finalProjectt.liveactivity" below must be
// typed identically here, in LiveActivityService's _appGroupId constant
// (lib/services/live_activity_service.dart), and in the App Groups
// capability on BOTH the Runner and this widget extension's target in
// Xcode's Signing & Capabilities tab. A mismatch anywhere in those four
// places means the widget reads nothing and falls back to the defaults
// below, silently.

/// One moment on the evening's rail -- ads starting, true start, a safe
/// break, credits, a credit scene, or the movie ending.
private struct WidgetBeat: Identifiable {
  let label: String
  let date: Date
  var id: String { "\(label)_\(date.timeIntervalSince1970)" }
}

/// Parses "LABEL@isoDate|LABEL@isoDate|..." -- "@" rather than ":" as the
/// separator because the ISO date itself contains colons.
private func parseBeats(_ raw: String, using isoFormatter: ISO8601DateFormatter) -> [WidgetBeat] {
  guard !raw.isEmpty else { return [] }
  return raw.split(separator: "|").compactMap { chunk -> WidgetBeat? in
    let parts = chunk.split(separator: "@", maxSplits: 1)
    guard parts.count == 2, let date = isoFormatter.date(from: String(parts[1])) else { return nil }
    return WidgetBeat(label: String(parts[0]), date: date)
  }
}

private struct TickedActivityData {
  let filmTitle: String
  let cinemaLabel: String
  let label: String
  let posterPath: String
  /// Plain text to display as-is: the frozen clock time before the real
  /// start arrives ("5:55 PM"), or a live "H:MM:SS"/"MM:SS" count down
  /// once the session is under way. Deliberately not a native
  /// `Text(timerInterval:)` -- that mechanism proved unreliable here,
  /// repeatedly rendering blank (taking the rest of the view down with
  /// it) both at creation and at the pre-show-to-live transition. This
  /// is refreshed by a fresh push from the app every second once live.
  let countdownText: String
  /// Ads, true start, each safe break, credits/scene (when known) and
  /// the movie's end, in order -- drawn as the rail below the header.
  let beats: [WidgetBeat]

  init(context: ActivityViewContext<LiveActivitiesAppAttributes>) {
    let defaults = UserDefaults(suiteName: "group.com.example.finalProjectt.liveactivity")
    let key = context.attributes.prefixedKey
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    filmTitle = defaults?.string(forKey: key("filmTitle")) ?? "Ticked"
    cinemaLabel = defaults?.string(forKey: key("cinemaLabel")) ?? ""
    label = defaults?.string(forKey: key("label")) ?? "TIME REMAINING"
    posterPath = defaults?.string(forKey: key("posterPath")) ?? ""
    countdownText = defaults?.string(forKey: key("countdownText")) ?? "--:--"
    beats = parseBeats(defaults?.string(forKey: key("beats")) ?? "", using: isoFormatter)
  }
}

// MARK: - Lock Screen presentation
//
// "Departure Board" design: a header row (poster, title/meta, big
// countdown + phase label), then a rail of every beat in the evening --
// ads, true start, each safe break, credits/scene when known, and the
// end -- as dots on a line. Only the beat just passed and the one coming
// up next get a time + label under them; the rest are just dots, so the
// rail stays legible no matter how many beats a given film has.

private struct BeatRailView: View {
  let beats: [WidgetBeat]
  let now: Date

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("h:mm")
    return f
  }()

  /// Index of the first beat still ahead of us -- everything before it
  /// has passed. `beats.count` when every beat is already behind.
  private var nextIndex: Int {
    beats.firstIndex(where: { $0.date > now }) ?? beats.count
  }

  var body: some View {
    let next = nextIndex
    HStack(alignment: .top, spacing: 0) {
      ForEach(Array(beats.enumerated()), id: \.element.id) { index, beat in
        let passed = index < next
        let isEdge = index == next - 1 || index == next
        VStack(spacing: 4) {
          HStack(spacing: 0) {
            Circle()
              .fill(passed ? Color.tickedGold : Color.tickedTextTertiary.opacity(0.35))
              .frame(width: 6, height: 6)
            if index < beats.count - 1 {
              Rectangle()
                .fill(passed ? Color.tickedGold.opacity(0.35) : Color.tickedTextTertiary.opacity(0.25))
                .frame(height: 1)
            }
          }
          if isEdge {
            Text(Self.timeFormatter.string(from: beat.date))
              .font(.system(size: 9, weight: .medium, design: .monospaced))
              .foregroundStyle(passed ? Color.tickedTextPrimary.opacity(0.9) : Color.tickedTextTertiary.opacity(0.85))
              .lineLimit(1)
            Text(beat.label)
              .font(.system(size: 8, weight: .semibold))
              .kerning(0.7)
              .foregroundStyle(passed ? Color.tickedGold : Color.tickedTextTertiary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          } else {
            // Keeps every column the same height whether or not it
            // carries a label, so the dots all stay lined up.
            Color.clear.frame(height: 21)
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
  }
}

private struct TickedLockScreenView: View {
  let data: TickedActivityData

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        if !data.posterPath.isEmpty, let posterImage = UIImage(contentsOfFile: data.posterPath) {
          Image(uiImage: posterImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 34, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(data.filmTitle)
            .font(.system(size: 19, weight: .heavy))
            .kerning(0.2)
            .foregroundStyle(Color.tickedTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          if !data.cinemaLabel.isEmpty {
            Text(data.cinemaLabel)
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(Color.tickedTextTertiary.opacity(0.78))
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .trailing, spacing: 2) {
          Text(data.countdownText)
            .font(.system(size: 27, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.tickedGold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize()

          Text(data.label)
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(1.2)
            .foregroundStyle(Color.tickedTextTertiary)
            .fixedSize()
        }
      }

      if !data.beats.isEmpty {
        VStack(spacing: 10) {
          Rectangle()
            .fill(Color.tickedGold.opacity(0.14))
            .frame(height: 1)
          BeatRailView(beats: data.beats, now: Date())
        }
      }
    }
    .padding(16)
    .activityBackgroundTint(Color.tickedBg)
    .activitySystemActionForegroundColor(Color.tickedTextPrimary)
  }
}

// MARK: - Widget + Dynamic Island

struct TickedLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      TickedLockScreenView(data: TickedActivityData(context: context))
    } dynamicIsland: { context in
      let data = TickedActivityData(context: context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(data.filmTitle)
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(Color.tickedTextPrimary)
              .lineLimit(1)
            Text(data.cinemaLabel)
              .font(.system(size: 11))
              .foregroundStyle(Color.tickedTextTertiary)
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(data.label)
              .font(.system(size: 9, weight: .semibold))
              .tracking(1.0)
              .foregroundStyle(Color.tickedTextTertiary)
            Text(data.countdownText)
              .font(.system(size: 16, weight: .bold, design: .monospaced))
              .foregroundStyle(Color.tickedGold)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
        }
      } compactLeading: {
        Image(systemName: "film.fill")
          .foregroundStyle(Color.tickedGold)
      } compactTrailing: {
        Text(data.countdownText)
          .font(.system(size: 13, weight: .bold, design: .monospaced))
          .foregroundStyle(Color.tickedGold)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(maxWidth: 44)
      } minimal: {
        Image(systemName: "film.fill")
          .foregroundStyle(Color.tickedGold)
      }
      .keylineTint(Color.tickedGold)
    }
  }
}

@main
struct TickedWidgetBundle: WidgetBundle {
  var body: some Widget {
    TickedLiveActivity()
  }
}
