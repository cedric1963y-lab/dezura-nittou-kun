import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/records.dart';
import '../plan/entitlement.dart';

/// On-device JSON files. No account and no network.
class Repository {
  Repository(this.root);

  final Directory root;

  static const _encoder = JsonEncoder.withIndent('  ');

  /// Version written to workers.json and records.json. 2 adds the pay type
  /// (日当・時給・月給). 3 (1.0.6) adds a record id and 昼/夜勤 to records and
  /// 従業員/外注 to workers. Version 1 and 2 files are still read: a missing
  /// pay type means 日当, a missing kind 従業員, a missing shift 昼, and a
  /// missing record id becomes `workerId@day`.
  static const listSchemaVersion = 3;
  static const _readableVersions = {1, 2, 3};

  String get exportDirectory => p.join(root.path, 'exports');

  Future<void> init() async {
    await root.create(recursive: true);
    await Directory(exportDirectory).create(recursive: true);
  }

  Future<List<Worker>> loadWorkers() =>
      _loadList('workers.json', 'workers', Worker.fromJson);

  Future<void> saveWorkers(List<Worker> workers) => _saveList(
    'workers.json',
    'workers',
    [for (final w in workers) w.toJson()],
  );

  Future<List<Site>> loadSites() =>
      _loadList('sites.json', 'sites', Site.fromJson);

  Future<void> saveSites(List<Site> sites) =>
      _saveList('sites.json', 'sites', [for (final s in sites) s.toJson()]);

  Future<List<DayRecord>> loadRecords() async {
    final records = await _loadList(
      'records.json',
      'records',
      DayRecord.fromJson,
    );
    // Ids must be unique. A damaged file with a repeated id keeps every
    // entry by renaming the later ones.
    final seen = <String>{};
    return [
      for (final r in records)
        if (seen.add(r.id)) r else r.withId(_freshId(seen, r.id)),
    ];
  }

  static String _freshId(Set<String> seen, String base) {
    var n = 2;
    while (!seen.add('$base#$n')) {
      n++;
    }
    return '$base#$n';
  }

  Future<void> saveRecords(List<DayRecord> records) => _saveList(
    'records.json',
    'records',
    [for (final r in records) r.toJson()],
  );

  Future<Map<String, dynamic>> loadSettings() async {
    return await _readObject('settings.json') ?? {'version': 1};
  }

  Future<void> saveSettings(Map<String, dynamic> settings) {
    return _atomicWrite(
      'settings.json',
      _encoder.convert({...settings, 'version': 1}),
    );
  }

  Future<Entitlement> loadEntitlement() async {
    return Entitlement.fromJson(await _readObject('entitlement.json'));
  }

  Future<void> saveEntitlement(Entitlement entitlement) {
    return _atomicWrite(
      'entitlement.json',
      _encoder.convert(entitlement.toJson()),
    );
  }

  /// Writes an export file and returns its path. Old exports are replaced.
  Future<String> writeExport(String fileName, Uint8List bytes) async {
    final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File(p.join(exportDirectory, safe));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<List<T>> _loadList<T>(
    String name,
    String key,
    T Function(Map<String, dynamic> json) parse,
  ) async {
    final json = await _readObject(name);
    if (json == null) return [];
    final list = json[key];
    if (list is! List) return [];
    return [
      for (final item in list)
        if (item is Map<String, dynamic>)
          parse(item)
        else if (item is Map)
          parse(Map<String, dynamic>.from(item)),
    ];
  }

  Future<void> _saveList(
    String name,
    String key,
    List<Map<String, dynamic>> items,
  ) {
    return _atomicWrite(
      name,
      _encoder.convert({'version': listSchemaVersion, key: items}),
    );
  }

  Future<Map<String, dynamic>?> _readObject(String name) async {
    final file = File(p.join(root.path, name));
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    if (text.trim().isEmpty) return null;
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('保存データの形式が不正です。');
    }
    final json = Map<String, dynamic>.from(decoded);
    final version = json['version'];
    if (!_readableVersions.contains(version)) {
      throw FormatException('未対応の保存データです（version: $version）。');
    }
    return json;
  }

  Future<void> _atomicWrite(String name, String contents) async {
    final target = File(p.join(root.path, name));
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  }
}
