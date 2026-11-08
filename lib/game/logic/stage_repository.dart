import 'dart:convert';

import 'stage_config.dart';

/// Parses and holds all stage definitions.
class StageCatalog {
  StageCatalog(List<StageConfig> stages)
    : stages = List.unmodifiable(stages..sort((a, b) => a.id.compareTo(b.id))) {
    final ids = <int>{};
    for (final s in this.stages) {
      if (!ids.add(s.id)) throw FormatException('Duplicate stage id ${s.id}');
    }
  }

  final List<StageConfig> stages;

  factory StageCatalog.fromJsonString(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final list = (root['stages'] as List)
        .map((e) => StageConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    return StageCatalog(list);
  }

  int get length => stages.length;

  StageConfig? byId(int id) {
    for (final s in stages) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The stage after [id], or null if [id] is the last one.
  StageConfig? nextOf(int id) {
    final i = stages.indexWhere((s) => s.id == id);
    if (i < 0 || i + 1 >= stages.length) return null;
    return stages[i + 1];
  }
}
