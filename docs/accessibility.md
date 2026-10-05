# Accessibility

This document describes the accessibility (a11y) strategy for
robotsix-chat-mobile and the conventions contributors should follow when
adding new features.

## Strategy and compliance goals

The app aims to be fully usable with screen readers — **TalkBack** on Android
and **VoiceOver** on iOS. Every interactive element must expose a clear,
human-readable semantic label so assistive technologies can announce its
purpose. We target conformance with Flutter's built-in accessibility
guidelines (tap-target size, labelled tap targets, and text contrast).

## Semantic labelling conventions

- **Icon buttons** (`IconButton`): always set `semanticLabel` to a short,
  descriptive phrase (e.g. `'Settings'`, `'Send message'`). Keep the existing
  `tooltip` for sighted mouse users; the two can coexist.
- **Text fields** (`TextField`): wrap the field in a `Semantics` widget with
  `textField: true`, an explicit `label`, and `enabled: true` so screen
  readers announce the field and its role.
- **Custom interactive widgets**: wrap them in a `Semantics` widget with an
  appropriate `label` and the relevant role flags (`button: true`,
  `textField: true`, etc.).
- Prefer concise labels that describe the *action*, not the icon
  (e.g. `'Send message'`, not `'Arrow icon'`).

## Testing with screen readers

### TalkBack (Android)

1. On the device, open **Settings → Accessibility → TalkBack** and turn it on.
2. Launch the app and swipe left/right to move focus between elements.
3. Confirm each interactive element is announced with its semantic label.

### VoiceOver (iOS)

1. On the device, open **Settings → Accessibility → VoiceOver** and turn it on
   (or triple-click the side button if configured).
2. Launch the app and swipe left/right to move focus between elements.
3. Confirm each interactive element is announced with its semantic label.

## Automated tests

`test/a11y_test.dart` validates the semantic tree: it checks that interactive
widgets expose semantic labels and that the UI meets Flutter's
`labeledTapTargetGuideline` and `androidTapTargetGuideline`. Add assertions
there when introducing new interactive widgets.

## References

- [Flutter accessibility guide](https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility)
- [`IconButton.semanticLabel`](https://api.flutter.dev/flutter/material/IconButton-class.html)
- [`Semantics` widget](https://api.flutter.dev/flutter/widgets/Semantics-class.html)
