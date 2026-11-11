import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

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
      bool changed = false;

      for (final item in items) {
        // Auto-purge items older than 30 days
        if (now.difference(item.deletedAt).inDays >= 30) {
          final file = File(item.localPath);
          if (await file.exists()) {
            await file.delete();
          }
          changed = true;
        } else {
          final file = File(item.localPath);
          if (await file.exists()) {
            validItems.add(item);
          } else {
            changed = true;
          }
        }
      }

      if (changed) {
        await _saveManifest(validItems);
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

  static Future<bool> moveToTrash(AssetEntity entity) async {
    try {
      final trashDir = await getTrashDirectory();
      final originFile = await entity.originFile;
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
        isVideo: entity.type == AssetType.video,
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
    try {
      final file = File(item.localPath);
      if (!await file.exists()) return false;

      String destPath = item.originalPath;
      File destFile = File(destPath);
      if (!await destFile.parent.exists()) {
        final extDir = await getExternalStorageDirectory();
        destPath =
            '${extDir?.path ?? file.parent.path}/Restored/${item.filename}';
        destFile = File(destPath);
        await destFile.parent.create(recursive: true);
      }

      await file.copy(destPath);
      await file.delete();

      try {
        if (item.isVideo) {
          await PhotoManager.editor.saveVideo(
            destFile,
            title: item.filename,
          );
        } else {
          final bytes = await destFile.readAsBytes();
          await PhotoManager.editor.saveImage(
            bytes,
            title: item.filename,
          );
        }
      } catch (err) {
        debugPrint('Media scan warning on restore: $err');
      }

      final items = await getTrashedItems();
      items.removeWhere(
          (e) => e.localPath == item.localPath || e.id == item.id);
      await _saveManifest(items);

      return true;
    } catch (e) {
      debugPrint('Error restoring item: $e');
      return false;
    }
  }

  static Future<void> permanentlyDelete(TrashedItem item) async {
    try {
      final file = File(item.localPath);
      if (await file.exists()) {
        await file.delete();
      }
      final items = await getTrashedItems();
      items.removeWhere(
          (e) => e.localPath == item.localPath || e.id == item.id);
      await _saveManifest(items);
    } catch (e) {
      debugPrint('Error permanently deleting item: $e');
    }
  }

  static Future<void> emptyTrash() async {
    try {
      final dir = await getTrashDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
      await _saveManifest([]);
    } catch (e) {
      debugPrint('Error emptying trash: $e');
    }
  }
}
