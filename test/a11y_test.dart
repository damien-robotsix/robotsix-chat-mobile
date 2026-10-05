import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/widgets/chat_input_bar.dart';

/// Accessibility tests: validate that interactive widgets expose semantic
/// labels so screen readers (TalkBack / VoiceOver) can announce them.
///
/// See `docs/accessibility.md` for the project's a11y strategy and labelling
/// conventions.
void main() {
  testWidgets('send button exposes a semantic label', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

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

    expect(find.bySemanticsLabel('Send message'), findsWidgets);
  });

  testWidgets('message input field exposes a semantic label', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

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

    expect(find.bySemanticsLabel('Message input'), findsWidgets);
  });

  testWidgets('semantic tree is traversable and exposes the expected labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);

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

    // Smoke test: walk the merged semantics tree the way a screen reader would
    // and collect every announced label.
    final labels = <String>{};
    void visit(SemanticsNode node) {
      final label = node.getSemanticsData().label.trim();
      if (label.isNotEmpty) {
        labels.add(label);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);

    expect(
      labels.any((label) => label.contains('Send message')),
      isTrue,
      reason: 'send button label not found in semantics tree: $labels',
    );
    expect(
      labels.any((label) => label.contains('Message input')),
      isTrue,
      reason: 'message input label not found in semantics tree: $labels',
    );
  });
}
