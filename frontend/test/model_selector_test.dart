import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/providers/pi_view_model.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';
import 'package:pi_mobile_agent/widgets/model_selector.dart';
import 'package:provider/provider.dart';

/// PiService stub for the model picker: a fixed list of offered models, a state
/// that says which model Pi is really running, and a record of what switching
/// was asked for.
class FakeModelService extends PiService {
  final List<PiModel> offered;
  final Map<String, dynamic> stateJson;
  final _events = StreamController<PiEvent>.broadcast();
  final _states = StreamController<PiState>.broadcast();

  String? requestedProvider;
  String? requestedModelId;
  int setModelCalls = 0;

  FakeModelService({
    required this.offered,
    required this.stateJson,
  });

  @override
  Stream<PiEvent> get events => _events.stream;
  @override
  Stream<PiState> get stateUpdates => _states.stream;

  void emitState() => _states.add(PiState.fromJson(stateJson));

  @override
  Future<List<PiModel>> getAvailableModels() async => offered;

  @override
  Future<void> setModel(String modelId, String provider) async {
    setModelCalls++;
    requestedModelId = modelId;
    requestedProvider = provider;
  }

  @override
  Future<void> refreshState() async {}
}

Widget _app(PiViewModel viewModel) => ChangeNotifierProvider<PiViewModel>.value(
      value: viewModel,
      child: const MaterialApp(home: Scaffold(body: ModelSelector())),
    );

void main() {
  final offered = [
    PiModel(
      id: 'claude-haiku-4.5',
      name: 'Claude Haiku 4.5',
      provider: 'github-copilot',
    ),
    PiModel(
      id: 'gpt-5.6-luna',
      name: 'GPT 5.6 Luna',
      provider: 'github-copilot',
    ),
  ];

  PiViewModel buildViewModel(FakeModelService service) {
    final viewModel = PiViewModel(piService: service);
    service.emitState();
    return viewModel;
  }

  testWidgets('switching a model names it to Pi by provider and id',
      (tester) async {
    final service = FakeModelService(
      offered: offered,
      stateJson: {
        'model': {'id': 'claude-haiku-4.5', 'provider': 'github-copilot'},
      },
    );
    final viewModel = buildViewModel(service);
    await tester.pumpWidget(_app(viewModel));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT 5.6 Luna').last);
    await tester.pumpAndSettle();

    // Pi's set_model takes a provider and a model id. A bare model string is
    // answered "Model not found: undefined/undefined", and the picker looks
    // like it does nothing.
    expect(service.setModelCalls, 1);
    expect(service.requestedModelId, 'gpt-5.6-luna');
    expect(service.requestedProvider, 'github-copilot');

    viewModel.dispose();
  });

  testWidgets('a model Pi runs but never offered is shown, not a crash',
      (tester) async {
    // The state this reproduces is real: Pi was running gpt-5.4 while its own
    // list of models did not contain it. DropdownButton asserts that its value
    // is one of its items, so the picker - and with it the whole input area -
    // used to fail to build at all.
    final service = FakeModelService(
      offered: offered,
      stateJson: {
        'model': {'id': 'gpt-5.4', 'provider': 'github-copilot'},
      },
    );
    final viewModel = buildViewModel(service);
    await tester.pumpWidget(_app(viewModel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('gpt-5.4 (not offered)'), findsOneWidget);

    // And it is one tap away from a model that works.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Haiku 4.5').last);
    await tester.pumpAndSettle();

    expect(service.requestedModelId, 'claude-haiku-4.5');
    expect(service.requestedProvider, 'github-copilot');

    viewModel.dispose();
  });
}
