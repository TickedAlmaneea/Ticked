# Live Activity setup checklist (do this in Xcode / Terminal, not from Claude)

Everything Claude could automate is already done: `live_activities` is in
pubspec.yaml, the iOS deployment target is bumped to 16.1, and
`lib/services/live_activity_service.dart` is wired into the Schedule Card's
start/tick/end. `TickedLiveActivity.swift` in this same folder is the
widget's full source, ready to drop in.

The rest genuinely has to happen in Xcode's GUI and your Apple ID — there's
no safe way to script a new Xcode target from the outside without risking
the project file.

1. Run `flutter pub get` in the project root.
2. Open `ios/Runner.xcworkspace` (not `.xcodeproj`) in Xcode.
3. File > New > Target… > iOS > Widget Extension.
   - Product Name: `TickedWidget`
   - Check "Include Live Activity" if Xcode offers the checkbox.
   - Uncheck "Include Configuration App Intent" (not needed).
   - Embed in Application: Runner. Finish, then "Activate" the new scheme
     when prompted.
4. In the new `TickedWidget` group Xcode created: delete the placeholder
   `.swift` files Xcode generated (keep `Assets.xcassets`, `Info.plist`,
   the entitlements file). Drag `TickedLiveActivity.swift` from this
   folder into that group instead.
5. Select the `TickedWidget` target > Build Settings > set
   iOS Deployment Target to `16.1` (match Runner's).
6. Signing & Capabilities:
   - **Runner** target: `+ Capability` > Push Notifications.
   - **Runner** target: `+ Capability` > App Groups > `+` > create
     `group.com.example.finalProjectt.liveactivity` > check it on.
   - **TickedWidget** target: `+ Capability` > App Groups > check the
     *same* `group.com.example.finalProjectt.liveactivity` (don't create
     a second one).
7. Info.plist — add this key set to **both** Runner's and TickedWidget's
   Info.plist (Xcode's "Include Live Activity" checkbox may already have
   added it to TickedWidget's):
   ```xml
   <key>NSSupportsLiveActivities</key>
   <true/>
   ```
8. Build and run on a real device, or an iOS 16.2+ Simulator (Simulator
   shows the Lock Screen/Dynamic Island fine for a demo; a real device is
   more convincing since you can actually lock the phone).
9. Start a live session from the Schedule Card, then lock the phone (or on
   Simulator: Device menu). The Lock Screen card and Dynamic Island should
   show the film, cinema, and a live countdown.

If it doesn't appear: double-check the App Group string is typed
*identically* in step 6 (both targets), in `TickedLiveActivity.swift`, and
in `_appGroupId` inside `live_activity_service.dart` — one typo anywhere
in those four places is the most common reason nothing shows up.

Once you've done steps 1–7, tell Claude and it can help debug anything
that doesn't build or doesn't show up.
