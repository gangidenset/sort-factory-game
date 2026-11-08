import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'save_data.dart';

/// Minimal key-value storage so the repository can be tested in memory.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPrefsStore implements KeyValueStore {
  SharedPrefsStore(this._prefs);
  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

/// Ordered migration steps. Each step upgrades from version `n` to `n + 1`.
class SaveMigrations {
  const SaveMigrations._();

  static final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)>
  steps = {
    // Example for the future:
    // 1: (j) => {...j, 'schemaVersion': 2, 'newField': j['old'] ?? 0},
  };

  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    var j = json;
    var v = (j['schemaVersion'] as num?)?.toInt() ?? 1;
    if (v > SaveData.currentVersion) {
      // Data from a newer app version: read what we understand, keep going.
      return j;
    }
    while (v < SaveData.currentVersion) {
      final step = steps[v];
      if (step == null) {
        throw StateError('Missing save migration from v$v');
      }
      j = step(j);
      v++;
    }
    return j;
  }
}

/// Loads / stores [SaveData] with a backup copy so a corrupted write never
/// loses progress: the primary is written first, then the backup.
class SaveRepository {
  SaveRepository(this._store);

  static const primaryKey = 'save_v1';
  static const backupKey = 'save_v1_backup';

  final KeyValueStore _store;

  /// Where the last [load] came from (for diagnostics / tests).
  String lastLoadSource = 'none';

  Future<SaveData> load() async {
    for (final key in [primaryKey, backupKey]) {
      final raw = await _store.read(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic>) continue;
        final data = SaveData.fromJson(SaveMigrations.migrate(json));
        lastLoadSource = key;
        return data;
      } catch (_) {
        // Corrupted entry: fall through to the backup.
      }
    }
    lastLoadSource = 'new';
    return SaveData();
  }

  Future<void> save(SaveData data) async {
    final encoded = data.encode();
    await _store.write(primaryKey, encoded);
    await _store.write(backupKey, encoded);
  }
}
