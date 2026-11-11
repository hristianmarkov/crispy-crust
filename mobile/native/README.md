# Native companion implementation status

These sources are real native implementations, but **they are not claimed integrated, signed, physically tested or store-ready**. Core phone baking does not depend on a watch. Device compatibility must be named after testing.

- `apple/Package.swift` provides versioned task/action models and XCTest cases. Run `swift test` on macOS (also in CI).
- `apple/project.yml` defines XcodeGen watch and Live Activity/widget targets. Run `xcodegen generate` in that folder, then build the resulting schemes in Xcode. The target identifiers and host embedding must be finalized for the owner-controlled Apple team. Add the widget extension to the Flutter Runner and start/update/end activities through an authorized phone bridge before advertising Live Activities as working.
- `apple/Watch` receives snapshots through WatchConnectivity and sends acknowledgement commands. It never marks a physical bake action complete itself; phone-side revision and operation-id checks must accept the action before confirming.
- `wearos` is a native Wear OS Gradle application receiving `/crispy/task` Data Layer snapshots and sending `/crispy/action` acknowledgements. Compile using the generated phone runner's Gradle wrapper with `-p mobile/native/wearos :app:assembleDebug`. Same package name/signing identity as the phone is required for Data Layer connectivity. Phone-side Data Layer transport and full acknowledgements require integration/physical validation.

The phone platform adapters and deterministic tests are under `apps/mobile/lib/platform` and `apps/mobile/test/platform`. Native phone runners are generated reproducibly by `scripts/bootstrap.sh`, then configured by `scripts/configure_platforms.py`. That script installs the notification boot receivers, point-of-use permission declarations, exact auth callback, privacy descriptions, busy-time-only calendar bridge and keep-awake bridge. It does not register paid services or create store identities.

Permission denied, unsupported platform, stale sensor/watch data and missing cloud configuration are explicit states. Local notification delivery remains subject to OS permissions, Focus/DND, battery behaviour, device power and Android force-stop. No unattended background camera or universal probe/watch support is claimed.

Outstanding physical/owner gates: Apple/Google signing/accounts; named minimum/device matrix; notification denial/reboot/OEM tests; app-group/extension provisioning; BLE model/protocol verification; watch pairing/reconnect/stale/replay tests; production backend URL/publishable key; OAuth provider/sender/redirect setup. No production account keys belong in source.
