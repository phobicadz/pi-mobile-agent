import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/models/turn_progress.dart';

const PiUsage _empty = PiUsage.zero;

TurnProgress _progress({
  PiUsage completed = _empty,
  PiUsage live = _empty,
  int estimatedTokens = 0,
  int toolOutputChars = 0,
  double modelSeconds = 0,
}) =>
    TurnProgress(
      active: true,
      kind: ActivityKind.thinking,
      activity: 'thinking',
      completed: completed,
      live: live,
      estimatedTokens: estimatedTokens,
      toolOutputChars: toolOutputChars,
      modelSeconds: modelSeconds,
    );

/// One completed response, as a provider reports it.
PiUsage _response({int output = 0, int reasoning = 0}) =>
    PiUsage(output: output, reasoning: reasoning, totalTokens: 1000);

void main() {
  test('the rate is measured over Pi\'s own reported generation time', () {
    // 224 reply tokens plus 168 thinking tokens over 4 s of generation: the
    // figures and the duration come from the same completed response.
    final progress = _progress(
      completed: _response(output: 224, reasoning: 168),
      modelSeconds: 4,
    );

    expect(progress.generatedTokens, 392,
        reason: 'thinking tokens were decoded in the same window');
    expect(progress.tokensPerSecond, closeTo(98, 0.001));
  });

  test('a run that only ran tools has no generation rate to report', () {
    final progress = _progress(toolOutputChars: 5000);

    expect(progress.tokensPerSecond, 0,
        reason: 'a command taking two minutes is not the model being slow');
  });

  test('no rate is claimed before there is a window long enough to divide by',
      () {
    final progress = _progress(
      completed: _response(output: 40),
      modelSeconds: 0.2,
    );

    expect(progress.tokensPerSecond, 0,
        reason: 'one short response measured over a fraction of a second is '
            'noise, and a number that early reads as a measurement');
  });

  test('a provider that reports nothing while streaming still has a rate', () {
    // Local models report no usage mid-response; the only figure available is
    // the estimate from the characters streamed so far.
    final progress = _progress(estimatedTokens: 200, modelSeconds: 1);

    expect(progress.generatedTokens, 200);
    expect(progress.tokensPerSecond, closeTo(200, 0.001));
  });

  test('a reported count wins over the estimate of the same response', () {
    final progress = _progress(
      live: _response(output: 500),
      estimatedTokens: 120,
      modelSeconds: 2,
    );

    expect(progress.generatedTokens, 500,
        reason: 'the estimate stands in for a provider that says nothing, it '
            'does not add to one that does');
    expect(progress.tokensPerSecond, closeTo(250, 0.001));
  });

  test('an idle run reports nothing', () {
    expect(TurnProgress.idle.tokensPerSecond, 0);
    expect(TurnProgress.idle.generatedTokens, 0);
  });
}
