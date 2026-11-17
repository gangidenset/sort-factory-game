import 'package:flutter/material.dart';

import '../app/services.dart';
import '../data/progress_controller.dart';
import '../game/logic/daily.dart';
import '../services/ads/ad_service.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'game_screen.dart';

/// Calendar of daily puzzles: replay solved days, open missed days of the
/// last [ProgressController.pastDays] days with a rewarded ad or coins.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.clock});

  /// Injectable for tests.
  final DateTime Function()? clock;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

enum _DayState { future, outOfRange, today, solved, solvedLate, open, locked }

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _today;
  late DateTime _month; // first day of the shown month
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = (widget.clock ?? DateTime.now)();
    _today = DateTime(now.year, now.month, now.day);
    _month = DateTime(_today.year, _today.month);
  }

  DateTime get _first => DateTime(
    _today.year,
    _today.month,
    _today.day - ProgressController.pastDays,
  );

  bool get _canGoBack => _month.isAfter(DateTime(_first.year, _first.month));
  bool get _canGoForward =>
      _month.isBefore(DateTime(_today.year, _today.month));

  _DayState _state(ProgressController p, DateTime d) {
    final key = DailyCatalog.dayKey(d);
    if (d.isAfter(_today)) return _DayState.future;
    final rec = p.dailyRecord(key);
    if (rec != null) return rec.late ? _DayState.solvedLate : _DayState.solved;
    if (d == _today) return _DayState.today;
    if (d.isBefore(_first)) return _DayState.outOfRange;
    return p.canPlayDaily(key) ? _DayState.open : _DayState.locked;
  }

  void _play(DateTime d) {
    final svc = context.services;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(stage: svc.daily.forDate(d), dailyDate: d),
      ),
    );
  }

  Future<void> _unlock(DateTime d, {required bool withAd}) async {
    final svc = context.services;
    final key = DailyCatalog.dayKey(d);
    setState(() => _busy = true);
    var ok = true;
    if (withAd) {
      ok = await svc.ads.showRewarded(RewardPlacement.dailyBonus);
      if (!ok && mounted) showSnack(context, '広告を読み込めませんでした');
    }
    if (ok) ok = await svc.progress.unlockPastDaily(key, payWithCoins: !withAd);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    svc.analytics.log('past_unlock', {
      'day': key,
      'method': withAd ? 'ad' : 'coins',
    });
    Navigator.of(context).pop(); // close the sheet
    _play(d);
  }

  void _tap(ProgressController p, DateTime d) {
    switch (_state(p, d)) {
      case _DayState.today ||
          _DayState.solved ||
          _DayState.solvedLate ||
          _DayState.open:
        _play(d);
      case _DayState.locked:
        _showUnlockSheet(p, d);
      case _DayState.future:
        showSnack(context, 'この日のパズルはまだ届いていません');
      case _DayState.outOfRange:
        showSnack(context, '遊べるのは過去${ProgressController.pastDays}日分までです');
    }
  }

  void _showUnlockSheet(ProgressController p, DateTime d) {
    final svc = context.services;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final enoughCoins = p.data.coins >= ProgressController.pastUnlockCost;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${DailyCatalog.label(d)}のパズル',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DailyCatalog.levelOf(d)}・クリアで${ProgressController.pastReward}コイン',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  if (svc.ads.rewardedAvailable) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _unlock(d, withAd: true),
                      icon: const Icon(Icons.smart_display),
                      label: const Text('広告を見て開ける'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy || !enoughCoins
                        ? null
                        : () => _unlock(d, withAd: false),
                    icon: const Icon(
                      Icons.monetization_on,
                      color: AppColors.coin,
                    ),
                    label: Text('${ProgressController.pastUnlockCost}コインで開ける'),
                  ),
                  if (!enoughCoins)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'コインが足りません（所持 ${p.data.coins}）',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    '一度開けた日は何度でも遊べます。過去のパズルは連続日数には入りません。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.services.progress;
    return Scaffold(
      appBar: AppBar(
        title: const Text('パズルカレンダー'),
        actions: const [CoinChip(), SizedBox(width: 12)],
      ),
      body: ListenableBuilder(
        listenable: p,
        builder: (context, _) {
          final solvedOnTime = p.data.dailyPuzzles.values
              .where((r) => !r.late)
              .length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _canGoBack
                        ? () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month - 1,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: '前の月',
                  ),
                  Expanded(
                    child: Text(
                      '${_month.year}年${_month.month}月',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _canGoForward
                        ? () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month + 1,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: '次の月',
                  ),
                ],
              ),
              _MonthGrid(
                month: _month,
                stateOf: (d) => _state(p, d),
                timeOf: (d) => p.dailyRecord(DailyCatalog.dayKey(d))?.seconds,
                onTap: (d) => _tap(p, d),
              ),
              const SizedBox(height: 12),
              const _Legend(),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: Color(0xFFFF7A45),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${p.dailyStreak}日連続',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      Text(
                        'その日に解いた数 $solvedOnTime',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.stateOf,
    required this.timeOf,
    required this.onTap,
  });

  final DateTime month;
  final _DayState Function(DateTime) stateOf;
  final int? Function(DateTime) timeOf;
  final void Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month).weekday - 1; // Monday first
    final cells = <Widget>[
      for (final w in DailyCatalog.weekdayNames)
        Center(
          child: Text(
            w,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: w == '土'
                  ? AppColors.primary
                  : w == '日'
                  ? AppColors.danger
                  : Colors.black54,
            ),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _DayCell(
          date: DateTime(month.year, month.month, d),
          state: stateOf(DateTime(month.year, month.month, d)),
          seconds: timeOf(DateTime(month.year, month.month, d)),
          onTap: onTap,
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 0.82,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.state,
    required this.seconds,
    required this.onTap,
  });

  final DateTime date;
  final _DayState state;
  final int? seconds;
  final void Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, Widget? icon) = switch (state) {
      _DayState.solved => (
        AppColors.success,
        Colors.white,
        const Icon(Icons.check_rounded, size: 16, color: Colors.white),
      ),
      _DayState.solvedLate => (
        const Color(0xFFD7F0DF),
        AppColors.success,
        const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
      ),
      _DayState.today => (
        const Color(0xFFFFF4D6),
        AppColors.ink,
        const Icon(
          Icons.play_arrow_rounded,
          size: 16,
          color: AppColors.primary,
        ),
      ),
      _DayState.open => (
        Colors.white,
        AppColors.ink,
        const Icon(
          Icons.play_arrow_rounded,
          size: 16,
          color: AppColors.primary,
        ),
      ),
      _DayState.locked => (
        Colors.white,
        AppColors.ink,
        const Icon(Icons.lock_rounded, size: 14, color: Colors.black38),
      ),
      _DayState.future || _DayState.outOfRange => (
        Colors.white.withValues(alpha: 0.4),
        Colors.black26,
        null,
      ),
    };
    final today = state == _DayState.today;
    final secs = seconds;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(date),
        child: Container(
          decoration: today
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.coin, width: 2),
                )
              : null,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(fontWeight: FontWeight.w900, color: fg),
              ),
              ?icon,
              if (secs != null)
                FittedBox(
                  child: Text(
                    '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 9,
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t, {Color? border}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(4),
            border: border == null ? null : Border.all(color: border, width: 2),
          ),
        ),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ],
    );
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item(AppColors.success, 'その日に解いた'),
        item(const Color(0xFFD7F0DF), 'あとから解いた'),
        item(const Color(0xFFFFF4D6), '今日', border: AppColors.coin),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.lock_rounded, size: 14, color: Colors.black38),
            SizedBox(width: 4),
            Text('広告かコインで開ける', style: TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
