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

private struct TickedActivityData {
  let filmTitle: String
  let cinemaLabel: String
  let label: String
  let targetDate: Date
  let posterPath: String

  init(context: ActivityViewContext<LiveActivitiesAppAttributes>) {
    let defaults = UserDefaults(suiteName: "group.com.example.finalProjectt.liveactivity")
    let key = context.attributes.prefixedKey

    filmTitle = defaults?.string(forKey: key("filmTitle")) ?? "Ticked"
    cinemaLabel = defaults?.string(forKey: key("cinemaLabel")) ?? ""
    label = defaults?.string(forKey: key("label")) ?? "TIME REMAINING"
    posterPath = defaults?.string(forKey: key("posterPath")) ?? ""
    
let iso = defaults?.string(forKey: key("targetDate"))
let isoFormatter = ISO8601DateFormatter()
isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
targetDate = iso.flatMap { isoFormatter.date(from: $0) } ?? Date()
  }

  /// Text(timerInterval:) needs a ClosedRange<Date> whose lower bound is
  /// never after its upper bound. Only the upper bound (targetDate)
  /// actually affects what a countsDown timer displays, so a fixed,
  /// far-past lower bound keeps the range valid no matter when this is
  /// read, without needing to know when the phase actually started.
  var countdownRange: ClosedRange<Date> {
    Date.distantPast...targetDate
  }
}

// MARK: - Lock Screen presentation
//
// "Ticket Stub" design: film identity on the left, a dashed perforation,
// then a fixed-width countdown "stub" on the right. Matches the approved
// design handoff, adapted to Ticked's actual data: no poster pipeline
// yet (design itself hides the poster gracefully when absent), no
// hall/seat (Ticked doesn't do seat selection), and the existing 4-phase
// labels (TRUE START IN / NEXT SAFE BREAK IN / etc.) fill the label slot
// instead of the mockup's TRUE START / LEAVE NOW two-state version.

private struct DashedPerforation: View {
  var body: some View {
    GeometryReader { geo in
      Path { path in
        path.move(to: CGPoint(x: 1, y: 0))
        path.addLine(to: CGPoint(x: 1, y: geo.size.height))
      }
      .stroke(Color.tickedGold.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
    }
    .frame(width: 2)
  }
}

private struct TickedLockScreenView: View {
  let data: TickedActivityData

  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: 12) {
        if !data.posterPath.isEmpty, let posterImage = UIImage(contentsOfFile: data.posterPath) {
          Image(uiImage: posterImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 46, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        VStack(alignment: .leading, spacing: 7) {
          Text(data.filmTitle)
            .font(.system(size: 21, weight: .heavy))
            .kerning(0.3)
            .foregroundStyle(Color.tickedTextPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
          if !data.cinemaLabel.isEmpty {
            Text(data.cinemaLabel)
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(Color.tickedTextTertiary.opacity(0.78))
              .lineLimit(1)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)

      DashedPerforation()

      VStack(spacing: 6) {
        Text(data.label)
          .font(.system(size: 9.5, weight: .semibold))
          .kerning(1.4)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .minimumScaleFactor(0.85)
          .foregroundStyle(Color.tickedTextTertiary)
        Text(timerInterval: data.countdownRange, countsDown: true)
          .font(.system(size: 21, weight: .bold, design: .monospaced))
          .foregroundStyle(Color.tickedGold)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 14)
      .frame(width: 104)
      .background(Color.black.opacity(0.18))
    }
    .frame(height: 108)
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
            Text(timerInterval: data.countdownRange, countsDown: true)
              .font(.system(size: 16, weight: .bold, design: .monospaced))
              .foregroundStyle(Color.tickedGold)
          }
        }
      } compactLeading: {
        Image(systemName: "film.fill")
          .foregroundStyle(Color.tickedGold)
      } compactTrailing: {
        Text(timerInterval: data.countdownRange, countsDown: true)
          .font(.system(size: 13, weight: .bold, design: .monospaced))
          .foregroundStyle(Color.tickedGold)
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
