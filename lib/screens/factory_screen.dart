import 'package:flutter/material.dart';

import '../app/services.dart';
import '../economy/catalog.dart';
import '../services/audio/audio_service.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';

/// Factory growth: upgrades (gameplay assists) and cosmetics (collection).
class FactoryScreen extends StatelessWidget {
  const FactoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('工場'),
          actions: const [CoinChip(), SizedBox(width: 12)],
          bottom: const TabBar(
            tabs: [
              Tab(text: '設備強化'),
              Tab(text: '外観'),
              Tab(text: 'コレクション'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_UpgradesTab(), _SkinsTab(), _CollectionTab()],
        ),
      ),
    );
  }
}

class _FactoryPreview extends StatelessWidget {
  const _FactoryPreview();

  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    final skin = FactorySkin.fromId(p.data.equippedSkin);
    final decos = cosmeticDefs
        .where((c) => c.type == CosmeticType.decoration && p.isOwned(c.id))
        .toList();
    return Container(
      height: 120,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skin.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: skin.accent, width: 3),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: skin.belt,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          Positioned(
            left: 30,
            bottom: 36,
            child: Row(
              children: [
                for (final c in [0, 1, 2])
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: packageColors[c],
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            top: 10,
            child: Row(
              children: [
                for (final d in decos)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      _decoIcon(d.id),
                      color: Color(d.colors.first),
                      size: 26,
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            top: 10,
            child: Text(
              'Lv.${p.level} 工場',
              style: TextStyle(
                color: skin.onBackground,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _decoIcon(String id) => switch (id) {
  'deco_plant' => Icons.local_florist,
  'deco_flag' => Icons.flag,
  'deco_clock' => Icons.schedule,
  'deco_robot' => Icons.smart_toy,
  'deco_trophy' => Icons.emoji_events,
  _ => Icons.star,
};

class _UpgradesTab extends StatelessWidget {
  const _UpgradesTab();

  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => ListView(
        children: [
          const _FactoryPreview(),
          for (final u in upgradeDefs)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                title: Text(
                  '${u.name}  Lv.${p.data.upgradeLevel(u.id)}/${u.maxLevel}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(u.description),
                trailing: _buyButton(context, u),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '設備強化はプレイを助けるものです。強化しなくても全ステージをクリアできます。',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buyButton(BuildContext context, UpgradeDef u) {
    final p = context.services.progress;
    final cost = u.costForNext(p.data.upgradeLevel(u.id));
    if (cost == null) {
      return const Text('MAX', style: TextStyle(fontWeight: FontWeight.w900));
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
      onPressed: p.data.coins >= cost
          ? () async {
              if (await p.buyUpgrade(u.id) && context.mounted) {
                context.services.audio.feedback(Sfx.truck);
                showSnack(context, '${u.name}を強化しました');
              }
            }
          : null,
      icon: const Icon(Icons.monetization_on, size: 18),
      label: Text('$cost'),
    );
  }
}

class _CosmeticGrid extends StatelessWidget {
  const _CosmeticGrid({required this.types});
  final Set<CosmeticType> types;

  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final items = cosmeticDefs
            .where((c) => types.contains(c.type))
            .toList();
        return GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: [for (final c in items) _CosmeticCard(def: c)],
        );
      },
    );
  }
}

class _CosmeticCard extends StatelessWidget {
  const _CosmeticCard({required this.def});
  final CosmeticDef def;

  String _unlockText(Unlock u) => switch (u) {
    CoinUnlock(:final cost) => '$cost コイン',
    StageUnlock(:final stageId) => 'ステージ$stageIdクリア',
    StarsUnlock(:final stars) => '★を$stars個集める',
    PurchaseUnlock() => 'ショップで入手',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    final owned = p.isOwned(def.id);
    final equipped =
        p.data.equippedSkin == def.id || p.data.equippedBox == def.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(child: Center(child: _preview())),
            Text(def.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (equipped)
              const Text(
                '使用中',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                ),
              )
            else if (owned && def.type != CosmeticType.decoration)
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: () => p.equip(def.id),
                child: const Text('使う'),
              )
            else if (owned)
              const Text(
                '設置済み',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                ),
              )
            else if (def.unlock case CoinUnlock(:final cost))
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                onPressed: p.data.coins >= cost
                    ? () => p.buyCosmetic(def.id)
                    : null,
                child: Text('$cost コイン'),
              )
            else
              Text(
                _unlockText(def.unlock),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    switch (def.type) {
      case CosmeticType.factorySkin:
        return Container(
          width: 80,
          height: 56,
          decoration: BoxDecoration(
            color: Color(def.colors[0]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Color(def.colors[2]), width: 3),
          ),
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.all(8),
          child: Container(height: 10, color: Color(def.colors[1])),
        );
      case CosmeticType.boxDesign:
        final round = def.id == 'box_round';
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: packageColors[1],
            borderRadius: BorderRadius.circular(round ? 26 : 10),
            border: def.id == 'box_gold'
                ? Border.all(color: const Color(0xFFFFD54F), width: 4)
                : null,
          ),
          child: switch (def.id) {
            'box_gift' => const Icon(Icons.card_giftcard, color: Colors.white),
            'box_crate' => const Icon(
              Icons.view_headline,
              color: Colors.white70,
            ),
            _ => null,
          },
        );
      case CosmeticType.decoration:
        return Icon(
          _decoIcon(def.id),
          size: 48,
          color: Color(def.colors.first),
        );
    }
  }
}

class _SkinsTab extends StatelessWidget {
  const _SkinsTab();
  @override
  Widget build(BuildContext context) => const _CosmeticGrid(
    types: {CosmeticType.factorySkin, CosmeticType.decoration},
  );
}

class _CollectionTab extends StatelessWidget {
  const _CollectionTab();
  @override
  Widget build(BuildContext context) =>
      const _CosmeticGrid(types: {CosmeticType.boxDesign});
}
