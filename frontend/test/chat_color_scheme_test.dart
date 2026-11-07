import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/main.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/utils/dracula_scheme.dart';
import 'package:pi_mobile_agent/widgets/chat_bubble.dart';
import 'package:pi_mobile_agent/widgets/chat_list.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// A chat with both roles in it: a prompt the app sent, and a reply Pi sent.
///
/// Both are here on purpose. The colour scheme is not one colour - your own
/// messages take the scheme's primary family, Pi's replies its tertiary - and a
/// test that looked at only one of them would pass with half the chat still
/// hardcoded.
class FakeChatService extends PiService {
  final StreamController<PiEvent> _events =
      StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  Future<List<PiModel>> getAvailableModels() async => [
        // One model the account can use, one it cannot, and one that can take a
        // photo: the three things the picker paints in its own colours.
        PiModel(
          id: 'model-offered',
          name: 'Offered Model',
          provider: 'test-provider',
          input: const ['text', 'image'],
        ),
        PiModel(
          id: 'model-retired',
          name: 'Retired Model',
          provider: 'test-provider',
          available: false,
        ),
      ];

  @override
  Future<void> sendPrompt(String message,
      {List<PiImage> images = const []}) async {}

  @override
  bool get isConnected => true;

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));

  /// Pi opening a reply with its text already there, which is how a resumed or
  /// finished message arrives.
  void addAssistantMessage(String text) {
    emit({
      'type': 'message_start',
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text}
        ],
      },
    });
  }
}

/// The app as `main.dart` runs it, theme provider included.
///
/// The view model comes *out of the widget tree* rather than being handed in:
/// `MyApp` creates the one its screens use, and a second one - however well fed -
/// is a view model no bubble is listening to.
Future<(AppearanceController, PiViewModel, FakeChatService)> pumpApp(
    WidgetTester tester,
    {Size size = const Size(900, 1200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final service = FakeChatService();
  final appearance = AppearanceController();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppearanceController>.value(
      value: appearance,
      child: MyApp(
        service: service,
        safeArea: ValueNotifier<EdgeInsets>(EdgeInsets.zero),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final viewModel =
      Provider.of<PiViewModel>(tester.element(find.byType(HomeScreen)),
          listen: false);
  return (appearance, viewModel, service);
}

void main() {
  const userText = 'plain text about the build';
  const assistantText = 'a reply from Pi about the build';

  /// The theme the chat is actually drawn under - not the one some controller
  /// believes it is.
  ColorScheme schemeOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(ChatList).first)).colorScheme;

  /// The colour a bubble's body text is really drawn in.
  Color chatTextColor(WidgetTester tester, String text) => tester
      .widget<Text>(find
          .descendant(
            of: find.byType(ChatList),
            matching: find.text(text),
          )
          .first)
      .style!
      .color!;

  /// The colour a bubble is really filled with.
  ///
  /// Found from something inside the bubble rather than by its own type: the
  /// chat holds one container per message and a test wants *this message's*.
  Color bubbleColor(WidgetTester tester, Finder insideBubble) {
    final container = tester.widget<AnimatedContainer>(find
        .ancestor(
          of: insideBubble,
          matching: find.byType(AnimatedContainer),
        )
        .first);
    return (container.decoration as BoxDecoration).color!;
  }

  /// The `Finder` for a bubble's "Pi" label.
  Finder piLabel() =>
      find.descendant(of: find.byType(ChatList), matching: find.text('Pi'));

  Color userBubbleColor(WidgetTester tester) => bubbleColor(
      tester,
      find.descendant(
          of: find.byType(ChatList), matching: find.text(userText)));

  Color assistantBubbleColor(WidgetTester tester) =>
      bubbleColor(tester, piLabel());

  /// The colour the "Pi" label is drawn in - the accent of a reply, which is
  /// what tells Pi's bubbles apart from yours at a glance.
  Color assistantAccent(WidgetTester tester) =>
      tester.widgetList<Text>(piLabel()).first.style!.color!;

  Future<void> settleThemeChange(WidgetTester tester) async {
    // MaterialApp animates from one theme into the other, so the frame right
    // after the choice is a blend of the two.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> fillChat(WidgetTester tester, PiViewModel viewModel,
      FakeChatService service) async {
    await viewModel.submitPrompt(userText);
    await tester.pump(const Duration(milliseconds: 120));
    service.addAssistantMessage(assistantText);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(ChatBubble), findsAtLeastNWidgets(2),
        reason: 'both bubbles have to be on screen for a colour read to mean '
            'anything about them');
    expect(
        find.descendant(
            of: find.byType(ChatList), matching: find.text(assistantText)),
        findsOneWidget);
  }

  testWidgets('the chat is drawn in the colours of the current scheme',
      (tester) async {
    final (appearance, viewModel, service) = await pumpApp(tester);
    await fillChat(tester, viewModel, service);

    // Read tokens, not fixed hex values: what is being tested is that the chat
    // and the theme agree, whatever the theme happens to be.
    final scheme = schemeOf(tester);
    expect(userBubbleColor(tester), scheme.primaryContainer,
        reason: 'your own messages are where a scheme shows up most, and these '
            'were the part left hardcoded blue');
    expect(chatTextColor(tester, userText), scheme.onPrimaryContainer);
    expect(assistantBubbleColor(tester), scheme.surfaceContainerHigh);
    expect(chatTextColor(tester, assistantText), scheme.onSurface);
    expect(assistantAccent(tester), scheme.tertiary);

    appearance.dispose();
  });

  testWidgets('choosing another colour scheme repaints the chat',
      (tester) async {
    final (appearance, viewModel, service) = await pumpApp(tester);
    await fillChat(tester, viewModel, service);

    final before = {
      'userBubble': userBubbleColor(tester),
      'userText': chatTextColor(tester, userText),
      'accent': assistantAccent(tester),
    };

    await openAppMenu(tester);
    await tapMenuRow(tester, Icons.palette);
    expect(find.text('Green'), findsOneWidget,
        reason: 'the picker has to name what it offers, not only show swatches');

    await tester.tap(find.text('Green'));
    await settleThemeChange(tester);

    expect(appearance.colorScheme, AppColorScheme.green);

    // The claim is not "something changed", it is that the chat matches the
    // scheme the app is now drawing with.
    final after = schemeOf(tester);
    expect(userBubbleColor(tester), after.primaryContainer);
    expect(chatTextColor(tester, userText), after.onPrimaryContainer);
    expect(assistantAccent(tester), after.tertiary);

    expect(before['userBubble'], isNot(after.primaryContainer),
        reason: 'a setting the chat ignores is a setting half applied');
    expect(before['userText'], isNot(after.onPrimaryContainer));
    expect(before['accent'], isNot(after.tertiary));

    // Same message content, new colours. The rendered bodies are cached per
    // message, so a cache keyed on content and brightness alone would still be
    // drawing the colours from before the choice - on every message at once.
    expect(
        find.descendant(
            of: find.byType(ChatList), matching: find.text(userText)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ChatList), matching: find.text(assistantText)),
        findsOneWidget);

    appearance.dispose();
  });

  /// WCAG contrast between two colours, for the claims this file makes about
  /// legibility rather than about identity.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (la > lb ? la / lb : lb / la);
  }

  testWidgets('Dracula paints the chat with Dracula, not with a purple seed',
      (tester) async {
    final (appearance, viewModel, service) = await pumpApp(tester);
    await fillChat(tester, viewModel, service);

    // Its palette is the dark one, so reach it the way a person does: dark
    // mode first, then the scheme.
    appearance.toggleTheme(Brightness.light); // the app is showing light
    appearance.setColorScheme(AppColorScheme.dracula);
    await settleThemeChange(tester);

    final scheme = schemeOf(tester);
    expect(scheme.surface, Dracula.background);
    expect(assistantBubbleColor(tester), Dracula.surfaceHigh);
    expect(chatTextColor(tester, assistantText), Dracula.foreground);
    expect(assistantAccent(tester), Dracula.pink,
        reason: 'the accent a generated scheme would have derived by hue rotation '
            'is not a colour Dracula has');
    expect(userBubbleColor(tester), isNot(Dracula.surfaceHigh),
        reason: 'your own messages are the purple family, not a third surface');

    // Dracula's comment grey is a code-editor grey: kept as-is it is the muted
    // UI text nobody can read comfortably.
    expect(scheme.onSurfaceVariant, Dracula.commentOnDark);
    expect(contrast(scheme.onSurfaceVariant, Dracula.surfaceHigh),
        greaterThanOrEqualTo(4.5));
    expect(contrast(Dracula.pink, Dracula.surfaceHigh),
        greaterThanOrEqualTo(4.5));
    expect(contrast(Dracula.foreground, Dracula.background),
        greaterThanOrEqualTo(4.5));

    appearance.dispose();
  });

  testWidgets('the model picker is painted with the scheme too',
      (tester) async {
    final app = await pumpApp(tester);
    final appearance = app.$1;

    // Read everything after the change: a widget instance captured before it is
    // the decoration the old theme built.
    appearance.toggleTheme(Brightness.light); // the app is showing light
    appearance.setColorScheme(AppColorScheme.dracula);
    await settleThemeChange(tester);

    final scheme = schemeOf(tester);

    // The box the picker is built in is always on screen.
    final box = tester.widget<Container>(find
        .ancestor(
          of: find.byType(DropdownButton<String>),
          matching: find.byType(Container),
        )
        .first);
    final border = (box.decoration as BoxDecoration).border as Border;
    expect(border.top.color, scheme.outlineVariant,
        reason: 'the hairline around the picker was a fixed light grey, which '
            'is a bright line across a dark app');

    // The rows only exist once the menu is open - a closed dropdown renders the
    // selected item, and here nothing is selected.
    await tester.tap(find.byType(DropdownButton<String>));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
        tester
            .widget<Icon>(find.byIcon(Icons.error_outline).first)
            .color,
        scheme.error,
        reason: 'a model that is not offered is a failure like any other the '
            'app reports, so it is the theme red rather than a fixed one');
    expect(
        tester.widget<Icon>(find.byIcon(Icons.image_outlined).first).color,
        scheme.onSurfaceVariant,
        reason: 'what a model can take is a fact about it, not something to '
            'act on - muted, and the theme\'s muted');

    appearance.dispose();
  });

  testWidgets('the picker says which schemes are dark only', (tester) async {
    final app = await pumpApp(tester);
    final appearance = app.$1;

    await openAppMenu(tester);
    await tapMenuRow(tester, Icons.palette);

    expect(find.text('Dracula'), findsOneWidget);
    expect(find.textContaining('dark palette'), findsOneWidget,
        reason: 'a swatch cannot say that a palette is dark only, and picking '
            'one to find that out is a worse way to learn it');

    appearance.dispose();
  });

  testWidgets('the two roles stay tellable apart in every scheme',
      (tester) async {
    final (appearance, viewModel, service) = await pumpApp(tester);
    await fillChat(tester, viewModel, service);

    for (final scheme in AppColorScheme.values) {
      appearance.setColorScheme(scheme);
      await settleThemeChange(tester);

      final active = schemeOf(tester);
      expect(assistantAccent(tester), active.tertiary);
      expect(
          assistantAccent(tester),
          isNot(active.primary),
          reason: '"Pi" and "You" are told apart by hue. A scheme that made '
              'them the same colour would cost the chat its only visual '
              'distinction - ${scheme.name} is the one to check it in.');
      expect(
          userBubbleColor(tester),
          isNot(assistantBubbleColor(tester)),
          reason: 'the bubbles have to stay tellable apart too, in '
              '${scheme.name}');
    }

    appearance.dispose();
  });
}
