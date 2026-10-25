import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/utils/format.dart';

void main() {
  test('token counts stay short and stable while they grow', () {
    expect(formatTokens(0), '0');
    expect(formatTokens(999), '999');
    expect(formatTokens(1000), '1.0k');
    expect(formatTokens(1234), '1.2k');
    expect(formatTokens(12345), '12k');
    expect(formatTokens(1234567), '1.23M');
  });

  test('costs are shown with enough precision to be meaningful', () {
    expect(formatCost(0), r'$0');
    expect(formatCost(0.0073675), r'$0.0074');
    expect(formatCost(0.45), r'$0.450');
    expect(formatCost(12.34), r'$12.34');
  });
}
