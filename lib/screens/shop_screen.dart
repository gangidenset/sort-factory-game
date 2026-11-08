import 'package:flutter/material.dart';

import '../app/services.dart';
import '../services/iap/products.dart';
import '../services/iap/purchase_service.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  PurchaseService? _iap;
  String? _shownMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final iap = context.services.purchases;
    if (iap != _iap) {
      _iap?.removeListener(_onIap);
      _iap = iap..addListener(_onIap);
    }
  }

  @override
  void dispose() {
    _iap?.removeListener(_onIap);
    super.dispose();
  }

  void _onIap() {
    final msg = _iap?.lastMessage;
    if (msg != null && msg != _shownMessage && mounted) {
      _shownMessage = msg;
      showSnack(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.services;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ショップ'),
        actions: const [CoinChip(), SizedBox(width: 12)],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([svc.purchases, svc.progress]),
        builder: (context, _) {
          final iap = svc.purchases;
          final owned = svc.progress.data.entitlements;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!iap.storeAvailable)
                const Card(
                  color: Color(0xFFFFF4E5),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'ストアに接続できないため、現在購入できません。\n'
                      '通信環境を確認するか、しばらくしてからお試しください。',
                    ),
                  ),
                ),
              for (final def in Products.enabled)
                _ProductCard(
                  def: def,
                  store: iap.products
                      .where((p) => p.def.id == def.id)
                      .firstOrNull,
                  owned: def.entitlements.every(owned.contains),
                  pending: iap.state == PurchaseUiState.pending,
                  onBuy: () => iap.buy(def.id),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: iap.storeAvailable ? iap.restore : null,
                icon: const Icon(Icons.restore),
                label: const Text('購入を復元'),
              ),
              const SizedBox(height: 12),
              const Text(
                '・価格はストアに表示される金額が適用されます。\n'
                '・広告削除後も、報酬がもらえる広告（任意）は利用できます。\n'
                '・機種変更時は「購入を復元」で購入済みの商品を復元できます。',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.def,
    required this.store,
    required this.owned,
    required this.pending,
    required this.onBuy,
  });

  final ProductDef def;
  final StoreProduct? store;
  final bool owned;
  final bool pending;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final icon = switch (def.id) {
      'remove_ads' => Icons.block,
      'starter_pack' => Icons.rocket_launch,
      'factory_skin_neon' => Icons.palette,
      _ => Icons.workspace_premium,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    def.description,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (owned)
              const Text(
                '購入済み',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w900,
                ),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(84, 44)),
                onPressed: store == null || pending ? null : onBuy,
                child: Text(store?.price ?? '---'),
              ),
          ],
        ),
      ),
    );
  }
}
