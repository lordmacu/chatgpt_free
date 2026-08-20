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
            // A source is not an action. With no [onTap] this renders a plain
            // Chip: an ActionChip with an empty onPressed looks tappable and
            // does nothing, which reads as a broken button rather than a
            // citation — that is exactly how it was first reported.
            for (final c in citations)
              if (onTap == null)
                Chip(
                  avatar: const Icon(Icons.link, size: 16),
                  label: Text(c.title, overflow: TextOverflow.ellipsis),
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.link, size: 16),
                  tooltip: c.url,
                  label: Text(c.title, overflow: TextOverflow.ellipsis),
                  onPressed: () => onTap!(c),
                ),
          ],
        ),
      );
}
