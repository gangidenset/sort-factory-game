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
      ),
    );
  }
}
