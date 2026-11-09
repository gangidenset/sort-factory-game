import 'package:flutter/material.dart';

import '../app/services.dart';
import 'palette.dart';

/// Coin balance chip that rebuilds on progress changes.
class CoinChip extends StatelessWidget {
  const CoinChip({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.services.progress;
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on, color: AppColors.coin, size: 20),
            const SizedBox(width: 4),
            Text(
              '${progress.data.coins}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class StarRow extends StatelessWidget {
  const StarRow(this.stars, {super.key, this.size = 16});
  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Icon(
          i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: i < stars ? AppColors.coin : Colors.black26,
        ),
    ],
  );
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
}
