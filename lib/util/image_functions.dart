import 'dart:io';
import 'dart:typed_data';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:nothing_gallery/model/model.dart';
import 'package:nothing_gallery/util/util.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import 'package:nothing_gallery/classes/classes.dart';
import 'package:nothing_gallery/constants/constants.dart';
import 'package:nothing_gallery/main.dart';

Future<List<String>> onDelete(List<AssetEntity> selectedAssets,
    ImageSelection imageSelection, bool useTrashBin) async {
  List<String> deletedImages = await confirmDelete(selectedAssets, useTrashBin);
  if (deletedImages.isNotEmpty) {
    imageSelection.endSelection();
  }
  return deletedImages;
}

Future<List<String>> moveCopyFiles(List<AssetEntity> moveEntityList,
    bool copyFiles, String destinationPath) async {
  List<String> movedFiles = [];

  bool pathExists = await Directory(destinationPath).exists();
  if (!pathExists) return movedFiles;

  if (!(await requestPermission(Permission.manageExternalStorage))) {
    Fluttertoast.showToast(
      msg: "Permission needed to move/copy files.",
      toastLength: Toast.LENGTH_LONG,
    );
    return movedFiles;
  }

  for (AssetEntity entity in moveEntityList) {
    File? sourceFile = await entity.file;
    if (sourceFile == null) {
      continue;
    }

    movedFiles.add(entity.id);
    String newPath = destinationPath +
        sourceFile.path.substring(sourceFile.path.lastIndexOf('/') + 1);

    if (copyFiles) {
      sourceFile.copySync(newPath);
    } else {
      try {
        await sourceFile.rename(newPath);
      } on FileSystemException catch (_) {
        await sourceFile.copy(newPath);
        await sourceFile.delete();
      }
    }
  }

  return movedFiles;
}

Future<List<String>> confirmDelete(
    List<AssetEntity> deleteEntityList, bool useTrash) async {
  if (useTrash) {
    for (var item in deleteEntityList) {
      await TrashManager.moveToTrash(item);
    }
  }

  List<String> result = (await PhotoManager.editor
          .deleteWithIds(deleteEntityList.map((e) => e.id).toList()))
      .map((id) => id)
      .toList();

  if (result.isEmpty) {
    // If the user cancelled system deletion dialog, clean up staged backups
    await TrashManager.cleanUpStagedTrash(
        deleteEntityList.map((e) => e.id).toList());
    return [];
  } else {
    eventController.sink.add(Event(EventType.assetDeleted, result));
  }
  return result;
}

Future<void> shareFiles(List<AssetEntity> images) async {
  List<String> paths = [];

  for (AssetEntity image in images) {
    File? file = await image.originFile;
    if (file != null) {
      paths.add(file.path);
    }
  }

  Share.shareXFiles(paths.map((path) => XFile(path)).toList());
}

Future<File?> moveToTrash(AssetEntity entity) async {
  await TrashManager.moveToTrash(entity);
  return null;
}
