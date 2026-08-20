import 'dart:convert';
import 'dart:io';

import 'package:chatgpt_free/src/core/sse/delta.dart';
import 'package:flutter_test/flutter_test.dart';

/// Extracts the JSON payload of every `event: delta` frame from a raw
/// captured SSE transcript, in order. Frames of other event types (or with
/// no event line at all, like `message_marker`/`[DONE]`) are skipped.
List<Map<String, dynamic>> _deltaFramesFrom(String sseContent) {
  final frames = <Map<String, dynamic>>[];
  String? currentEvent;
  final dataLines = <String>[];

  void flush() {
    if (currentEvent == 'delta' && dataLines.isNotEmpty) {
      final payload = jsonDecode(dataLines.join('\n'));
      if (payload is Map<String, dynamic>) frames.add(payload);
    }
    currentEvent = null;
    dataLines.clear();
  }

  for (final rawLine in const LineSplitter().convert(sseContent)) {
    final line = rawLine.trimRight();
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('event:')) {
      currentEvent = line.substring('event:'.length).trim();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring('data:'.length).trim());
    }
  }
  flush(); // in case the file doesn't end on a blank line

  return frames;
}

void main() {
  late DeltaApplier applier;

  setUp(() => applier = DeltaApplier());

  String textOf(DeltaApplier a) =>
      ((a.document['message'] as Map)['content'] as Map)['parts'][0] as String;

  test('add at the root seeds the document', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['']
          }
        }
      }
    });

    expect(textOf(applier), '');
  });

  test('append concatenates at an explicit path', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['']
          }
        }
      }
    });
    applier.apply({'p': '/message/content/parts/0', 'o': 'append', 'v': 'hola'});
    applier.apply({'p': '/message/content/parts/0', 'o': 'append', 'v': ' mundo'});

    expect(textOf(applier), 'hola mundo');
  });

  test('a delta with no path continues the previous path', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['']
          }
        }
      }
    });
    applier.apply({'p': '/message/content/parts/0', 'o': 'append', 'v': 'a'});
    applier.apply({'v': 'b'});
    applier.apply({'v': 'c'});

    expect(textOf(applier), 'abc');
  });

  test('replace overwrites, truncate cuts to length', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['abcdef']
          }
        }
      }
    });
    applier.apply({'p': '/message/content/parts/0', 'o': 'truncate', 'v': 3});
    expect(textOf(applier), 'abc');

    applier.apply({'p': '/message/content/parts/0', 'o': 'replace', 'v': 'zzz'});
    expect(textOf(applier), 'zzz');
  });

  test('patch applies a nested list of sub-deltas', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['']
          },
          'status': 'in_progress'
        }
      }
    });
    applier.apply({
      'p': '',
      'o': 'patch',
      'v': [
        {'p': '/message/status', 'o': 'replace', 'v': 'finished_successfully'},
        {'p': '/message/content/parts/0', 'o': 'append', 'v': 'listo'},
      ]
    });

    expect((applier.document['message'] as Map)['status'], 'finished_successfully');
    expect(textOf(applier), 'listo');
  });

  test('a list value with no operation is treated as a patch', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['']
          }
        }
      }
    });
    applier.apply({
      'v': [
        {'p': '/message/content/parts/0', 'o': 'append', 'v': 'x'}
      ]
    });

    expect(textOf(applier), 'x');
  });

  test('append creates missing intermediate containers', () {
    applier.apply({
      'p': '/message/metadata/content_references',
      'o': 'append',
      'v': [
        {'type': 'grouped_webpages'}
      ]
    });

    final refs = ((applier.document['message'] as Map)['metadata']
        as Map)['content_references'] as List;
    expect(refs.single['type'], 'grouped_webpages');
  });

  test('remove deletes a key without throwing on a missing one', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {'invalid': true}
      }
    });
    applier.apply({'p': '/message/invalid', 'o': 'remove'});
    applier.apply({'p': '/message/never_existed', 'o': 'remove'});

    expect((applier.document['message'] as Map).containsKey('invalid'), isFalse);
  });

  test('an unknown operation is ignored rather than fatal', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['ok']
          }
        }
      }
    });
    applier.apply({'p': '/message/content/parts/0', 'o': 'teleport', 'v': 'nope'});

    expect(textOf(applier), 'ok');
  });

  // Regression for Finding 1: an implicit-form delta (no 'o', no 'p') whose
  // path resolves to root ('') swaps in a whole new message shell. Real
  // streams do this repeatedly (user -> system rebases -> assistant) before
  // any streamed text arrives. The applier must replace the document at
  // root, not silently drop the swap while the stale message lingers.
  test('an implicit root swap replaces the message instead of leaving it stale', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'author': {'role': 'user'},
          'content': {
            'parts': ['echoed prompt']
          }
        }
      }
    });
    // No 'o', no 'p': continues the previous path, which is still '' right
    // after the initial root 'add' above.
    applier.apply({
      'v': {
        'message': {
          'author': {'role': 'assistant'},
          'content': {
            'parts': ['']
          }
        }
      }
    });
    applier.apply({'p': '/message/content/parts/0', 'o': 'append', 'v': 'hola mundo'});

    expect(textOf(applier), 'hola mundo');
    expect(
      ((applier.document['message'] as Map)['author'] as Map)['role'],
      'assistant',
    );
  });

  // Regression for Finding 2: the recursive apply() calls that walk a
  // patch's sub-deltas must not leak _lastPath past the patch. A bare
  // continuation delta right after a patch should land on the path that was
  // active before the patch, not on whatever the last sub-delta touched.
  test('a patch restores the pre-patch path for the next implicit continuation', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['']
          },
          'status': 'in_progress'
        }
      }
    });
    applier.apply({'p': '/message/content/parts/0', 'o': 'append', 'v': 'hello '});
    applier.apply({
      'p': '',
      'o': 'patch',
      'v': [
        {'p': '/message/status', 'o': 'replace', 'v': 'foo'},
      ]
    });
    applier.apply({'v': 'world'});

    expect(textOf(applier), 'hello world');
    expect((applier.document['message'] as Map)['status'], 'foo');
  });

  // The test that would have caught Finding 1: fold a real captured stream
  // (plain_text.sse) through the applier end-to-end and check the final
  // assembled text is exactly the assistant's reply, with no user-prompt
  // prefix left over from the message the stream started with.
  test('folds a captured stream into the assistant reply with no stale prefix', () {
    final content = File('test/fixtures/plain_text.sse').readAsStringSync();

    for (final delta in _deltaFramesFrom(content)) {
      applier.apply(delta);
    }

    expect(textOf(applier), 'hola mundo');
    expect(
      ((applier.document['message'] as Map)['author'] as Map)['role'],
      'assistant',
    );
  });

  // Regression for the fix-round-2 finding: the _lastPath save/restore
  // around a patch's sub-delta loop must run even if a sub-delta throws.
  // `sub is Map` only checks the Map interface, not that its keys are
  // Strings, so a sub-delta with a non-String key passes that check but
  // makes the recursive apply()'s own `Map<String, dynamic>.from(sub)`
  // throw a genuine TypeError — no artificial throw added to production
  // code, this is a real, reachable failure mode for a caller that passes
  // a malformed delta.
  test('a throwing sub-delta still restores the pre-patch path (finally)', () {
    applier.apply({
      'p': '',
      'o': 'add',
      'v': {
        'message': {
          'content': {
            'parts': ['']
          },
          'status': 'in_progress'
        }
      }
    });
    applier.apply({'p': '/message/content/parts/0', 'o': 'append', 'v': 'hello '});

    // The first sub-delta succeeds and moves _lastPath to /message/status
    // as a side effect (mirroring the earlier patch-leak scenario). The
    // second sub-delta has a non-String key: it passes the `sub is Map`
    // check in the patch loop but makes the recursive apply()'s own
    // `Map<String, dynamic>.from(sub)` throw a genuine TypeError before
    // that recursive call's body ever runs. No throw was added to
    // production code — this is a real, reachable failure mode for a
    // caller that passes a malformed delta list.
    final Map<dynamic, dynamic> subDeltaWithBadKey = <dynamic, dynamic>{1: 'oops'};
    expect(
      () => applier.apply({
        'p': '',
        'o': 'patch',
        'v': [
          {'p': '/message/status', 'o': 'replace', 'v': 'foo'},
          subDeltaWithBadKey,
        ],
      }),
      throwsA(isA<TypeError>()),
    );

    // Without the try/finally, _lastPath would still point at
    // /message/status (the last successful sub-delta's path) here, and this
    // continuation would corrupt status to 'fooworld' instead of extending
    // the text.
    applier.apply({'v': 'world'});

    expect(textOf(applier), 'hello world');
    expect((applier.document['message'] as Map)['status'], 'foo');
  });
}
