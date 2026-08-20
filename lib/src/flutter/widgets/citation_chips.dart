import 'package:flutter/material.dart';

import '../../core/models/models.dart';

/// The sources behind an answer, one chip each.
class CitationChips extends StatelessWidget {
  /// Creates the chip row.
  const CitationChips({required this.citations, this.onTap, super.key});

  /// Sources to show.
  final List<Citation> citations;

  /// Called with the citation the user tapped.
  final ValueChanged<Citation>? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final c in citations)
              ActionChip(
                label: Text(c.title, overflow: TextOverflow.ellipsis),
                onPressed: onTap == null ? () {} : () => onTap!(c),
              ),
          ],
        ),
      );
}
