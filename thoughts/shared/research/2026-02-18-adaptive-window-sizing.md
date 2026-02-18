---
date: 2026-02-18T17:38:48Z
researcher: Blake McAnally
git_commit: cec247e54f4927880bba41f04506555a07029006
branch: main
repository: pr-status-watcher
topic: "Adaptive window sizing: ContentView and SettingsView frame constants, Dynamic Type, accessibility, and content-aware sizing"
tags: [research, codebase, layout, accessibility, dynamic-type, window-sizing, MenuBarExtra]
status: complete
last_updated: 2026-02-18
last_updated_by: Blake McAnally
last_updated_note: "Added follow-up research on @ScaledMetric, Dynamic Type on macOS, and practical options"
---

# Research: Adaptive Window Sizing

**Date**: 2026-02-18T17:38:48Z
**Researcher**: Blake McAnally
**Git Commit**: cec247e54f4927880bba41f04506555a07029006
**Branch**: main
**Repository**: pr-status-watcher

## Research Question

ContentView and SettingsView use centralized frame constants but don't adapt to Dynamic Type, accessibility settings, or content amount. What exists today, what are the platform constraints, and what would adaptation involve?

## Summary

The app uses a centralized `AppConstants.Layout` enum in `Constants.swift` to define fixed min/ideal/max width and height values for both the ContentView (MenuBarExtra window) and SettingsView (standalone Window). These constants are pure `CGFloat` values that do not respond to Dynamic Type, accessibility text size, or content volume. The app has good coverage of `.accessibilityLabel` and `.accessibilityHint` modifiers, but zero usage of `@ScaledMetric`, `@Environment(\.dynamicTypeSize)`, `@Environment(\.accessibilityReduceMotion)`, or any other responsive sizing APIs. Most fonts use semantic Dynamic Type styles (`.caption`, `.title3`, `.headline`), but a handful use fixed point sizes. The MenuBarExtra window style has inherent platform limitations around adaptive sizing — it doesn't support `windowResizability`, doesn't animate resizes, and macOS itself doesn't automatically propagate Text Size accessibility settings to SwiftUI views.

## Detailed Findings

### 1. Window Architecture

The app has two window surfaces:

- **ContentView** — hosted inside a `MenuBarExtra` with `.menuBarExtraStyle(.window)` (`App.swift:51-61`). This is a floating panel that appears from the menu bar. The window sizes itself from its content's `.frame()` modifiers.

- **SettingsView** — hosted in a standalone `Window("Settings", id: "settings")` with `.windowResizability(.contentSize)` and `.defaultPosition(.center)` (`App.swift:63-68`). This is a standard macOS window whose resize range is constrained by the content's frame modifiers.

### 2. Centralized Frame Constants

All layout constants live in `Sources/App/Constants.swift`:

```
AppConstants.Layout.ContentWindow:
  minWidth:   400    idealWidth:   460    maxWidth:   560
  minHeight:  400    idealHeight:  520    maxHeight:  700

AppConstants.Layout.SettingsWindow:
  minWidth:   320    idealWidth:   380    maxWidth:   480
  minHeight:  520    idealHeight:  620    maxHeight:  800

AppConstants.Layout.Header.tabPickerWidth: 180

AppConstants.Layout.MenuBar:
  imageSize:       NSSize(20, 16)
  badgeDotDiameter: 5
  symbolPointSize:  14
  statusFontSize:   11
```

**Consumers:**

| Constant Group | Consumer | Location |
|---------------|----------|----------|
| `ContentWindow.*` | `ContentView.body` | `ContentView.swift:94-101` |
| `SettingsWindow.*` | `SettingsView.body` | `SettingsView.swift:381-388` |
| `Header.tabPickerWidth` | Tab picker frame | `ContentView.swift:118` |
| `MenuBar.statusFontSize` | Menu bar label | `App.swift:58` |
| `MenuBar.symbolPointSize` | Menu bar icon | `PRManager.swift:183` |
| `MenuBar.imageSize` | Menu bar image | `PRManager.swift:196` |
| `MenuBar.badgeDotDiameter` | Badge dot | `PRManager.swift:205` |

### 3. Font Sizing Patterns

**Semantic (Dynamic Type-compatible) fonts** — the majority of the codebase:

| Style | Usage Locations |
|-------|----------------|
| `.title2.weight(.semibold)` | SettingsView header |
| `.title3` / `.title3.weight(.semibold)` | ContentView header icon, empty state titles |
| `.headline` | SettingsView section headers |
| `.body` / `.body.weight(.medium)` | PRRowView title, AuthStatusView, refresh button |
| `.caption` / `.caption.weight(.semibold)` | Repo names, section headers, auth views, inline labels |
| `.caption2` / `.caption2.weight(.medium)` | Footer labels, badge pills, status counts |
| `.system(.caption, design: .monospaced)` | Check names, SHA text, auth command |
| `.system(.body, design: .default)` | PR title in PRRowView |

**Fixed-size fonts** — 4 instances:

| Size | File | Purpose |
|------|------|---------|
| `.system(size: 32)` | `ContentView.swift:421,445,467` | Empty state SF Symbol icons |
| `.system(size: 7)` | `PRRowView.swift:95` | External link icon in failed checks |
| `.system(size: 7, weight: .bold)` | `PRRowView.swift:220` | Chevron icon in CI badge |
| `.system(size: 11, ...)` | `App.swift:58` (via constant) | Menu bar status text |

### 4. Fixed Dimension Inventory (Non-Constant)

Beyond `AppConstants`, these inline fixed values exist in view code:

| Value | Context | Files |
|-------|---------|-------|
| `6 × 6` | Status dots (readiness, repo headers) | ContentView |
| `10 × 10` | PR row status dot | PRRowView |
| `60` | SLA value TextField width | SettingsView |
| `140` | SLA unit Picker width | SettingsView |
| `36` | Divider leading padding (aligns with PR content) | ContentView |
| `16` | Horizontal padding (headers, rows, footer) | ContentView, PRRowView |
| `24` | Content padding (empty state text, settings) | ContentView, SettingsView |
| `8`, `12` | Vertical padding (rows, headers) | ContentView, PRRowView |
| `4` | Corner radius, small spacing | Multiple views |

### 5. Accessibility Feature Coverage

**Present:**

| Feature | Coverage |
|---------|----------|
| `.accessibilityLabel` | Comprehensive — every interactive element, empty states, auth status |
| `.accessibilityHint` | Collapsible sections, PR rows, settings toggles |
| `.accessibilityHidden(true)` | Decorative status dot in PRRowView |
| `.help()` tooltips | Footer items, refresh button, settings button |
| `NSImage accessibilityDescription` | Menu bar icon |

**Absent:**

| Feature | Current Usage |
|---------|--------------|
| `@ScaledMetric` | None |
| `@Environment(\.dynamicTypeSize)` | None |
| `@Environment(\.sizeCategory)` | None |
| `@Environment(\.accessibilityReduceMotion)` | None |
| `@Environment(\.accessibilityReduceTransparency)` | None |
| `.dynamicTypeSize()` modifier | None |
| `ContentSizeCategory` | None |
| `NSFont.preferredFont` | None |

### 6. MenuBarExtra Platform Constraints

The MenuBarExtra window style (`.menuBarExtraStyle(.window)`) has specific limitations relevant to adaptive sizing:

| Constraint | Impact |
|-----------|--------|
| **No `windowResizability` support** | This scene modifier only applies to `Window`/`WindowGroup`, not MenuBarExtra. The MenuBarExtra window sizes from its content's `.frame()` modifiers. |
| **No animated resizing** | When content changes size, the window jumps rather than animating. Third-party libraries like FluidMenuBarExtra exist to address this. |
| **No automatic Dynamic Type** | macOS 14 added a "Text Size" accessibility setting, but native SwiftUI/AppKit apps do not automatically respond to it. Manual observation of `com.apple.universalaccess` UserDefaults is required. |
| **`idealWidth`/`idealHeight` behavior undocumented** | Practical documentation for MenuBarExtra only shows fixed `.frame(width:height:)`. How min/ideal/max constraints interact with the floating panel is not officially documented. |
| **No programmatic show/hide** | Cannot open/close the MenuBarExtra window from code (relevant for accessibility shortcuts). |

### 7. Settings Window Platform Constraints

The Settings window uses `.windowResizability(.contentSize)` (`App.swift:67`), which means:

- The window **can be resized** by the user within the min/max bounds set by the content's `.frame()` modifiers.
- Currently those bounds are `320–480` wide and `520–800` tall (from `AppConstants.Layout.SettingsWindow`).
- The SettingsView content is wrapped in a `ScrollView`, so vertical overflow is handled gracefully — content scrolls when it exceeds the window height.
- `.contentSize` resizability would respect changes to content size if the frame constraints were dynamic, but currently they are static `CGFloat` constants.

### 8. Content Amount Sensitivity

**ContentView** handles varying content amounts through:
- `ScrollView` + `LazyVStack` for PR lists (line 157-164, 173-204)
- Multiple empty states (loading, no PRs, all repos ignored, all filtered)
- Collapsible sections (readiness groups, repo groups)
- But: the window height range is fixed (400-700pt) regardless of whether there are 2 PRs or 50

**SettingsView** handles varying content through:
- `ScrollView` wrapping all settings content (line 27)
- Conditional SLA configuration section (only shown when SLA is enabled)
- Dynamic lists for required checks, ignored checks, and ignored repos
- But: the window height range is fixed (520-800pt) even when all lists are empty

## Code References

- `Sources/App/Constants.swift` — Centralized layout constants
- `Sources/App/ContentView.swift:94-101` — ContentView frame modifiers consuming constants
- `Sources/App/SettingsView.swift:381-388` — SettingsView frame modifiers consuming constants
- `Sources/App/App.swift:50-68` — Window scene configuration (MenuBarExtra + Settings Window)
- `Sources/App/PRRowView.swift` — PR row with fixed 10×10 dot, fixed 7pt fonts
- `Sources/App/AuthStatusView.swift` — Auth status (semantic fonts only)
- `Sources/App/PRManager.swift:163,183-211` — Menu bar image rendering with fixed NSSize/CGFloat

## Architecture Documentation

### Current Sizing Architecture

```
AppConstants.Layout (static CGFloat values)
    ├── ContentWindow.{min,ideal,max}{Width,Height}
    │       └── ContentView.body .frame() modifier
    │               └── MenuBarExtra(.window) — sizes from content
    │
    ├── SettingsWindow.{min,ideal,max}{Width,Height}
    │       └── SettingsView.body .frame() modifier
    │               └── Window(.contentSize) — constrains resize range
    │
    ├── Header.tabPickerWidth
    │       └── ContentView tab Picker .frame(width:)
    │
    └── MenuBar.{imageSize,badgeDotDiameter,symbolPointSize,statusFontSize}
            └── PRManager.buildMenuBarImage() / App.swift label
```

All sizing flows from compile-time constants through `.frame()` modifiers. No runtime adaptation occurs based on text size, accessibility settings, or content volume.

### Existing Accessibility Architecture

The app has a "labels and hints" accessibility model — it annotates what things are and how to interact with them for screen readers, but doesn't adapt the visual presentation for different accessibility needs. The separation between "screen reader support" (present) and "visual accessibility" (absent) is clean.

## Related Research

- `thoughts/shared/plans/2026-02-11-p3-low-impact-bugfixes.md` — Previously identified adaptive window sizing as a low-priority item
- `thoughts/shared/plans/2026-02-17-ready-not-ready-review-sections.md` — Readiness sections that added more content to ContentView

## Open Questions

1. **MenuBarExtra ideal size behavior** — How exactly does SwiftUI resolve `idealWidth`/`idealHeight` in a MenuBarExtra window? The actual runtime behavior is undocumented by Apple.

---

## Follow-up Research: @ScaledMetric, Dynamic Type, and Practical Options (2026-02-18)

### @ScaledMetric on macOS: Effectively a No-Op

`@ScaledMetric` is available on macOS 11+, but on macOS it **always returns the base value**. The reason:

- `@ScaledMetric` scales relative to the current `dynamicTypeSize` environment value.
- On macOS, `dynamicTypeSize` is **always** `.large` (the default). Users cannot change it.
- At `.large`, the scaling factor is 1.0, so the value is unchanged.

Similarly, `@Environment(\.dynamicTypeSize)` and `@Environment(\.sizeCategory)` always return their default values on macOS. They are not driven by any system setting.

**Source:** [SwiftUI Field Guide – Dynamic Type](https://www.swiftuifieldguide.com/layout/dynamic-type/) — "Dynamic Type is not yet supported on macOS."
**Source:** [Stack Overflow – macOS 14 Sonoma Text Size](https://stackoverflow.com/questions/77937271/how-to-respond-to-the-new-text-size-setting-in-macos-14-sonoma)

### macOS Does Not Have Dynamic Type for Third-Party Apps

macOS 14 Sonoma introduced a "Text Size" slider under Settings → Accessibility → Display. However:

- This slider **only affects Apple's own apps** (Finder, Mail, Notes, Xcode, Settings, Messages, Calendar) via private/internal APIs.
- Third-party SwiftUI and AppKit apps **do not automatically respond** to this setting.
- `NSFont.preferredFont(forTextStyle:)` returns fixed sizes on macOS and does not honor the Text Size setting.
- There is no `UIContentSizeCategory.didChangeNotification` equivalent on macOS.
- Mac Catalyst apps that scale on iOS do **not** scale on macOS.
- This is unchanged through macOS 15 Sequoia and no evidence of change in macOS 16 Tahoe.

### Semantic Fonts vs Fixed Fonts: No Runtime Difference on macOS

On macOS, `.font(.caption)` and `.font(.system(size: 12))` are **both effectively fixed**. Neither responds to the system Text Size slider. The practical difference:

- Semantic styles (`.caption`, `.body`, `.title3`) express intent and will automatically benefit if Apple ever adds Dynamic Type to macOS.
- Fixed-size fonts (`.system(size: 7)`, `.system(size: 32)`) are explicit about their intent and won't unexpectedly change.
- For code clarity and future-proofing, semantic styles are preferable where the intent matches a text style.

### The Sonoma Text Size Values

The Text Size slider stores values in `com.apple.universalaccess` → `FontSizeCategory` → `global`:

| Value | Text Size | Notes |
|-------|-----------|-------|
| XXXS | 9pt | |
| XXS | 10pt | |
| XS | 11pt | |
| S | 12pt | |
| DEFAULT | 11pt | Default system value |
| M | 13pt | |
| L | 14pt | |
| XL | 15pt | |
| XXL | 16pt | |
| XXXL | 17pt | |
| AX1–AX5 | 20–42pt | Accessibility sizes |

### Practical Options for This App

**Option A: Manual system Text Size integration**
- Read `UserDefaults(suiteName: "com.apple.universalaccess")` and KVO on `FontSizeCategory`.
- Build a custom mapping from category values to font sizes.
- Requires `com.apple.security.temporary-exception.shared-preference.read-only` entitlement for `com.apple.universalaccess` — unclear impact on App Store distribution, but this app is not on the App Store.
- Significant implementation effort. No standard patterns to follow.

**Option B: In-app font size control**
- Add a font size slider or presets in Settings (Small / Medium / Large / Extra Large).
- Use a custom environment value or `@ScaledMetric`-like property wrapper driven by the user's choice.
- No entitlement issues. Works on all macOS versions.
- User must configure it separately from system settings.

**Option C: Keep semantic fonts, wait for Apple**
- Continue using `.caption`, `.body`, `.title3` etc. throughout.
- Replace the 4 remaining fixed-size fonts with semantic equivalents where possible.
- When/if Apple adds Dynamic Type to macOS, the app benefits automatically.
- Zero effort now, zero benefit now.

**Option D: Hybrid — semantic fonts + generous frame constraints**
- Keep semantic fonts for future compatibility.
- Remove or relax the maxWidth/maxHeight frame constraints so the window can grow if content grows.
- Doesn't solve text scaling, but does solve "window too small for content amount."

### Relevance to the Original Question

The original question asked about adapting to Dynamic Type, accessibility settings, and content amount. The findings show:

1. **Dynamic Type**: Not supported on macOS for third-party apps. `@ScaledMetric` is a no-op. The only way to respond to system text size is manual implementation with entitlement requirements. Semantic fonts are already mostly used and are the right default for future-proofing.

2. **Accessibility settings**: VoiceOver labels/hints are comprehensive. Visual accessibility (Reduce Motion, Increase Contrast) is not handled but is straightforward to add via environment values. Text size accessibility requires Option A or B above.

3. **Content amount**: The MenuBarExtra window uses fixed min/max frame constraints. Since the content already scrolls via `ScrollView` + `LazyVStack`, content overflow is handled. Relaxing frame constraints (especially maxHeight) would let the window show more content when available. The user has indicated the panel should take up as much space as needed since it's overlay UI.

### References

- [SwiftUI Field Guide – Dynamic Type](https://www.swiftuifieldguide.com/layout/dynamic-type/)
- [Stack Overflow – macOS 14 Sonoma Text Size](https://stackoverflow.com/questions/77937271/how-to-respond-to-the-new-text-size-setting-in-macos-14-sonoma)
- [Stack Overflow – macOS font scaling](https://stackoverflow.com/questions/77917221/macos-projects-fonts-are-not-scaling)
- [Stack Overflow – Customizable font size in macOS](https://stackoverflow.com/questions/75115578/how-to-make-font-size-customizable-in-a-macos-app)
- [WWDC24 – Get started with Dynamic Type](https://developer.apple.com/videos/play/wwdc2024/10074/) (iOS/visionOS/watchOS only)
- [Apple HIG – Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Jared Sinclair – Scaled Metric Surprises](https://jaredsinclair.com/2024/03/02/scaled-metrics.html) (iOS behavior)
