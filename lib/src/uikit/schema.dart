import '../core/errors.dart';

/// A screen described as JSON, and the state it operates on.
///
/// This is a deliberately tiny vocabulary. It exists to find out how well a
/// language model can describe a working interface, not to be a UI framework —
/// so every node type here is one a model can hold in its head, and anything
/// outside the vocabulary is a [ProtocolException] rather than a guess.
class UiSpec {
  /// Creates a spec.
  const UiSpec({required this.root, this.state = const {}, this.title});

  /// The widget tree.
  final UiNode root;

  /// Initial values for anything the tree binds to or an action mutates.
  final Map<String, String> state;

  /// Optional screen title.
  final String? title;

  /// Parses a decoded JSON map. Throws [ProtocolException] on anything it does
  /// not recognise — a generated interface that is half-understood is worse
  /// than one that refuses to render.
  factory UiSpec.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const ProtocolException('ui spec must be a JSON object');
    }
    final root = json['root'];
    if (root == null) {
      throw const ProtocolException('ui spec has no "root"');
    }
    return UiSpec(
      root: UiNode.fromJson(root),
      title: json['title'] as String?,
      state: {
        for (final e in ((json['state'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
    );
  }
}

/// One node of the tree.
class UiNode {
  /// Creates a node.
  const UiNode({
    required this.type,
    this.text,
    this.children = const [],
    this.actions = const [],
    this.stateKey,
    this.flex,
    this.gap,
    this.fontSize,
    this.bold = false,
    this.align,
    this.columns,
  });

  /// One of the supported node types; see [kSupportedNodeTypes].
  final String type;

  /// Literal text, or a template containing `{{stateKey}}` bindings.
  final String? text;

  /// Child nodes, for the layout types.
  final List<UiNode> children;

  /// What pressing this node does, for `button`.
  final List<UiAction> actions;

  /// State key this node writes to, for `textField`.
  final String? stateKey;

  /// Flex factor inside a `row` or `column`.
  final int? flex;

  /// Spacing between children, for layout types.
  final double? gap;

  /// Font size, for `text`.
  final double? fontSize;

  /// Whether `text` renders bold.
  final bool bold;

  /// `start`, `center` or `end`.
  final String? align;

  /// Column count, for `grid`.
  final int? columns;

  /// Every type this renderer understands.
  static const Set<String> kSupportedNodeTypes = {
    'column',
    'row',
    'grid',
    'container',
    'spacer',
    'text',
    'button',
    'textField',
  };

  /// Parses a node, rejecting unknown types.
  factory UiNode.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const ProtocolException('every ui node must be a JSON object');
    }
    final type = json['type'];
    if (type is! String || !kSupportedNodeTypes.contains(type)) {
      throw ProtocolException(
        'unsupported node type ${type ?? 'null'}; '
        'supported: ${(kSupportedNodeTypes.toList()..sort()).join(', ')}',
      );
    }
    return UiNode(
      type: type,
      text: json['text'] as String?,
      stateKey: json['stateKey'] as String?,
      flex: (json['flex'] as num?)?.toInt(),
      gap: (json['gap'] as num?)?.toDouble(),
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      bold: json['bold'] == true,
      align: json['align'] as String?,
      columns: (json['columns'] as num?)?.toInt(),
      children: [
        for (final child in (json['children'] as List?) ?? const [])
          UiNode.fromJson(child),
      ],
      actions: [
        for (final action in (json['actions'] as List?) ?? const [])
          UiAction.fromJson(action),
      ],
    );
  }
}

/// Something a button does to the state.
class UiAction {
  /// Creates an action.
  const UiAction({
    required this.type,
    required this.key,
    this.value,
    this.expr,
  });

  /// `set`, `append`, `clear`, `backspace` or `calc`.
  final String type;

  /// The state key this action writes.
  final String key;

  /// Literal value, for `set` and `append`.
  final String? value;

  /// Expression to evaluate, for `calc`. `{{key}}` bindings are substituted
  /// before evaluation.
  final String? expr;

  /// Every action this renderer understands.
  static const Set<String> kSupportedActions = {
    'set',
    'append',
    'clear',
    'backspace',
    'calc',
  };

  /// Parses an action, rejecting unknown types.
  factory UiAction.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const ProtocolException('every action must be a JSON object');
    }
    final type = json['type'];
    if (type is! String || !kSupportedActions.contains(type)) {
      throw ProtocolException(
        'unsupported action ${type ?? 'null'}; '
        'supported: ${(kSupportedActions.toList()..sort()).join(', ')}',
      );
    }
    final key = json['key'];
    if (key is! String || key.isEmpty) {
      throw ProtocolException('action "$type" needs a "key"');
    }
    return UiAction(
      type: type,
      key: key,
      value: json['value']?.toString(),
      expr: json['expr'] as String?,
    );
  }
}

final RegExp _binding = RegExp(r'\{\{(\w+)\}\}');

/// Substitutes `{{key}}` bindings from [state].
///
/// An unknown key becomes an empty string rather than an error: a model that
/// binds to a key it forgot to declare should render a blank, not refuse the
/// whole screen.
String resolveBindings(String template, Map<String, String> state) =>
    template.replaceAllMapped(_binding, (m) => state[m.group(1)] ?? '');
