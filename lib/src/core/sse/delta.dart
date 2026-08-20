/// Applies the backend's JSON-Patch-style deltas to an in-memory document.
///
/// The stream sends compact keys (`p` path, `o` operation, `v` value, `c`
/// channel index) and leans on two implicit forms: a value with no operation
/// is an append continuing the previous path, and a list value with no
/// operation is a patch. Both are the common case, not edge cases.
class DeltaApplier {
  final Map<String, dynamic> _document = <String, dynamic>{};
  String _lastPath = '';

  /// The document assembled so far.
  Map<String, dynamic> get document => _document;

  /// Applies one delta. Unknown operations and paths are ignored, never fatal —
  /// the protocol grows without warning and a new channel must not kill a turn.
  void apply(Map<String, dynamic> delta) {
    final op = (delta['o'] ?? delta['operation'] ?? '').toString().toLowerCase();
    final rawPath = delta['p'] ?? delta['path'];
    final value = delta.containsKey('v') ? delta['v'] : delta['value'];

    if (op == 'patch' || (op.isEmpty && value is List && rawPath == null)) {
      // Sub-deltas are applied through the same apply() path-tracking
      // machinery, so they mutate _lastPath as a side effect. Save and
      // restore it around the loop so a patch never leaks its last
      // sub-delta's path out to whatever implicit-form delta follows it.
      final savedLastPath = _lastPath;
      for (final sub in (value as List)) {
        if (sub is Map) apply(Map<String, dynamic>.from(sub));
      }
      _lastPath = savedLastPath;
      return;
    }

    final path = rawPath?.toString() ?? _lastPath;
    if (rawPath != null) _lastPath = path;

    final effectiveOp = op.isEmpty ? 'append' : op;

    switch (effectiveOp) {
      case 'add':
      case 'replace':
        _write(path, value);
      case 'append':
        _append(path, value);
      case 'truncate':
        if (value is int) {
          final current = _read(path);
          if (current is String && value <= current.length) {
            _write(path, current.substring(0, value));
          } else if (current is List && value <= current.length) {
            _write(path, current.sublist(0, value));
          }
        }
      case 'remove':
        _remove(path);
      default:
        return; // unknown operation: ignore
    }
  }

  List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  dynamic _read(String path) {
    dynamic node = _document;
    for (final seg in _segments(path)) {
      if (node is Map && node.containsKey(seg)) {
        node = node[seg];
      } else if (node is List) {
        final i = int.tryParse(seg);
        if (i == null || i < 0 || i >= node.length) return null;
        node = node[i];
      } else {
        return null;
      }
    }
    return node;
  }

  /// Walks to the parent of [segments], creating maps and growing lists as needed.
  dynamic _parentOf(List<String> segments) {
    dynamic node = _document;
    for (var i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      final nextIsIndex = int.tryParse(segments[i + 1]) != null;
      if (node is Map) {
        node[seg] ??= nextIsIndex ? <dynamic>[] : <String, dynamic>{};
        node = node[seg];
      } else if (node is List) {
        final idx = int.tryParse(seg);
        if (idx == null) return null;
        while (node.length <= idx) {
          node.add(nextIsIndex ? <dynamic>[] : <String, dynamic>{});
        }
        node = node[idx];
      } else {
        return null;
      }
    }
    return node;
  }

  void _write(String path, dynamic value) {
    final segments = _segments(path);
    if (segments.isEmpty) {
      // A root path means "replace the whole document". This is reachable
      // both explicitly (o: 'add'/'replace' with p: '') and implicitly
      // (a value-only delta whose _lastPath is still '' — the backend's
      // common way to swap in a whole new message shell mid-stream).
      // Silently bailing here — the original bug — meant _append's root
      // merge was computed and then discarded.
      if (value is Map) {
        _document
          ..clear()
          ..addAll(Map<String, dynamic>.from(value));
      }
      return;
    }
    final parent = _parentOf(segments);
    final last = segments.last;
    if (parent is Map) {
      parent[last] = value;
    } else if (parent is List) {
      final idx = int.tryParse(last);
      if (idx == null) return;
      while (parent.length <= idx) {
        parent.add(null);
      }
      parent[idx] = value;
    }
  }

  void _append(String path, dynamic value) {
    final current = _read(path);
    if (current is String && value is String) {
      _write(path, current + value);
    } else if (current is List && value is List) {
      _write(path, [...current, ...value]);
    } else if (current is List) {
      _write(path, [...current, value]);
    } else if (current is Map && value is Map) {
      _write(path, {...current, ...Map<String, dynamic>.from(value)});
    } else if (current == null) {
      _write(path, value);
    } else {
      _write(path, value);
    }
  }

  void _remove(String path) {
    final segments = _segments(path);
    if (segments.isEmpty) return;
    final parent = _parentOf(segments);
    final last = segments.last;
    if (parent is Map) {
      parent.remove(last);
    } else if (parent is List) {
      final idx = int.tryParse(last);
      if (idx != null && idx >= 0 && idx < parent.length) parent.removeAt(idx);
    }
  }
}
