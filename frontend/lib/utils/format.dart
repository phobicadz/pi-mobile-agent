/// Display helpers for the token counters shown while Pi works.
library;

/// `1234` -> `1.2k`, `12345` -> `12.3k`, `1234567` -> `1.23M`.
///
/// Token counts update many times a second, so they must stay short and keep a
/// stable width; a fixed set of abbreviations avoids the layout jitter a
/// full-width number causes in a status line.
String formatTokens(int value) {
  if (value < 1000) return value.toString();
  if (value < 1000000) {
    final k = value / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
  }
  return '${(value / 1000000).toStringAsFixed(2)}M';
}

/// Counts that are only interesting as a magnitude: `1.2k chars`, `340 chars`.
String formatCount(int value) => formatTokens(value);

/// `0.0146` -> `$0.015`, `1.234` -> `$1.23`.
String formatCost(double value) {
  if (value == 0) return r'$0';
  if (value < 0.01) return '\$${value.toStringAsFixed(4)}';
  if (value < 1) return '\$${value.toStringAsFixed(3)}';
  return '\$${value.toStringAsFixed(2)}';
}
