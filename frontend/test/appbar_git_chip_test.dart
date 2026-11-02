import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/git_status_chip.dart';
import 'package:provider/provider.dart';

/// A backend that reports a git repository, so the bar has a branch to show.
///
/// The status is mutable because the counts are the point of the tooltip: a test
/// that wants "3 files changed" changes what the backend says rather than
/// building the sentence in the test.
class _GitService extends PiService {
  final StreamController<PiState> _states = StreamController<PiState>.broadcast();

  Map<String, dynamic>? gitStatus;
  String branch = 'main';

  @override
  Stream<PiState> get stateUpdates => _states.stream;
  @override
  Stream<PiEvent> get events => const Stream.empty();
  @override
  bool get isConnected => true;
  @override
  Future<List<PiModel>> getAvailableModels() async => const [];
  @override
  Future<void> refreshState() async {}
  @override
  Future<List<Map<String, dynamic>>> loadCurrentHistory() async => const [];

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {
          'input': 40000,
          'output': 0,
          'total': 40000
        },
        'contextUsage': {'tokens': 40000, 'contextWindow': 200000, 'percent': 20},
      });

  void push() {
    _states.add(PiState(
      cwd: '/home/adam/source/repos/pi-mobile-agent',
      cwdDisplay: '~/source/repos/pi-mobile-agent',
      gitBranch: gitStatus == null ? null : branch,
      gitStatus: gitStatus == null ? null : GitStatus.fromJson(gitStatus!),
    ));
  }
}

Map<String, dynamic> _dirty() => {
      'branch': 'main',
      'upstream': 'origin/main',
      'ahead': 2,
      'modified': 3,
      'untracked': 1,
    };

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<PiViewModel> pumpHome(WidgetTester tester, _GitService service,
      double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final viewModel = PiViewModel(piService: service);
    await tester.pumpWidget(ChangeNotifierProvider<AppearanceController>(
      create: (_) => AppearanceController(),
      child: ChangeNotifierProvider<PiViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    ));
    await settle(tester);
    return viewModel;
  }

  testWidgets('the branch sits at the right end of the bar', (tester) async {
    for (final width in [390.0, 1280.0]) {
      final service = _GitService()..gitStatus = _dirty();
      await pumpHome(tester, service, width);
      service.push();
      await settle(tester);

      final bar = tester.getRect(find.byType(AppBar));
      final folder = tester.getRect(find.byIcon(Icons.folder_open));
      final branch = tester.getRect(find.text('main'));
      final meter = tester.getRect(find.text('20%'));

      expect(branch.left, greaterThan(folder.left),
          reason: 'the directory is the left-hand thing and the branch is the '
              'right-hand one');
      expect(branch.right, lessThan(meter.left),
          reason: 'it belongs beside the other read-only indicators, not among them');
      expect(meter.left - branch.right, lessThan(40),
          reason: 'adjacent to them, not merely somewhere to their left');
      expect(branch.left, greaterThan((bar.left + bar.right) / 2),
          reason: 'on a $width-wide window the branch was measured in the middle '
              'of the bar with half of it empty behind it: the title box is '
              'width-limited by the AppBar, so the only place a flex reaches the '
              'right edge is the actions');
    }
  });

  testWidgets('the tooltip says what the working tree is doing', (tester) async {
    final service = _GitService()..gitStatus = _dirty();
    await pumpHome(tester, service, 390);
    service.push();
    await settle(tester);

    final tooltip = find.byTooltip(
      'Branch main\n2 committed, not pushed to origin/main\n3 modified, 1 untracked',
    );
    expect(tooltip, findsOneWidget,
        reason: 'the bar has room for the branch name and nothing else, so the '
            'state behind it has to be one press or one hover away');
  });

  testWidgets('a clean tree says so rather than showing nothing', (tester) async {
    final service = _GitService()
      ..gitStatus = {'branch': 'main', 'upstream': 'origin/main'};
    await pumpHome(tester, service, 390);
    service.push();
    await settle(tester);

    expect(
      find.byTooltip('Branch main\nup to date with origin/main\nworking tree clean'),
      findsOneWidget,
    );
  });

  testWidgets('no repository, no branch', (tester) async {
    final service = _GitService();
    await pumpHome(tester, service, 390);
    service.push();
    await settle(tester);

    expect(find.byType(GitStatusChip), findsOneWidget,
        reason: 'the chip is always in the bar; it is the state that is absent');
    expect(find.byIcon(Icons.merge_type), findsNothing);
    expect(find.text('main'), findsNothing);
    expect(find.text('20%'), findsOneWidget,
        reason: 'the rest of the bar is unaffected by there being no git here');
  });

  testWidgets('a long branch name is shortened, not squeezed out', (tester) async {
    const long = 'feature/a-branch-name-long-enough-to-run-past-the-whole-bar';
    final service = _GitService();
    service.branch = long;
    service.gitStatus = {'branch': long, 'upstream': 'origin/main'};
    await pumpHome(tester, service, 390);
    service.push();
    await settle(tester);

    final branch = tester.getRect(find.text(long));
    final meter = tester.getRect(find.text('20%'));

    expect(branch.width, lessThanOrEqualTo(140),
        reason: 'a branch name may be long; the context percentage may not be '
            'pushed off the screen to make room for it');
    expect(branch.right, lessThan(meter.left));
  });
}
