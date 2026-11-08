import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// A backend that reports the conversation its Pi process is actually in, which
/// is the only thing that can say what the app bar should show next to the
/// directory.
class _NamedService extends PiService {
  final StreamController<PiState> _states = StreamController<PiState>.broadcast();

  static const livePath = '/home/adam/.pi/agent/sessions/--home-adam--/live.jsonl';

  String? sessionName;
  String cwd = '/home/adam/source/repos/pi-mobile-agent';

  /// What the app asked to rename the session to.
  final List<String?> renames = [];

  @override
  Stream<PiState> get stateUpdates => _states.stream;
  @override
  Stream<PiEvent> get events => const Stream.empty();
  @override
  bool get isConnected => true;
  @override
  Future<List<PiModel>> getAvailableModels() async => const [];
  @override
  Future<List<Map<String, dynamic>>> loadCurrentHistory() async => const [];

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {'input': 1000, 'output': 0, 'total': 1000},
        'contextUsage': {'tokens': 1000, 'contextWindow': 200000, 'percent': 1},
      });

  @override
  Future<void> refreshState() async => push();

  @override
  Future<List<PiSessionInfo>> listSessions() async => [
        PiSessionInfo(
          path: livePath,
          id: 'live',
          cwd: cwd,
          name: sessionName,
          preview: 'the first message',
          messageCount: 3,
          modified: DateTime.now(),
        ),
      ];

  @override
  Future<void> renameSession(String sessionPath, String? name) async {
    renames.add(name);
    sessionName = name;
    // The live Pi writes the name into the session it is holding, and the state
    // it reports afterwards is what the bar shows. Simulating the write without
    // the report is how a test passes over a bar that never updates.
    push();
  }

  @override
  Future<void> newSession() async {
    // Pi starts a fresh conversation with no name on it, and the backend asks
    // for the state again right after - which is the report that has to arrive.
    sessionName = null;
    push();
  }

  void push() {
    _states.add(PiState(
      cwd: cwd,
      cwdDisplay: '~/${cwd.split('/').skip(3).join('/')}',
      sessionName: sessionName,
    ));
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(_NamedService, PiViewModel)> pumpHome(
    WidgetTester tester, {
    String? sessionName,
    Size width = const Size(390, 844),
  }) async {
    tester.view.physicalSize = width;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _NamedService()..sessionName = sessionName;
    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppearanceController>(
        create: (_) => AppearanceController(),
        child: ChangeNotifierProvider<PiViewModel>.value(
          value: viewModel,
          child: const MaterialApp(home: HomeScreen()),
        ),
      ),
    );
    service.push();
    await settle(tester);
    return (service, viewModel);
  }

  /// Both finders are scoped to the bar. The same words appear in the session
  /// sheet whenever it is open, and a test that taps one has to be sure which
  /// copy it pressed.
  Finder folderName() => find.descendant(
      of: find.byType(AppBar), matching: find.text('pi-mobile-agent'));
  Finder sessionName() => find.descendant(
      of: find.byType(AppBar), matching: find.text('garden siren diagnosis'));

  /// The three boxes the bar is made of, as laid out.
  ///
  /// The title box is the space the AppBar leaves between the menu button and the
  /// actions - everything the bar puts in its `title` has to live inside it, and
  /// the bar's own `actions` start where it ends.
  ({Rect title, Rect name, Rect folder}) measure(WidgetTester tester, String name) =>
      (
        title: tester.getRect(find
            .descendant(
                of: find.byType(AppBar), matching: find.byType(Consumer<PiViewModel>))
            .first),
        name: tester.getRect(
            find.descendant(of: find.byType(AppBar), matching: find.text(name)).first),
        folder: tester.getRect(find
            .descendant(of: find.byType(AppBar), matching: find.text('pi-mobile-agent'))
            .first),
      );

  testWidgets('the bar names the conversation next to the directory',
      (tester) async {
    final (_, viewModel) =
        await pumpHome(tester, sessionName: 'garden siren diagnosis');

    expect(sessionName(), findsOneWidget,
        reason: 'which directory and which conversation in it are the two halves '
            'of "where am I", and only the directory was ever on screen');

    final style = tester.widget<Text>(sessionName()).style!;
    expect(style.fontWeight, FontWeight.bold,
        reason: 'this is the centre of the bar and the name of what the rest of '
            'the screen is about, not a caption on the directory');

    final folder = tester.getRect(folderName());
    final name = tester.getRect(sessionName());
    expect(name.left, greaterThan(folder.right),
        reason: 'after the folder name, which is the order the question is '
            'asked in');
    expect(name.left, lessThan(name.right));

    viewModel.dispose();
  });

  testWidgets('the name is the session picker, not a label', (tester) async {
    final (_, viewModel) =
        await pumpHome(tester, sessionName: 'garden siren diagnosis');

    await tester.tap(sessionName());
    await settle(tester);

    expect(find.text('Resume a session'), findsOneWidget,
        reason: 'the name is the live session\'s, and the one thing worth doing '
            'with it is leaving it');
    expect(find.byType(AppBar), findsOneWidget);

    viewModel.dispose();
  });

  testWidgets('the name is fixed to the right end of the bar, at both widths',
      (tester) async {
    // A short name and a long one, measured against each other. Anchoring is the
    // design here, and a design is only worth the name if the two things it
    // promises are the two things that stay true: the name ends in the same place
    // whatever it says, and the directory is not what gives way when it is long.
    for (final width in const [Size(390, 844), Size(1280, 900)]) {
      final first = await pumpHome(
        tester,
        sessionName: 'garden siren diagnosis',
        width: width,
      );
      final short = measure(tester, 'garden siren diagnosis');
      first.$2.dispose();

      final second = await pumpHome(
        tester,
        sessionName: 'refactor the mobile agent title bar layout and context meter',
        width: width,
      );
      final long = measure(
          tester, 'refactor the mobile agent title bar layout and context meter');

      for (final measured in [short, long]) {
        expect(measured.title.right - measured.name.right,
            inInclusiveRange(0, 12),
            reason: 'the name is anchored to the right end of the title area - '
                'where the bar already right-aligns things - and the only thing '
                'between it and that edge is its own tap padding (width $width)');
        expect(measured.name.right,
            lessThan(tester.getRect(find.byType(AppBar)).right),
            reason: 'and it is inside the bar, not past it');
        expect(measured.name.left, greaterThan(measured.folder.right),
            reason: 'the two halves of "where am I" do not lie on top of each '
                'other to get there');
      }

      expect(long.name.right, closeTo(short.name.right, 1),
          reason: 'a name that moved with its own length would be a bar whose '
              'centre shifts as you work');
      expect(long.folder, equals(short.folder),
          reason: 'and the directory keeps the room it was given, whatever the '
              'name next to it says');

      second.$2.dispose();
    }
  });

  testWidgets('an unnamed session shows nothing rather than a placeholder',
      (tester) async {
    final (_, viewModel) = await pumpHome(tester);

    expect(folderName(), findsOneWidget);
    expect(find.text('[]'), findsNothing);
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.textContaining('Session:')),
      findsNothing,
      reason: 'an unnamed chat has nothing to show there, and a bar that prints a '
          'placeholder for it is a bar with a decoration on it');

    viewModel.dispose();
  });

  testWidgets('a long name gives way rather than pushing the directory out',
      (tester) async {
    for (final width in const [Size(390, 844), Size(1280, 900)]) {
      final short = await pumpHome(
        tester,
        sessionName: 'garden siren diagnosis',
        width: width,
      );
      final shortFolder = tester.getRect(folderName());
      short.$2.dispose();

      const longName =
          'refactor the mobile agent title bar layout and context meter';
      final (_, viewModel) =
          await pumpHome(tester, sessionName: longName, width: width);

      final bar = tester.getRect(find.byType(AppBar));
      final title = tester.getRect(find
          .descendant(
              of: find.byType(AppBar), matching: find.byType(Consumer<PiViewModel>))
          .first);
      final name = tester.getRect(find
          .descendant(of: find.byType(AppBar), matching: find.text(longName))
          .first);

      expect(name.right, lessThanOrEqualTo(bar.right));
      expect(name.width, lessThanOrEqualTo(title.width / 2),
          reason: 'the name is capped at its own half of the title area, so a '
              'long one ellipsizes there instead of taking the path\'s room off '
              'the bar (width $width)');
      expect(tester.getRect(folderName()).width, equals(shortFolder.width),
          reason: 'which is the whole point of the cap: the directory shows the '
              'same thing it was going to show either way');

      viewModel.dispose();
    }
  });

  testWidgets('renaming the live session renames the bar', (tester) async {
    final (service, viewModel) =
        await pumpHome(tester, sessionName: 'garden siren diagnosis');

    await openSessionPicker(tester, sessionName: 'garden siren diagnosis');
    await settle(tester);

    final row = find.ancestor(
      of: find.text('garden siren diagnosis'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
    );
    await settle(tester);

    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'title bar layout work',
    );
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(service.renames, ['title bar layout work']);
    expect(sessionName(), findsNothing);
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.text('title bar layout work')),
      findsOneWidget,
      reason: 'the bar shows the name Pi reports for the session it is in, so '
          'renaming where you are has to show up where you are');

    viewModel.dispose();
  });

  testWidgets('a new session clears the name from the bar', (tester) async {
    final (_, viewModel) =
        await pumpHome(tester, sessionName: 'garden siren diagnosis');

    await viewModel.startNewSession();
    await settle(tester);

    expect(sessionName(), findsNothing,
        reason: 'a bar still naming the conversation that was just left behind '
            'describes a session it is no longer in');

    viewModel.dispose();
  });
}
