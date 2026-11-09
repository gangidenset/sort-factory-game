import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/title_screen.dart';
import 'services.dart';
import 'theme.dart';

class SortFactoryApp extends StatelessWidget {
  const SortFactoryApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: services,
      child: MaterialApp(
        title: 'SORT FACTORY',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const TitleScreen(),
        // In desktop browsers (playtest build) keep a phone-shaped portrait
        // frame instead of stretching the board across a wide window.
        builder: kIsWeb ? (context, child) => _PhoneFrame(child: child!) : null,
      ),
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  static const maxWidth = 460.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= maxWidth) return child;
    return ColoredBox(
      color: const Color(0xFF1F2733),
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(maxWidth, mq.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
