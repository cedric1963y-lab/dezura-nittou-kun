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

  Future<List<DayRecord>> loadRecords() =>
      _loadList('records.json', 'records', DayRecord.fromJson);

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
    return _atomicWrite(name, _encoder.convert({'version': 1, key: items}));
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
    if (version != 1) {
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
