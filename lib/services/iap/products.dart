/// In-app product definitions.
///
/// Product IDs must be registered identically in Google Play Console and App
/// Store Connect. They are identifiers, not secrets. Prices shown in the UI
/// always come from the store; [referencePriceJpy] is documentation only.
class ProductDef {
  const ProductDef({
    required this.id,
    required this.title,
    required this.description,
    required this.referencePriceJpy,
    required this.entitlements,
    this.bonusCoins = 0,
  });

  final String id;
  final String title;
  final String description;
  final int referencePriceJpy;

  /// Entitlements granted by owning this (non-consumable) product.
  final Set<String> entitlements;

  /// Coins granted once, the first time the entitlement is added.
  final int bonusCoins;
}

class Products {
  const Products._();

  static const removeAds = ProductDef(
    id: 'remove_ads',
    title: '広告削除',
    description:
        'インタースティシャル広告を表示しません。\n'
        '（任意で見るリワード広告は引き続き利用できます）',
    referencePriceJpy: 600,
    entitlements: {'remove_ads'},
  );

  static const starterPack = ProductDef(
    id: 'starter_pack',
    title: '初心者応援パック',
    description: '1,500コイン + ミント工場スキン',
    referencePriceJpy: 300,
    entitlements: {'starter_pack', 'skin_mint'},
    bonusCoins: 1500,
  );

  static const neonSkin = ProductDef(
    id: 'factory_skin_neon',
    title: '工場スキン「ネオン」',
    description: '限定の工場スキン',
    referencePriceJpy: 150,
    entitlements: {'skin_neon'},
  );

  static const premiumPack = ProductDef(
    id: 'premium_pack',
    title: 'プレミアムパック',
    description: '広告削除 + ネオンスキン + 3,000コイン',
    referencePriceJpy: 800,
    entitlements: {'remove_ads', 'skin_neon', 'premium_pack'},
    bonusCoins: 3000,
  );

  /// Release 1 ships only [removeAds]; the rest are ready behind this list.
  static const enabled = [removeAds, starterPack, neonSkin, premiumPack];

  static ProductDef? byId(String id) {
    for (final p in enabled) {
      if (p.id == id) return p;
    }
    return null;
  }
}
