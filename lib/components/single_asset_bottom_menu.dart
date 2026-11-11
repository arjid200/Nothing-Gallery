import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import 'package:nothing_gallery/model/model.dart';
import 'package:nothing_gallery/util/util.dart';
import 'package:nothing_gallery/components/exif_details_sheet.dart';

class SingleItemBottomMenu extends StatelessWidget {
  const SingleItemBottomMenu(
      {super.key,
      required this.parentContext,
      required this.asset,
      required this.popOnDelete,
      required this.favoritesPage});

  final BuildContext parentContext;
  final AssetEntity asset;
  final bool popOnDelete;
  final bool favoritesPage;

  @override
  Widget build(BuildContext context) {
    bool useTrashbin = true;

    return Consumer<AppStatus>(builder: (context, appStatus, child) {
      bool isFavorite = appStatus.isFavorite(asset.id);

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
              onPressed: () {
                isFavorite
                    ? appStatus.removeFavorite([asset.id])
                    : appStatus.addFavorite([asset.id]);
              },
              icon: Icon(isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded)),
          IconButton(
              onPressed: () {
                shareFiles([asset]);
              },
              icon: const Icon(Icons.share)),
          IconButton(
              onPressed: () {
                showExifDetailsSheet(parentContext, asset);
              },
              icon: const Icon(Icons.info_outline_rounded)),
          IconButton(
              onPressed: () async {
                confirmDelete([asset], useTrashbin).then((deletedList) {
                  appStatus.removeFavorite(deletedList);
                  if (deletedList.isNotEmpty && popOnDelete) {
                    Navigator.pop(parentContext);
                  }
                });
              },
              icon: const Icon(Icons.delete_outline_rounded)),
          PopupMenuButton<String>(
            color: const Color.fromRGBO(30, 30, 30, 1),
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'details') {
                showExifDetailsSheet(parentContext, asset);
              } else if (val == 'share') {
                shareFiles([asset]);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'details',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.white70),
                    SizedBox(width: 12),
                    Text("Details", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20, color: Colors.white70),
                    SizedBox(width: 12),
                    Text("Share", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}
