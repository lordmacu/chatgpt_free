import 'package:flutter/material.dart';

import '../core/errors.dart';
import 'expression.dart';
import 'schema.dart';

/// Renders a [UiSpec] as real Flutter widgets, and runs its actions.
///
/// State lives here, not in the spec: the spec's `state` map is the starting
/// point, and actions mutate this widget's copy. Nothing is evaluated except
/// the arithmetic in a `calc` action — there is no code execution path from a
/// generated document into the host app.
class JsonUiView extends StatefulWidget {
  /// Creates a view over [spec].
  const JsonUiView({required this.spec, this.onError, super.key});

  /// The interface to render.
  final UiSpec spec;

  /// Called when an action fails — a malformed expression, a division by zero.
  /// Failures never crash the view; the state simply does not change.
  final ValueChanged<ChatGptException>? onError;

  @override
  State<JsonUiView> createState() => _JsonUiViewState();
}

class _JsonUiViewState extends State<JsonUiView> {
  late Map<String, String> _state = {...widget.spec.state};

  // One controller per bound field, kept for the life of the screen. Building
  // a fresh controller on every build would drop the caret to the start of the
  // line on the keystroke after any rebuild — and every action rebuilds.
  final Map<String, TextEditingController> _controllers = {};

  @override
  void didUpdateWidget(covariant JsonUiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new spec is a new screen, so it starts from its own initial state.
    if (!identical(oldWidget.spec, widget.spec)) {
      _state = {...widget.spec.state};
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Pushes state an action changed back into the fields bound to it — a
  /// `clear` on a key a `textField` writes has to empty the field too.
  void _syncControllers() {
    for (final entry in _controllers.entries) {
      final value = _state[entry.key] ?? '';
      if (entry.value.text != value) {
        entry.value.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    }
  }

  void _run(List<UiAction> actions) {
    final next = {..._state};
    try {
      for (final action in actions) {
        final current = next[action.key] ?? '';
        switch (action.type) {
          case 'set':
            next[action.key] = action.value ?? '';
          case 'append':
            next[action.key] = '$current${action.value ?? ''}';
          case 'clear':
            next[action.key] = '';
          case 'backspace':
            next[action.key] =
                current.isEmpty ? '' : current.substring(0, current.length - 1);
          case 'calc':
            final source = resolveBindings(action.expr ?? current, next);
            next[action.key] = formatNumber(evaluateExpression(source));
        }
      }
    } on ChatGptException catch (e) {
      // A generated interface that computes nonsense must not take the app
      // down with it. Report and leave the state as it was.
      widget.onError?.call(e);
      return;
    }
    setState(() => _state = next);
    _syncControllers();
  }

  @override
  Widget build(BuildContext context) => _build(widget.spec.root);

  Widget _build(UiNode node) {
    final child = switch (node.type) {
      'text' => _text(node),
      'button' => _button(node),
      'textField' => _textField(node),
      'spacer' => const Spacer(),
      'container' => Padding(
          padding: EdgeInsets.all(node.gap ?? 8),
          child: node.children.isEmpty
              ? const SizedBox.shrink()
              : _build(node.children.first),
        ),
      'row' => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _spaced(node, horizontal: true),
        ),
      'column' => Column(
          crossAxisAlignment: _cross(node.align),
          mainAxisSize: MainAxisSize.min,
          children: _spaced(node, horizontal: false),
        ),
      'grid' => _grid(node),
      _ => const SizedBox.shrink(),
    };

    final flex = node.flex;
    return flex == null ? child : Expanded(flex: flex, child: child);
  }

  CrossAxisAlignment _cross(String? align) => switch (align) {
        'center' => CrossAxisAlignment.center,
        'end' => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      };

  List<Widget> _spaced(UiNode node, {required bool horizontal}) {
    final gap = node.gap ?? 0;
    final out = <Widget>[];
    for (final (i, child) in node.children.indexed) {
      if (i > 0 && gap > 0) {
        out.add(SizedBox(
          width: horizontal ? gap : null,
          height: horizontal ? null : gap,
        ));
      }
      out.add(_build(child));
    }
    return out;
  }

  Widget _grid(UiNode node) {
    final columns = (node.columns ?? 4).clamp(1, 8);
    final gap = node.gap ?? 8;
    final rows = <Widget>[];
    for (var i = 0; i < node.children.length; i += columns) {
      final slice = node.children.skip(i).take(columns).toList();
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
        child: Row(
          children: [
            for (final (j, cell) in slice.indexed) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(child: _build(cell)),
            ],
            // Keep the last row's cells the same width as a full row's.
            for (var pad = slice.length; pad < columns; pad++) ...[
              SizedBox(width: gap),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _text(UiNode node) => Text(
        resolveBindings(node.text ?? '', _state),
        textAlign: switch (node.align) {
          'center' => TextAlign.center,
          'end' => TextAlign.right,
          _ => TextAlign.left,
        },
        style: TextStyle(
          fontSize: node.fontSize,
          fontWeight: node.bold ? FontWeight.bold : null,
        ),
      );

  Widget _button(UiNode node) => FilledButton.tonal(
        onPressed: node.actions.isEmpty ? null : () => _run(node.actions),
        child: Text(resolveBindings(node.text ?? '', _state)),
      );

  Widget _textField(UiNode node) {
    final key = node.stateKey;
    return TextField(
      controller: key == null
          ? null
          : _controllers.putIfAbsent(
              key,
              () => TextEditingController(text: _state[key] ?? ''),
            ),
      decoration: InputDecoration(
        labelText: node.text,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: key == null
          ? null
          : (value) => setState(() => _state = {..._state, key: value}),
    );
  }
}
