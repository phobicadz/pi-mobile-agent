import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/main.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/appearance_controller.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:provider/provider.dart';

/// A backend that answers `get_session_stats` with fixed numbers, including the
/// context usage Pi computes for the conversation currently loaded.
///
/// The figures are mutable on purpose: the app re-asks for them whenever a run
/// settles, and a test that wants a different number has to change what the
/// backend answers rather than build a second app around a second backend.
class FakeStatsService extends PiService {
  /// The `contextUsage` block Pi reports, or null when it has none - which is
  /// what happens right after a compaction.
  Map<String, dynamic>? contextUsage;

  FakeStatsService({this.contextUsage});

  final StreamController<PiEvent> _events =
      StreamController<PiEvent>.broadcast();

  @override
  Stream<PiState> get stateUpdates => const Stream.empty();

  @override
  Stream<PiEvent> get events => _events.stream;

  @override
  bool get isConnected => true;

  @override
  Future<List<PiModel>> getAvailableModels() async => const [];

  @override
  Future<void> refreshState() async {}

  @override
  Future<PiSessionStats> getSessionStats() async => PiSessionStats.fromJson({
        'tokens': {'input': 1000, 'output': 200, 'total': 1200},
        'cost': 0.01,
        if (contextUsage != null) 'contextUsage': contextUsage,
      });

  void emit(Map<String, dynamic> inner) =>
      _events.add(PiEvent.fromJson({'type': 'pi_event', 'event': inner}));

  /// A run settling is the moment the app asks for the statistics.
  void settled() => emit({'type': 'agent_settled'});
}

Future<void> showMeter(WidgetTester tester, FakeStatsService service) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppearanceController>.value(
      value: AppearanceController(),
      child: MyApp(
        service: service,
        safeArea: ValueNotifier<EdgeInsets>(EdgeInsets.zero),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// Let a run settle with the backend reporting `usage`, so the app re-reads it.
Future<void> settleRun(WidgetTester tester, FakeStatsService service,
    [Map<String, dynamic>? usage]) async {
  service.contextUsage = usage;
  service.settled();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Color meterColour(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.color!;

Map<String, dynamic> _usage(int tokens, int window, double percent) => {
      'tokens': tokens,
      'contextWindow': window,
      'percent': percent,
    };

void main() {
  testWidgets('the bar says nothing about context until Pi has measured it',
      (tester) async {
    await showMeter(tester, FakeStatsService());

    expect(find.textContaining('%'), findsNothing,
        reason: 'a 0% would read as an empty context, which is a different lie '
            'from an unmeasured one, and one someone would act on');
  });

  testWidgets('the bar shows the percentage Pi measured and its numbers',
      (tester) async {
    final service = FakeStatsService();
    await showMeter(tester, service);
    await settleRun(tester, service, _usage(60000, 200000, 30));

    expect(find.text('30%'), findsOneWidget);
    expect(
      find.byTooltip('Context used: 60k / 200k tokens (30.0%)'),
      findsOneWidget,
      reason: 'a percentage with no window behind it cannot be judged; the '
          'tooltip is where the figure becomes meaningful',
    );
  });

  testWidgets('the number says how full the context is without being read',
      (tester) async {
    final service = FakeStatsService();
    await showMeter(tester, service);

    await settleRun(tester, service, _usage(60000, 200000, 30));
    final theme = Theme.of(tester.element(find.text('30%')));
    expect(meterColour(tester, '30%'), theme.colorScheme.onSurfaceVariant,
        reason: 'a third full is not news and must not shout');

    await settleRun(tester, service, _usage(170000, 200000, 85));
    expect(meterColour(tester, '85%'), const Color(0xFF8D6E00),
        reason: 'this is where Pi\'s own compaction starts getting close');

    await settleRun(tester, service, _usage(194000, 200000, 97));
    expect(meterColour(tester, '97%'), theme.colorScheme.error,
        reason: 'one more long file read is what ends the conversation here');

    // A conversation that Pi has just compacted reports no context usage, and
    // the bar goes quiet rather than holding the last number up.
    await settleRun(tester, service, null);
    expect(find.textContaining('%'), findsNothing,
        reason: 'a stale percentage left in the bar reads as the current one');
  });

  testWidgets(
      'a percentage Pi reported without the numbers behind it is still shown',
      (tester) async {
    final service = FakeStatsService();
    await showMeter(tester, service);
    await settleRun(tester, service, {'percent': 42.5});

    expect(find.text('43%'), findsOneWidget,
        reason: 'the percentage is the part worth showing even on its own');
    expect(
      find.byTooltip('Context used: 42.5%'),
      findsOneWidget,
      reason:
          'and the tooltip must not invent token counts that were never reported',
    );
  });
}
