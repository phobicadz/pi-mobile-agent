import 'package:flutter/services.dart';

/// Where a reference lands in the prompt text.
typedef PromptInsertion = ({String text, int caret});

/// Put a `path:line` reference into the prompt text at the caret.
///
/// A reference is one token, so it is separated from whatever is already typed:
/// glued onto the end of a word it becomes part of that word, and the agent is
/// asked to open a file called `scrapercheck.ts:10-20`. The caret ends up after
/// what was inserted, including the gap, so typing can continue straight on.
///
/// Pure, because "where does the text land" is the part of inserting a reference
/// that is worth being able to prove, and it does not need a widget tree.
PromptInsertion insertReferenceIntoPrompt({
  required String text,
  required TextSelection selection,
  required String reference,
}) {
  final offset = (selection.baseOffset < 0 ? text.length : selection.baseOffset)
      .clamp(0, text.length);
  final before = text.substring(0, offset);
  final after = text.substring(offset);

  final gapBefore =
      before.isNotEmpty && !_breaks(before.codeUnitAt(before.length - 1));
  final gapAfter = after.isNotEmpty && !_breaks(after.codeUnitAt(0));

  final inserted = '${gapBefore ? ' ' : ''}$reference${gapAfter ? ' ' : ''}';

  return (
    text: before + inserted + after,
    caret: before.length + inserted.length,
  );
}

bool _breaks(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
