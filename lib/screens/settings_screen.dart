import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/services.dart';
import '../services/ads/ad_config.dart';
import '../services/analytics/analytics.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.services;
    final p = svc.progress;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListenableBuilder(
        listenable: p,
        builder: (context, _) {
          final s = p.data.settings;
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('効果音'),
                value: s.sound,
                onChanged: (v) => p.updateSettings((s) => s.sound = v),
              ),
              SwitchListTile(
                title: const Text('振動'),
                value: s.haptics,
                onChanged: (v) => p.updateSettings((s) => s.haptics = v),
              ),
              SwitchListTile(
                title: const Text('序盤のヒント表示'),
                subtitle: const Text('ステージ1〜2で正しい仕分け先を光らせます'),
                value: s.showHints,
                onChanged: (v) => p.updateSettings((s) => s.showHints = v),
              ),
              if (!p.data.adsRemoved)
                ListTile(
                  title: const Text('広告の表示頻度'),
                  subtitle: Text('ステージクリア ${s.interstitialEvery} 回ごと（最短3分間隔）'),
                  trailing: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 4, label: Text('標準')),
                      ButtonSegment(value: 6, label: Text('少')),
                      ButtonSegment(value: 8, label: Text('最少')),
                    ],
                    selected: {s.interstitialEvery},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) =>
                        p.updateSettings((s) => s.interstitialEvery = v.first),
                  ),
                ),
              if (svc.ads.service.privacyOptionsRequired)
                ListTile(
                  title: const Text('プライバシー設定（広告の同意）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: svc.ads.service.showPrivacyOptions,
                ),
              const Divider(),
              ListTile(
                title: const Text('プレイ記録'),
                subtitle: Text(
                  'プレイ日数 ${p.data.stats.daysPlayed}日 / '
                  '累計配送 ${p.data.stats.totalDeliveries}個 / '
                  '★ ${p.data.totalStars}',
                ),
              ),
              const AboutListTile(
                applicationName: 'SORT FACTORY',
                applicationVersion: '0.1.0 (MVP)',
                child: Text('このアプリについて / ライセンス'),
              ),
              if (kDebugMode) _DebugPanel(analytics: svc.analytics),
            ],
          );
        },
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.analytics});
  final Analytics analytics;

  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    final recent = analytics is DebugAnalytics
        ? (analytics as DebugAnalytics).recent.reversed.take(20).toList()
        : const <String>[];
    return ExpansionTile(
      title: const Text('DEBUG'),
      children: [
        ListTile(
          title: Text(
            'Ads: ${AdConfig.enabled ? (AdConfig.useTestAds ? "TEST IDs" : "PROD IDs") : "disabled"}',
          ),
        ),
        ListTile(
          title: const Text('+1000 コイン (debug only)'),
          onTap: () => p.addCoins(1000),
        ),
        for (final e in recent)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              e,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
      ],
    );
  }
}
