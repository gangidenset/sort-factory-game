import 'package:flutter/material.dart';

import '../app/services.dart';
import '../economy/economy.dart';
import '../ui/palette.dart';
import '../ui/strings.dart';
import '../ui/widgets.dart';
import 'factory_screen.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'stage_select_screen.dart';

class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key});

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final svc = context.services;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: svc.progress,
          builder: (context, _) {
            final p = svc.progress;
            final xp = p.data.xp;
            // "Play" continues from the first uncleared stage.
            final nextStage = svc.stages.stages.firstWhere(
              (s) => !(p.recordOf(s.id)?.cleared ?? false),
              orElse: () => svc.stages.stages.last,
            );
            return LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _LevelBadge(
                                level: p.level,
                                progress: Economy.levelProgress(xp),
                              ),
                              const Spacer(),
                              const CoinChip(),
                              IconButton(
                                onPressed: () =>
                                    _push(context, const SettingsScreen()),
                                icon: const Icon(Icons.settings),
                                tooltip: S.settings,
                              ),
                            ],
                          ),
                          const Spacer(),
                          _Logo(compact: box.maxHeight < 640),
                          const SizedBox(height: 8),
                          const Text(
                            S.tagline,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black54,
                            ),
                          ),
                          const Spacer(),
                          _MissionCard(),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _push(context, GameScreen(stage: nextStage)),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 32,
                              ),
                              label: Text(
                                '${S.play}  STAGE ${nextStage.id}',
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MenuButton(
                                  icon: Icons.grid_view_rounded,
                                  label: S.stages,
                                  onTap: () =>
                                      _push(context, const StageSelectScreen()),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _MenuButton(
                                  icon: Icons.factory_rounded,
                                  label: S.factory,
                                  onTap: () =>
                                      _push(context, const FactoryScreen()),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _MenuButton(
                                  icon: Icons.storefront_rounded,
                                  label: S.shop,
                                  onTap: () =>
                                      _push(context, const ShopScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in [0, 1, 2, 3])
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: packageColors[c],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'SORT\nFACTORY',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 36 : 48,
          height: 1.0,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
          letterSpacing: 2,
        ),
      ),
    ],
  );
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.progress});
  final int level;
  final double progress;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Lv.$level', style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    ),
  );
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Icon(icon, size: 30, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    ),
  );
}

class _MissionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    final missions = p.missions();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              S.missions,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            for (final m in missions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      m.claimed
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: m.claimed ? AppColors.success : Colors.black38,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        m.def.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (m.complete && !m.claimed)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => p.claimMission(m.def.id),
                        child: Text('+${m.def.reward}'),
                      )
                    else
                      Text(
                        m.claimed
                            ? '受取済'
                            : '${m.progress.clamp(0, m.def.goal)}/${m.def.goal}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
