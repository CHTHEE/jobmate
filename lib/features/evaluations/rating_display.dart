import 'package:flutter/material.dart';

String formatRating(num score) => '${score.toStringAsFixed(2)} / 5';

class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating});

  final num rating;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Wrap(
      children: [
        for (var index = 0; index < 5; index++)
          Stack(
            children: [
              const Icon(Icons.star_border, size: 22),
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: (rating - index).clamp(0, 1).toDouble(),
                  child: Icon(
                    Icons.star,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class RatingBreakdownRow extends StatelessWidget {
  const RatingBreakdownRow({
    super.key,
    required this.label,
    required this.rating,
    this.notObserved = false,
  });

  final String label;
  final num? rating;
  final bool notObserved;

  @override
  Widget build(BuildContext context) {
    final score = rating;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              Text(label),
              Text(
                notObserved
                    ? 'Not Observed'
                    : score == null
                    ? 'No ratings'
                    : formatRating(score),
              ),
            ],
          ),
          if (!notObserved && score != null) ...[
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: LinearProgressIndicator(value: score.toDouble() / 5),
            ),
          ],
        ],
      ),
    );
  }
}
