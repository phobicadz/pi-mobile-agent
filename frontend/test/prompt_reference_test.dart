import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/utils/prompt_reference.dart';

void main() {
  group('inserting a reference into the prompt', () {
    test('an empty prompt becomes the reference on its own', () {
      final result = insertReferenceIntoPrompt(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
        reference: '/srv/app.ts:10-20',
      );

      expect(result.text, '/srv/app.ts:10-20');
      expect(result.caret, 17);
    });

    test('it goes after what was already typed, separated from it', () {
      final result = insertReferenceIntoPrompt(
        text: 'explain what ',
        selection: const TextSelection.collapsed(offset: 13),
        reference: '/srv/app.ts:10-20',
      );

      expect(result.text, 'explain what /srv/app.ts:10-20');
      expect(result.caret, 30);
    });

    test('a word already there is not joined into the path', () {
      // The case a plain append would get wrong: no gap, and the agent is asked
      // to open a file called `scraper/srv/app.ts:10-20`.
      final result = insertReferenceIntoPrompt(
        text: 'fix the scraper',
        selection: const TextSelection.collapsed(offset: 15),
        reference: '/srv/app.ts:7',
      );

      expect(result.text, 'fix the scraper /srv/app.ts:7');
    });

    test('an existing gap is not doubled', () {
      final spaced = insertReferenceIntoPrompt(
        text: 'check ',
        selection: const TextSelection.collapsed(offset: 6),
        reference: '/srv/app.ts:7',
      );
      final wrapped = insertReferenceIntoPrompt(
        text: 'line one\n',
        selection: const TextSelection.collapsed(offset: 9),
        reference: '/srv/app.ts:7',
      );

      expect(spaced.text, 'check /srv/app.ts:7');
      expect(wrapped.text, 'line one\n/srv/app.ts:7');
    });

    test('a reference dropped mid-sentence keeps both halves apart', () {
      final result = insertReferenceIntoPrompt(
        text: 'compare alpha and beta',
        selection: const TextSelection.collapsed(offset: 14),
        reference: '/srv/app.ts:1',
      );

      expect(result.text, 'compare alpha /srv/app.ts:1 and beta');
      expect(result.caret, 28,
          reason: 'the caret lands past the reference so typing can continue');
    });

    test('a selection rather than a caret does not swallow the text', () {
      // Replacing a selection is not what this does: it inserts. Text the user
      // had highlighted is theirs until they delete it.
      final result = insertReferenceIntoPrompt(
        text: 'alpha beta',
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        reference: '/srv/app.ts:1',
      );

      expect(result.text, '/srv/app.ts:1 alpha beta');
    });

    test('a caret position outside the text lands at the end, not a crash', () {
      final result = insertReferenceIntoPrompt(
        text: 'short',
        selection: const TextSelection.collapsed(offset: 400),
        reference: '/srv/app.ts:1',
      );

      expect(result.text, 'short /srv/app.ts:1');
    });
  });
}
