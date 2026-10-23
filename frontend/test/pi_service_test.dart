import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile_agent/models/pi_models.dart';
import 'package:pi_mobile_agent/services/pi_service.dart';

/// Mirrors the shape of a real backend reply (backend/src/index.ts):
/// every command answer is an envelope with the payload under `data`.
Map<String, dynamic> envelope(Map<String, dynamic> data) => {
      'type': 'response',
      'id': 'test-id',
      'command': 'list_dir',
      'success': true,
      'data': data,
    };

const listDirPayload = {
  'path': '/home/adam',
  'parent': '/home',
  'roots': [
    {'name': '/', 'path': '/'},
  ],
  'entries': [
    {'name': 'source', 'path': '/home/adam/source'},
    {'name': 'Documents', 'path': '/home/adam/Documents'},
  ],
  'current': '/home/adam',
  'cwdDisplay': '~',
  'recent': ['/home/adam/source/repos'],
};

void main() {
  group('PiService.unwrapData', () {
    test('returns the payload carried by the response envelope', () {
      final data =
          PiService.unwrapData(envelope({...listDirPayload}), command: 'list_dir');
      final listing = DirListing.fromJson(data);

      expect(listing.path, '/home/adam');
      expect(listing.entries.map((e) => e.name), ['source', 'Documents']);
      expect(listing.current, '/home/adam');
      expect(listing.cwdDisplay, '~');
      expect(listing.roots.single.path, '/');
    });

    test('parsing the envelope itself is empty - the directory-browser bug',
        () {
      // Regression guard: list_dir must never be parsed from the envelope,
      // otherwise the browser renders "No subdirectories here" for every folder.
      final listing = DirListing.fromJson(envelope({...listDirPayload}));

      expect(listing.entries, isEmpty);
      expect(listing.path, isEmpty);
      expect(listing.roots, isEmpty);
    });

    test('throws with the backend error message', () {
      expect(
        () => PiService.unwrapData(
          {
            'type': 'response',
            'id': 'x',
            'command': 'list_dir',
            'success': false,
            'error': 'Not a directory: ~',
          },
          command: 'list_dir',
        ),
        throwsA(predicate((e) => e is Exception && '$e'.contains('Not a directory'))),
      );
    });

    test('commands without a payload unwrap to an empty map', () {
      expect(
        PiService.unwrapData(
          {'type': 'response', 'success': true, 'command': 'abort'},
          command: 'abort',
        ),
        isEmpty,
      );
    });
  });

  group('PiState', () {
    test('reads the working directory the backend reports', () {
      final state = PiState.fromJson({
        'model': {'id': 'qwen 3.8 Strata'},
        'cwd': '/home/adam',
        'cwdDisplay': '~',
        'messageCount': 3,
      });

      expect(state.currentModel, 'qwen 3.8 Strata');
      expect(state.cwd, '/home/adam');
      expect(state.cwdDisplay, '~');
    });
  });
}
