import 'package:flutter/material.dart';

import '../app/services.dart';
import '../game/logic/stage_config.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'game_screen.dart';

class StageSelectScreen extends StatelessWidget {
  const StageSelectScreen({super.key});

  static const _diffColors = {
    Difficulty.easy: AppColors.success,
    Difficulty.normal: AppColors.primary,
    Difficulty.hard: AppColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final svc = context.services;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ステージ選択'),
        actions: const [CoinChip(), SizedBox(width: 12)],
      ),
      body: ListenableBuilder(
        listenable: svc.progress,
        builder: (context, _) => CustomScrollView(
          slivers: [
            for (final diff in Difficulty.values) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    diff.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _diffColors[diff],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.count(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.8,
                  children: [
                    for (final s in svc.stages.stages.where(
                      (s) => s.difficulty == diff,
                    ))
                      _StageTile(stage: s, color: _diffColors[diff]!),
                  ],
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.stage, required this.color});
  final StageConfig stage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    final unlocked = p.isUnlocked(stage.id);
    final rec = p.recordOf(stage.id);
    return Material(
      color: unlocked ? Colors.white : Colors.white54,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: unlocked
            ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GameScreen(stage: stage)),
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (unlocked)
              Text(
                '${stage.id}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              )
            else
              const Icon(Icons.lock, color: Colors.black26),
            const SizedBox(height: 4),
            StarRow(rec?.stars ?? 0, size: 13),
          ],
        ),
      ),
    );
  }
}
