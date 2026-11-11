import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class TrashedItem {
  final String id;
  final String filename;
  final String originalPath;
  final String localPath;
  final DateTime deletedAt;
  final bool isVideo;

  TrashedItem({
    required this.id,
    required this.filename,
    required this.originalPath,
    required this.localPath,
    required this.deletedAt,
    required this.isVideo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'originalPath': originalPath,
        'localPath': localPath,
        'deletedAt': deletedAt.toIso8601String(),
        'isVideo': isVideo,
      };

  factory TrashedItem.fromJson(Map<String, dynamic> json) => TrashedItem(
        id: json['id'] ?? '',
        filename: json['filename'] ?? '',
        originalPath: json['originalPath'] ?? '',
        localPath: json['localPath'] ?? '',
        deletedAt: DateTime.tryParse(json['deletedAt'] ?? '') ?? DateTime.now(),
        isVideo: json['isVideo'] ?? false,
      );
}

class TrashManager {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.kahluabear.nothing_gallery/native_trash');
  static const String manifestFileName = 'trash_manifest.json';

  static Future<Directory> getTrashDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final trashDir = Directory('${appDir.path}/trash');
    if (!await trashDir.exists()) {
      await trashDir.create(recursive: true);
    }
    return trashDir;
  }

  static Future<File> _getManifestFile() async {
    final dir = await getTrashDirectory();
    return File('${dir.path}/$manifestFileName');
  }

  static Future<List<TrashedItem>> getTrashedItems() async {
    try {
      final manifestFile = await _getManifestFile();
      if (!await manifestFile.exists()) return [];

      final content = await manifestFile.readAsString();
      final List<dynamic> list = jsonDecode(content);
      final items = list.map((e) => TrashedItem.fromJson(e)).toList();

      final now = DateTime.now();
      final validItems = <TrashedItem>[];
      final expiredItems = <TrashedItem>[];

      for (final item in items) {
        if (now.difference(item.deletedAt).inDays >= 30) {
          expiredItems.add(item);
        } else {
          final file = File(item.localPath);
          if (await file.exists()) {
            validItems.add(item);
          }
        }
      }

      if (expiredItems.isNotEmpty) {
        await permanentlyDeleteMultiple(expiredItems);
      }

      validItems.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
      return validItems;
    } catch (e) {
      debugPrint('Error loading trashed items: $e');
      return [];
    }
  }

  static Future<void> _saveManifest(List<TrashedItem> items) async {
    final manifestFile = await _getManifestFile();
    final jsonString = jsonEncode(items.map((e) => e.toJson()).toList());
    await manifestFile.writeAsString(jsonString);
  }

  static Future<bool> moveToTrash(dynamic entity) async {
    try {
      final trashDir = await getTrashDirectory();
      final File? originFile = await entity.originFile;
      if (originFile == null || !await originFile.exists()) return false;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = originFile.path.contains('.')
          ? originFile.path.substring(originFile.path.lastIndexOf('.'))
          : '';
      final newFileName =
          'trash_${timestamp}_${entity.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}$ext';
      final targetFile = File('${trashDir.path}/$newFileName');

      await originFile.copy(targetFile.path);

      final item = TrashedItem(
        id: entity.id,
        filename: originFile.path.split(Platform.pathSeparator).last,
        originalPath: originFile.path,
        localPath: targetFile.path,
        deletedAt: DateTime.now(),
        isVideo: entity.type.toString().contains('video'),
      );

      final currentItems = await getTrashedItems();
      currentItems.add(item);
      await _saveManifest(currentItems);

      return true;
    } catch (e) {
      debugPrint('Error moving entity to trash: $e');
      return false;
    }
  }

  static Future<bool> restoreItem(TrashedItem item) async {
    return restoreMultipleItems([item]);
  }

  static Future<bool> restoreMultipleItems(List<TrashedItem> targets) async {
    if (targets.isEmpty) return true;

    // 1. First attempt native MediaStore untrash (API 30+)
    try {
      final payload = targets
          .map((i) => {
                'id': i.id,
                'isVideo': i.isVideo,
                'path': i.originalPath,
              })
          .toList();
      final dynamic nativeResult = await _nativeChannel
          .invokeMethod('restoreItems', {'items': payload});
      if (nativeResult == true) {
        // Native untrash restored files in place into original folders
        for (final item in targets) {
          final file = File(item.localPath);
          if (await file.exists()) await file.delete();
        }
        final items = await getTrashedItems();
        final targetIds = targets.map((t) => t.id).toSet();
        items.removeWhere((e) => targetIds.contains(e.id));
        await _saveManifest(items);
        return true;
      } else if (nativeResult == false) {
        // User cancelled native untrash confirmation dialog
        return false;
      }
    } catch (e) {
      debugPrint('Native untrash fallback: $e');
    }

    // 2. Fallback restore: Copy back to originalPath and call MediaScanner
    // Restores to original folder and NEVER creates 'Pictures' folder!
    for (final item in targets) {
      try {
        final file = File(item.localPath);
        if (!await file.exists()) continue;

        String destPath = item.originalPath;
        File destFile = File(destPath);
        if (!await destFile.parent.exists()) {
          await destFile.parent.create(recursive: true);
        }

        await file.copy(destPath);
        await file.delete();

        // Index in place via MediaScannerConnection
        await _nativeChannel.invokeMethod('scanFile', {'path': destPath});
      } catch (err) {
        debugPrint('Fallback restore error for ${item.filename}: $err');
      }
    }

    final items = await getTrashedItems();
    final targetIds = targets.map((t) => t.id).toSet();
    items.removeWhere((e) => targetIds.contains(e.id));
    await _saveManifest(items);

    return true;
  }

  static Future<bool> permanentlyDelete(TrashedItem item) async {
    return permanentlyDeleteMultiple([item]);
  }

  static Future<bool> permanentlyDeleteMultiple(List<TrashedItem> targets) async {
    if (targets.isEmpty) return true;

    // 1. Call native MediaStore delete request so Android & Google Photos permanently remove it
    try {
      final payload = targets
          .map((i) => {
                'id': i.id,
                'isVideo': i.isVideo,
                'path': i.originalPath,
              })
          .toList();
      final dynamic nativeResult = await _nativeChannel
          .invokeMethod('deletePermanently', {'items': payload});
      if (nativeResult == false) {
        // User cancelled native delete confirmation dialog
        return false;
      }
    } catch (e) {
      debugPrint('Native permanent delete warning: $e');
    }

    // 2. Clean up local backup copies
    for (final item in targets) {
      try {
        final file = File(item.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting local file: $e');
      }
    }

    // 3. Update manifest
    final items = await getTrashedItems();
    final targetIds = targets.map((t) => t.id).toSet();
    items.removeWhere((e) => targetIds.contains(e.id));
    await _saveManifest(items);

    return true;
  }

  static Future<void> cleanUpStagedTrash(List<String> assetIds) async {
    try {
      final idSet = assetIds.toSet();
      final items = await getTrashedItems();
      final toRemove = items.where((i) => idSet.contains(i.id)).toList();
      for (final item in toRemove) {
        final f = File(item.localPath);
        if (await f.exists()) await f.delete();
      }
      items.removeWhere((i) => idSet.contains(i.id));
      await _saveManifest(items);
    } catch (e) {
      debugPrint('Error cleaning up staged trash: $e');
    }
  }

  static Future<void> emptyTrash() async {
    final allItems = await getTrashedItems();
    await permanentlyDeleteMultiple(allItems);
  }
}
