import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../data/progress_controller.dart';
import '../analytics/analytics.dart';
import 'products.dart';

class StoreProduct {
  const StoreProduct(this.def, this.price);
  final ProductDef def;

  /// Localized price string from the store.
  final String price;
}

enum PurchaseUiState { idle, pending, purchased, restored, error, canceled }

/// Abstract purchase backend.
abstract class PurchaseService extends ChangeNotifier {
  /// False when the store is unreachable or not configured. The UI must then
  /// show the shop as unavailable; purchases are never simulated.
  bool get storeAvailable;
  List<StoreProduct> get products;
  PurchaseUiState get state;
  String? get lastMessage;

  Future<void> initialize();
  Future<void> buy(String productId);
  Future<void> restore();
}

/// Applies a confirmed purchase to local state. Idempotent: restoring the same
/// product again does not grant coins twice.
Future<void> grantProduct(ProgressController progress, ProductDef def) =>
    progress.setEntitlements(def.entitlements, bonusCoins: def.bonusCoins);

/// Google Play Billing / StoreKit implementation via `in_app_purchase`.
///
/// MVP note: purchases are trusted on-device. Before scaling, add server-side
/// receipt verification (see docs/MONETIZATION.md).
class StorePurchaseService extends PurchaseService {
  StorePurchaseService(this._progress, this._analytics);

  final ProgressController _progress;
  final Analytics _analytics;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  List<StoreProduct> _products = const [];
  PurchaseUiState _state = PurchaseUiState.idle;
  String? _message;

  @override
  bool get storeAvailable => _available;
  @override
  List<StoreProduct> get products => _products;
  @override
  PurchaseUiState get state => _state;
  @override
  String? get lastMessage => _message;

  @override
  Future<void> initialize() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) {
        notifyListeners();
        return;
      }
      _sub = _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) =>
            _setState(PurchaseUiState.error, '購入処理でエラーが発生しました'),
      );
      final resp = await _iap.queryProductDetails(
        Products.enabled.map((p) => p.id).toSet(),
      );
      if (resp.notFoundIDs.isNotEmpty) {
        debugPrint('IAP products not found in store: ${resp.notFoundIDs}');
      }
      _products = [
        for (final d in resp.productDetails)
          if (Products.byId(d.id) case final def?) StoreProduct(def, d.price),
      ];
      _details = {for (final d in resp.productDetails) d.id: d};
    } catch (e) {
      debugPrint('IAP init failed: $e');
      _available = false;
    }
    notifyListeners();
  }

  Map<String, ProductDetails> _details = {};

  @override
  Future<void> buy(String productId) async {
    final details = _details[productId];
    if (!_available || details == null) {
      _setState(PurchaseUiState.error, 'ストアに接続できません');
      return;
    }
    _analytics.log('purchase_start', {'product': productId});
    _setState(PurchaseUiState.pending, null);
    try {
      // All current products are non-consumable (one-time unlocks).
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
    } catch (e) {
      _setState(PurchaseUiState.error, '購入を開始できませんでした');
    }
  }

  @override
  Future<void> restore() async {
    if (!_available) {
      _setState(PurchaseUiState.error, 'ストアに接続できません');
      return;
    }
    _setState(PurchaseUiState.pending, null);
    try {
      await _iap.restorePurchases();
      // Restored items arrive on the purchase stream.
      if (_state == PurchaseUiState.pending) {
        _setState(PurchaseUiState.idle, '復元処理を行いました');
      }
    } catch (e) {
      _setState(PurchaseUiState.error, '復元に失敗しました');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      final def = Products.byId(p.productID);
      switch (p.status) {
        case PurchaseStatus.pending:
          _setState(PurchaseUiState.pending, '購入処理中…');
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (def != null) {
            await grantProduct(_progress, def);
            _analytics.log(
              p.status == PurchaseStatus.purchased
                  ? 'purchase_complete'
                  : 'purchase_restored',
              {'product': def.id},
            );
          }
          _setState(
            p.status == PurchaseStatus.purchased
                ? PurchaseUiState.purchased
                : PurchaseUiState.restored,
            p.status == PurchaseStatus.purchased
                ? '購入ありがとうございます！'
                : '購入を復元しました',
          );
        case PurchaseStatus.error:
          _analytics.log('purchase_error', {'product': p.productID});
          _setState(PurchaseUiState.error, '購入できませんでした');
        case PurchaseStatus.canceled:
          _setState(PurchaseUiState.canceled, null);
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  void _setState(PurchaseUiState s, String? message) {
    _state = s;
    _message = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Used where no store exists (tests, desktop). Reports unavailable.
class UnavailablePurchaseService extends PurchaseService {
  @override
  bool get storeAvailable => false;
  @override
  List<StoreProduct> get products => const [];
  @override
  PurchaseUiState get state => PurchaseUiState.idle;
  @override
  String? get lastMessage => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> buy(String productId) async {}
  @override
  Future<void> restore() async {}
}
