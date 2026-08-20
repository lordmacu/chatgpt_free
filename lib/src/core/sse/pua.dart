/// A Private Use Area marker found in assistant text.
class PuaMarker {
  /// Creates a marker.
  const PuaMarker({
    required this.kind,
    required this.ref,
    required this.start,
    required this.end,
  });

  /// Marker kind, e.g. `cite` or `genui`.
  final String kind;

  /// Payload between the separator and the closing marker.
  final String ref;

  /// Index of the opening marker in the source text.
  final int start;

  /// Index just past the closing marker in the source text.
  final int end;
}

final RegExp _structured =
    RegExp('\u{e200}([^\u{e202}]*)\u{e202}(.*?)\u{e201}', dotAll: true);
final RegExp _strayPua = RegExp('[\u{e000}-\u{f8ff}]');

/// Removes every PUA marker, returning text safe to render.
String stripPuaMarkers(String text) =>
    text.replaceAll(_structured, '').replaceAll(_strayPua, '');

/// Lists the structured markers in [text] with their offsets.
List<PuaMarker> findPuaMarkers(String text) => _structured
    .allMatches(text)
    .map((m) => PuaMarker(
          kind: m.group(1) ?? '',
          ref: m.group(2) ?? '',
          start: m.start,
          end: m.end,
        ))
    .toList();
