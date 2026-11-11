import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nothing_gallery/constants/constants.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:nothing_gallery/main.dart';
import 'package:nothing_gallery/style.dart';
import 'package:nothing_gallery/classes/classes.dart';
import 'package:nothing_gallery/components/components.dart';
import 'package:nothing_gallery/model/model.dart';
import 'package:nothing_gallery/util/util.dart';

class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State createState() => _FavoriteState();
}

class _FavoriteState extends LifecycleListenerState<FavoritePage> {
  late AlbumInfo recent;
  List<AssetEntity> assets = [];
  List<AssetEntity> images = [];
  Map<DateTime, List<AssetEntity>> dateMap = {};
  List<DateSection> sections = [];

  final ScrollController _scrollController = ScrollController();
  StreamSubscription? eventSubscription;

  int startingIndex = 0;
  int totalLoaded = 0;
  int numCol = 4;
  bool _isLoading = false;

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final albumInfoList = Provider.of<AlbumInfoList>(context, listen: false);
      final appStatus = Provider.of<AppStatus>(context, listen: false);

      recent = albumInfoList.recent!;

      getFavorites(appStatus);

      eventSubscription =
          eventController.stream.asBroadcastStream().listen((event) {
        switch (validateEventType(event)) {
          case EventType.assetDeleted:
          case EventType.favoriteRemoved:
            final List<String> removedIds = (event.details is List)
                ? (event.details as List).map((e) => e.toString()).toList()
                : [];
            removeIdsFromDateMap(dateMap, removedIds);
            final rebuiltSections = buildDateSections(dateMap);

            setState(() {
              assets.removeWhere((asset) => removedIds.contains(asset.id));
              sections = rebuiltSections;
              images = collectOrderedImages(rebuiltSections);
            });
            break;
          case EventType.videoOpen:
            openVideoPlayerPage(context, event.details);
            break;
          case EventType.pictureOpen:
            final int idx = images.indexWhere(
                (img) => img.id == (event.details as AssetEntity).id);
            if (idx != -1) {
              openImagePage(context, idx, images.length, images,
                  favoritesPage: true);
            }
            break;
          default:
        }
      });
    });
  }

  @override
  void dispose() {
    eventSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> updateFavorites() async {
    final albumInfoList = Provider.of<AlbumInfoList>(context, listen: false);
    await albumInfoList.refreshRecent();
    if (albumInfoList.recent == null) {
      return;
    }
    recent = albumInfoList.recent!;

    await checkRemovedFavorites();
  }

  Future<void> checkRemovedFavorites() async {
    final appStatus = Provider.of<AppStatus>(context, listen: false);

    int cursor = 0;
    final Set<String> currentAssetIds = {};
    List<AssetEntity> batch = [];

    do {
      batch = await loadAssetsRange(recent.pathEntity, cursor, 500);
      cursor += batch.length;
      for (final asset in batch) {
        if (appStatus.favoriteIds.contains(asset.id)) {
          currentAssetIds.add(asset.id);
        }
      }
    } while (batch.isNotEmpty);

    final List<String> removedIds = assets
        .where((asset) => !currentAssetIds.contains(asset.id))
        .map((asset) => asset.id)
        .toList();

    if (removedIds.isEmpty) return;

    appStatus.removeFavorite(removedIds);
    removeIdsFromDateMap(dateMap, removedIds);
    final rebuiltSections = buildDateSections(dateMap);

    setState(() {
      assets.removeWhere((favorites) => removedIds.contains(favorites.id));
      sections = rebuiltSections;
      images = collectOrderedImages(rebuiltSections);
    });
  }

  Future<void> getFavorites(AppStatus appStatus) async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      int cursor = 0;
      bool firstBatch = true;

      while (totalLoaded < recent.assetCount) {
        final int batchSize = firstBatch ? 100 : 500;
        firstBatch = false;

        final List<AssetEntity> newAssets =
            await loadAssetsRange(recent.pathEntity, cursor, batchSize);
        if (newAssets.isEmpty) break;
        cursor += newAssets.length;
        totalLoaded += newAssets.length;

        final List<AssetEntity> favBatch = newAssets
            .where((asset) => appStatus.favoriteIds.contains(asset.id))
            .toList();

        if (favBatch.isNotEmpty) {
          assets.addAll(favBatch);
          addAssetsToDateMap(dateMap, favBatch);
          final builtSections = buildDateSections(dateMap);
          final orderedImages = collectOrderedImages(builtSections);

          setState(() {
            sections = builtSections;
            images = orderedImages;
          });
        }
      }
    } finally {
      _isLoading = false;
    }
  }

  Widget gridPageWrapper(ImageSelection imageSelection, Widget child) {
    return GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
            body: WillPopScope(
                onWillPop: () async {
                  if (imageSelection.selectionMode) {
                    imageSelection.endSelection();
                    return false;
                  }
                  if (Navigator.canPop(context)) Navigator.pop(context);
                  return true;
                },
                child: SafeArea(child: child))));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStatus>(builder: (context, appStatus, child) {
      if (appStatus.favoriteIds.isEmpty) {
        Future.microtask(() {
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        });
        return Container();
      } else {
        return Consumer<ImageSelection>(
            builder: (context, imageSelection, child) {
          return gridPageWrapper(
              imageSelection,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  const SizedBox(width: 10),
                  GestureDetector(
                      onTap: () {
                        if (Navigator.canPop(context)) Navigator.pop(context);
                      },
                      child: const Icon(Icons.arrow_back)),
                  Expanded(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
                        child: Text(
                          "FAVORITES (${appStatus.favoriteIds.length})",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mainTextStyle(TextStyleType.gridPageTitle),
                        )),
                  ),
                  imageSelection.selectionMode
                      ? SelectionMenu(
                          assets: assets,
                          showMore: false,
                          currentAlbum: null,
                        )
                      : Container()
                ]),

                // Date-Grouped Favorites Grid with Fast Scroller
                Expanded(
                  child: DateGroupedMediaGrid(
                    controller: _scrollController,
                    sections: sections,
                    crossAxisCount: numCol,
                    onRefresh: updateFavorites,
                    favoritePage: true,
                  ),
                ),
              ]));
        });
      }
    });
  }

  @override
  void onDetached() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {}

  @override
  void onResumed() async {
    updateFavorites();
  }

  @override
  void onHidden() {}
}
