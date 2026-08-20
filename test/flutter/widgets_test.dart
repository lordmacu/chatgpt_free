import 'package:chatgpt_free/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('MessageBubble renders the message text', (tester) async {
    await tester.pumpWidget(_wrap(const MessageBubble(
      message: ChatMessage(role: 'assistant', text: 'hola mundo'),
    )));

    expect(find.text('hola mundo'), findsOneWidget);
  });

  testWidgets('MessageBubble takes its colours from the theme', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: const Scaffold(
        body: MessageBubble(message: ChatMessage(role: 'user', text: 'x')),
      ),
    ));

    final container = tester.widget<Container>(find
        .descendant(
            of: find.byType(MessageBubble), matching: find.byType(Container))
        .first);
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.color, scheme.primaryContainer);
  });

  testWidgets('ChatMessageList renders one bubble per message', (tester) async {
    await tester.pumpWidget(_wrap(const ChatMessageList(messages: [
      ChatMessage(role: 'user', text: 'uno'),
      ChatMessage(role: 'assistant', text: 'dos'),
    ])));

    expect(find.byType(MessageBubble), findsNWidgets(2));
  });

  testWidgets('MessageComposer reports submitted text and clears',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_wrap(MessageComposer(onSend: sent.add)));

    await tester.enterText(find.byType(TextField), 'hola');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, ['hola']);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('MessageComposer is inert while disabled', (tester) async {
    final sent = <String>[];
    await tester
        .pumpWidget(_wrap(MessageComposer(onSend: sent.add, enabled: false)));

    await tester.enterText(find.byType(TextField), 'hola');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, isEmpty);
  });

  testWidgets('CitationChips renders one chip per source', (tester) async {
    await tester.pumpWidget(_wrap(const CitationChips(citations: [
      Citation(title: 'Fuente A', url: 'https://a.example'),
      Citation(title: 'Fuente B', url: 'https://b.example'),
    ])));

    // Plain Chips, not ActionChips: with no onTap a source must not pretend to
    // be pressable. Updated from findsNWidgets(2) on ActionChip, which encoded
    // the fake-button behaviour this widget was fixed to stop doing.
    expect(find.byType(Chip), findsNWidgets(2));
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Fuente A'), findsOneWidget);
  });

  // Appended in Fix round 1: ChatView is the package's flagship convenience
  // widget and previously had zero coverage.

  testWidgets(
      'ChatView renders the transcript, disables the composer '
      'while streaming, and keeps the downgrade out of the UI', (tester) async {
    final transport = FakeTransport();
    final controller = ChatController(
      client: ChatGptClient(transport: transport),
      model: 'gpt-5-6-imaginary', // triggers a downgrade against plain_text.sse
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(ChatView(controller: controller)));

    // FakeTransport streams a fixture off real disk I/O (File.openRead()).
    // testWidgets() runs the test body inside flutter_test's fake-async
    // zone, which never drives genuine dart:io callbacks forward on its
    // own. Stream.listen() binds its callbacks to whatever zone is current
    // when it is called — and ChatController.send() calls .listen()
    // synchronously, before its first await — so it is not enough to
    // tester.runAsync() around the *await*; the call to send() itself has
    // to happen inside runAsync() too, or the subscription stays bound to
    // the fake zone and the read never completes. So: start the turn inside
    // one runAsync() call (without awaiting its result there, so this
    // returns as soon as send()'s synchronous prefix — which sets
    // _isStreaming = true and calls notifyListeners() — has run), pump to
    // observe the mid-stream state, then await completion inside a second
    // runAsync() call.
    late Future<void> sending;
    await tester.runAsync(() async {
      sending = controller.send('hola');
    });
    await tester.pump();

    expect(controller.isStreaming, isTrue);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.byType(TypingIndicator), findsOneWidget);

    await tester.runAsync(() => sending);
    await tester.pump();

    expect(controller.isStreaming, isFalse);
    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.byType(TypingIndicator), findsNothing);

    // The controller still reports the downgrade — that is the package's
    // differentiating signal — but ChatView no longer paints a banner for it:
    // the anonymous backend ignores the requested model on every turn, so the
    // banner fired constantly and drowned the case it exists for.
    expect(controller.downgradeNotice, isNotNull);
    expect(find.textContaining('gpt-5-6-imaginary'), findsNothing);
  });

  // Appended in Fix round 1: TypingIndicator drives a repeating
  // AnimationController that had never been pumped under test, so there was
  // no evidence either way about a pending timer/ticker. `pumpAndSettle()`
  // cannot be used here — it polls until no frame is scheduled, which never
  // happens for a `repeat()`-ing controller, so the call times out. Instead,
  // advance time with explicit `pump(duration)` calls, then unmount the
  // widget (pumpWidget with a replacement tree) so the State's `dispose()` —
  // which disposes the AnimationController and its Ticker — runs
  // deterministically before the test ends, rather than relying on
  // whatever the test framework does with a still-mounted tree at teardown.
  // Verified empirically both ways: on this Flutter (3.38.3), the test
  // passes even without this explicit unmount — this SDK's default
  // `flutter test` run does not fail a still-animating, still-mounted
  // ticker at teardown. The unmount is kept anyway as the documented,
  // version-independent technique for exercising a widget that owns a real
  // Ticker/AnimationController, so the test does not depend on that
  // behaviour continuing to hold on other Flutter versions.
  testWidgets('TypingIndicator animates without leaking a ticker',
      (tester) async {
    await tester.pumpWidget(_wrap(const TypingIndicator()));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TypingIndicator), findsOneWidget);

    // Unmount so dispose() tears down the AnimationController/Ticker
    // deterministically, rather than leaving that to implicit teardown.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ChatView keeps the composer inside the safe area',
      (tester) async {
    // Regression: ChatView was a bare Column, so on a gesture-nav device the
    // composer rendered behind the system navigation bar and the send button
    // could not be tapped. Caught only by installing on a real phone.
    final controller =
        ChatController(client: ChatGptClient(transport: FakeTransport()));
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ChatView(controller: controller)),
    ));

    expect(
      find.ancestor(
        of: find.byType(MessageComposer),
        matching: find.byType(SafeArea),
      ),
      findsWidgets,
      reason: 'the composer must sit inside a SafeArea',
    );
  });

  testWidgets('a citation with no handler is not a fake button',
      (tester) async {
    // Regression: CitationChips used an ActionChip with an empty onPressed, so
    // a source looked tappable and did nothing — reported on device as "it made
    // a button" that responded to nothing.
    await tester.pumpWidget(_wrap(const CitationChips(citations: [
      Citation(title: 'Visor Sismos', url: 'https://sgc.gov.co'),
    ])));

    expect(find.byType(ActionChip), findsNothing);
    expect(find.byType(Chip), findsOneWidget);
    expect(find.text('Visor Sismos'), findsOneWidget);
  });

  testWidgets('a citation with a handler is tappable and reports the source',
      (tester) async {
    final tapped = <Citation>[];
    await tester.pumpWidget(_wrap(CitationChips(
      citations: const [
        Citation(title: 'Visor Sismos', url: 'https://sgc.gov.co')
      ],
      onTap: tapped.add,
    )));

    await tester.tap(find.byType(ActionChip));
    await tester.pump();

    expect(tapped.single.url, 'https://sgc.gov.co');
  });
}
