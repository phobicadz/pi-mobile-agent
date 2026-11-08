import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/screens/home_screen.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/file_browser.dart';
import 'package:pi_mobile_agent/widgets/github_clone_dialog.dart';
import 'package:provider/provider.dart';

import 'support/app_menu.dart';

/// A backend that lists a directory, lists two repositories, and clones one.
///
/// Every clone is recorded rather than performed: what these tests are about is
/// which directory a clone is asked for and what the sheet does with the answer,
/// not whether git can copy a repository.
class CloneService extends PiService {
  static const reposDir = '/home/adam/source/repos';

  /// What the clone requests actually carried, as `owner/name -> target`.
  ///
  /// Read as text because "the directory being browsed" is the whole claim, and
  /// a test that only asserts a clone *happened* would pass with the wrong one.
  final clones = <String>[];

  /// Set to make every clone fail with this reason.
  String? failWith;

  final _states = StreamController<PiState>.broadcast();

  @override
  Stream<PiState> get stateUpdates => _states.stream;

  @override
  Stream<PiEvent> get events => const Stream.empty();

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  bool get isConnected => true;

  @override
  Future<void> refreshState() async {}

  @override
  Future<FileListing> listFiles({String? path}) async {
    final dir = path ?? reposDir;
    final insideAClone = dir != reposDir;
    return FileListing(
      path: dir,
      roots: const [],
      entries: [
        DirEntry(
          name: insideAClone ? 'README.md' : 'pi-setup',
          path: insideAClone ? '$dir/README.md' : '$reposDir/pi-setup',
          isDirectory: !insideAClone,
        ),
      ],
      recent: const [],
    );
  }

  @override
  Future<List<GitHubRepo>> listGitHubRepos() async => [
        GitHubRepo(
          slug: 'phobicadz/docker',
          name: 'docker',
          owner: 'phobicadz',
          url: 'https://github.com/phobicadz/docker',
          isPrivate: true,
          description: 'Docker compose and Docker files for various machines',
          pushedAt: DateTime.utc(2026, 11, 4),
        ),
        GitHubRepo(
          slug: 'phobicadz/pagebox',
          name: 'pagebox',
          owner: 'phobicadz',
          url: 'https://github.com/phobicadz/pagebox',
          pushedAt: DateTime.utc(2026, 10, 30),
        ),
      ];

  @override
  Future<String> cloneGitHubRepo(
      {required String repo, String? path}) async {
    clones.add('$repo -> ${path ?? reposDir}');
    if (failWith != null) throw Exception(failWith);
    final name = repo.split('/').last.replaceAll(RegExp(r'\.git$'), '');
    return '${path ?? reposDir}/$name';
  }
}

/// The field in the clone picker, and not the composer behind the sheet.
Finder cloneSearchField() => find.descendant(
      of: find.byType(GitHubCloneDialog), matching: find.byType(TextField));

Future<PiViewModel> pumpHome(WidgetTester tester, CloneService service) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
  await settle(tester);
  return viewModel;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Open the browser sheet and the clone picker in it.
Future<void> openClonePicker(WidgetTester tester) async {
  await openFileBrowser(tester);
  expect(find.byType(FileBrowser), findsOneWidget);

  await tester.tap(find.byIcon(Icons.cloud_download));
  await settle(tester);
  expect(find.byType(GitHubCloneDialog), findsOneWidget);
}

void main() {
  testWidgets('the clone picker lists the repositories, private ones marked',
      (tester) async {
    final viewModel = await pumpHome(tester, CloneService());
    await openClonePicker(tester);

    expect(find.text('phobicadz/docker'), findsOneWidget);
    expect(find.text('phobicadz/pagebox'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget,
        reason: 'a private repository is the one a clone can fail on '
            'permissions for, so the difference is worth knowing before the tap');

    viewModel.dispose();
  });

  testWidgets('picking a repository clones it into the directory being browsed, '
      'and the browser lands inside what it made', (tester) async {
    final service = CloneService();
    final viewModel = await pumpHome(tester, service);
    await openClonePicker(tester);

    await tester.tap(find.text('phobicadz/docker'));
    await settle(tester);

    expect(
      service.clones.single,
      'phobicadz/docker -> ${CloneService.reposDir}',
      reason: 'the picker was opened from a directory on screen, so that is '
          'the one the clone belongs in — not whatever Pi was spawned in',
    );

    expect(find.byType(GitHubCloneDialog), findsNothing);
    expect(find.text('Location: ${CloneService.reposDir}/docker'),
        findsOneWidget,
        reason: 'the point of cloning a repository here is to work on it, and '
            'the sheet is now sitting in it with "Set as working directory" '
            'one tap away');
    expect(find.text('README.md'), findsOneWidget,
        reason: 'the listing is the new directory\'s, not the parent\'s');

    viewModel.dispose();
  });

  testWidgets('a repository that is not in the list is still cloned as typed',
      (tester) async {
    final service = CloneService();
    final viewModel = await pumpHome(tester, service);
    await openClonePicker(tester);

    await tester.enterText(cloneSearchField(), 'someone/other');
    await settle(tester);

    expect(find.text('Clone someone/other'), findsOneWidget,
        reason: 'a repository owned by someone else, or one past the listing '
            'cap, has to be reachable from the same field that filters it');

    await tester.tap(find.text('Clone someone/other'));
    await settle(tester);

    expect(service.clones.single, 'someone/other -> ${CloneService.reposDir}');
    expect(find.text('Location: ${CloneService.reposDir}/other'),
        findsOneWidget);

    viewModel.dispose();
  });

  testWidgets('typing narrows the list to what the words match',
      (tester) async {
    final viewModel = await pumpHome(tester, CloneService());
    await openClonePicker(tester);

    await tester.enterText(cloneSearchField(), 'pagebox');
    await settle(tester);

    expect(find.text('phobicadz/pagebox'), findsOneWidget);
    expect(find.text('phobicadz/docker'), findsNothing);
    // The typed text names the repository the list is already showing, so it is
    // not offered a second time as its own action.
    expect(find.text('Clone pagebox'), findsNothing);

    viewModel.dispose();
  });

  testWidgets('a failed clone keeps the reason where it can be read and tried '
      'again from', (tester) async {
    final service = CloneService();
    final viewModel = await pumpHome(tester, service);
    service.failWith =
        'GitHub is not signed in on this machine — run `gh auth login` there first.';
    await openClonePicker(tester);

    await tester.tap(find.text('phobicadz/docker'));
    await settle(tester);

    expect(find.byType(GitHubCloneDialog), findsOneWidget,
        reason: 'a dialog that closed on a failure would take the reason with '
            'it and leave a directory that is not there');
    // Scoped to the dialog, because the same failure is also in the view model
    // and the chat behind this sheet shows that too. What matters here is that
    // the reason is next to the control that failed and the button that retries
    // it.
    expect(
      find.descendant(
        of: find.byType(GitHubCloneDialog),
        matching: find.textContaining('gh auth login'),
      ),
      findsOneWidget,
    );
    expect(find.text('Location: ${CloneService.reposDir}'), findsOneWidget,
        reason: 'the browser stays where it was — nothing was cloned');

    viewModel.dispose();
  });
}
