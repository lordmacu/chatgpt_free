import 'package:chatgpt_free/src/core/sse/delta.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
