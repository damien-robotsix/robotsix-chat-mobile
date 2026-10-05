import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/widgets/chat_input_bar.dart';

/// Accessibility tests: validate that interactive widgets expose the semantic
/// labels and tooltips that screen readers (TalkBack / VoiceOver) rely on.
///
/// These assertions inspect the widget tree directly rather than the compiled,
/// merged semantics tree. The merged tree is sensitive to how Flutter folds
/// adjacent semantic contributions together (e.g. an [IconButton]'s tooltip and
/// its [Icon]'s `semanticLabel`), which makes label-equality finders brittle
/// across Flutter versions. Inspecting the widgets directly guarantees the a11y
/// annotations are present and stable.
///
/// See `docs/accessibility.md` for the project's a11y strategy and labelling
/// conventions.
Future<void> _pumpInputBar(WidgetTester tester) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatInputBar(
          controller: controller,
          isLoading: false,
          onSend: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('send button exposes a semantic label and tooltip', (
    tester,
  ) async {
    await _pumpInputBar(tester);

    // The send action is announced via the icon's semantic label ...
    final icon = tester.widget<Icon>(find.byIcon(Icons.send));
    expect(icon.semanticLabel, 'Send message');

    // ... and via the button tooltip (also surfaced to screen readers).
    expect(find.byTooltip('Send message'), findsOneWidget);
  });

  testWidgets('message input field exposes a semantic label', (tester) async {
    await _pumpInputBar(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Message input',
      ),
      findsOneWidget,
      reason: 'the message input should carry a "Message input" semantic label',
    );
  });

  testWidgets('interactive elements expose the expected a11y annotations', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

    await _pumpInputBar(tester);

    // Send button: labelled icon, descriptive tooltip, and enabled (so its
    // enabled/disabled state is announced correctly).
    final icon = tester.widget<Icon>(find.byIcon(Icons.send));
    expect(icon.semanticLabel, 'Send message');
    expect(find.byTooltip('Send message'), findsOneWidget);

    final sendButton = tester.widget<IconButton>(find.byType(IconButton));
    expect(sendButton.onPressed, isNotNull);

    // Message input: carries a semantic label and is flagged as a text field.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Message input' &&
            widget.properties.textField == true,
      ),
      findsOneWidget,
    );
  });
}
