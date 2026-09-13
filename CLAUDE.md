Read PROP_HANDOFF.md before doing anything.
Project: Lantern.xcodeproj, scheme "Lantern", package LanternCore.
Build with: xcodebuild -scheme Lantern -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
Test LanternCore with: swift test --package-path Packages/LanternCore
Prefer the Xcode MCP bridge for builds and diagnostics when available.
Commit small, conventional messages. Don't touch signing settings.
