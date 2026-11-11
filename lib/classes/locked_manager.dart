import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockedItem {
  final String id;
  final String filename;
  final String originalPath;
  final String localPath;
  final DateTime lockedAt;
  final bool isVideo;

  LockedItem({
    required this.id,
    required this.filename,
    required this.originalPath,
    required this.localPath,
    required this.lockedAt,
    required this.isVideo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'originalPath': originalPath,
        'localPath': localPath,
        'lockedAt': lockedAt.toIso8601String(),
        'isVideo': isVideo,
      };

  factory LockedItem.fromJson(Map<String, dynamic> json) => LockedItem(
        id: json['id'] ?? '',
        filename: json['filename'] ?? '',
        originalPath: json['originalPath'] ?? '',
        localPath: json['localPath'] ?? '',
        lockedAt: DateTime.tryParse(json['lockedAt'] ?? '') ?? DateTime.now(),
        isVideo: json['isVideo'] ?? false,
      );
}

class LockedManager {
  static const String manifestFileName = 'locked_manifest.json';
  static const String pinPrefKey = 'user_locked_pin_code';

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(pinPrefKey) &&
        (prefs.getString(pinPrefKey)?.isNotEmpty ?? false);
  }

  static Future<bool> verifyPin(String enteredPin) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(pinPrefKey);
    return saved == enteredPin;
  }

  static Future<void> setPin(String newPin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pinPrefKey, newPin);
  }

  static Future<Directory> getLockedDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final lockedDir = Directory('${appDir.path}/locked_media');
    if (!await lockedDir.exists()) {
      await lockedDir.create(recursive: true);
    }
    return lockedDir;
  }

  static Future<File> _getManifestFile() async {
    final dir = await getLockedDirectory();
    return File('${dir.path}/$manifestFileName');
  }

  static Future<List<LockedItem>> getLockedItems() async {
    try {
      final manifestFile = await _getManifestFile();
      if (!await manifestFile.exists()) return [];

      final content = await manifestFile.readAsString();
      final List<dynamic> list = jsonDecode(content);
      final items = list.map((e) => LockedItem.fromJson(e)).toList();

      final validItems = <LockedItem>[];
      bool changed = false;

      for (final item in items) {
        final file = File(item.localPath);
        if (await file.exists()) {
          validItems.add(item);
        } else {
          changed = true;
        }
      }

      if (changed) {
        await _saveManifest(validItems);
      }

      validItems.sort((a, b) => b.lockedAt.compareTo(a.lockedAt));
      return validItems;
    } catch (e) {
      debugPrint('Error getting locked items: $e');
      return [];
    }
  }

  static Future<void> _saveManifest(List<LockedItem> items) async {
    final manifestFile = await _getManifestFile();
    final jsonString = jsonEncode(items.map((e) => e.toJson()).toList());
    await manifestFile.writeAsString(jsonString);
  }

  static Future<bool> moveToLocked(AssetEntity entity) async {
    try {
      final lockedDir = await getLockedDirectory();
      final originFile = await entity.originFile;
      if (originFile == null || !await originFile.exists()) return false;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = originFile.path.contains('.')
          ? originFile.path.substring(originFile.path.lastIndexOf('.'))
          : '';
      final newFileName =
          'lock_${timestamp}_${entity.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}$ext';
      final targetFile = File('${lockedDir.path}/$newFileName');

      await originFile.copy(targetFile.path);

      final item = LockedItem(
        id: entity.id,
        filename: originFile.path.split(Platform.pathSeparator).last,
        originalPath: originFile.path,
        localPath: targetFile.path,
        lockedAt: DateTime.now(),
        isVideo: entity.type == AssetType.video,
      );

      final currentItems = await getLockedItems();
      currentItems.add(item);
      await _saveManifest(currentItems);

      // Remove original from public media gallery
      await PhotoManager.editor.deleteWithIds([entity.id]);

      return true;
    } catch (e) {
      debugPrint('Error locking asset: $e');
      return false;
    }
  }

  static Future<bool> unlockItem(LockedItem item) async {
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
      } catch (e) {
        debugPrint('Media scan warning on unlock: $e');
      }

      final items = await getLockedItems();
      items.removeWhere(
          (e) => e.localPath == item.localPath || e.id == item.id);
      await _saveManifest(items);

      return true;
    } catch (e) {
      debugPrint('Error unlocking item: $e');
      return false;
    }
  }

  static Future<void> deleteLockedItem(LockedItem item) async {
    try {
      final file = File(item.localPath);
      if (await file.exists()) {
        await file.delete();
      }
      final items = await getLockedItems();
      items.removeWhere(
          (e) => e.localPath == item.localPath || e.id == item.id);
      await _saveManifest(items);
    } catch (e) {
      debugPrint('Error deleting locked item: $e');
    }
  }
}
