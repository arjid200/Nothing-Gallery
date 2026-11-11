import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nothing_gallery/classes/classes.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import 'package:nothing_gallery/style.dart';
import 'package:nothing_gallery/main.dart';
import 'package:nothing_gallery/util/util.dart';
import 'package:nothing_gallery/components/components.dart';
import 'package:nothing_gallery/constants/constants.dart';
import 'package:nothing_gallery/model/model.dart';

class VideosPage extends StatefulWidget {
  const VideosPage({super.key});

  @override
  State createState() => _VideosPageState();
}

class _VideosPageState extends LifecycleListenerState<VideosPage> {
  late AlbumInfo recent;
  List<AssetEntity> assets = [];

  Map<DateTime, List<AssetEntity>> dateMap = {};
  int totalLoaded = 0;
  bool _isLoading = false;

  final ScrollController _scrollController = ScrollController();
  StreamSubscription? eventSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final albumInfoList = Provider.of<AlbumInfoList>(context, listen: false);

      recent = albumInfoList.recent!;
      assets = [];
      totalLoaded = 0;

      getVideos();

      eventSubscription =
          eventController.stream.asBroadcastStream().listen((event) {
        switch (validateEventType(event)) {
          case EventType.assetDeleted:
            final List<String> deletedIds = (event.details is List)
                ? (event.details as List).map((e) => e.toString()).toList()
                : [];
            removeIdsFromDateMap(dateMap, deletedIds);

            if (mounted) {
              setState(() {
                assets.removeWhere((image) => deletedIds.contains(image.id));
              });
            }
            break;
          case EventType.videoOpen:
            openVideoPlayerPage(context, event.details);
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

  Future<void> checkNewVideos() async {
    if (assets.isEmpty) {
      await getVideos();
      return;
    }

    final AssetEntity lastLoaded = assets[0];
    List<AssetEntity> newAssets = [];
    int currPage = 0;

    while (newAssets.where((asset) => asset.id == lastLoaded.id).isEmpty) {
      if (newAssets.isNotEmpty) {
        assets.insertAll(0, newAssets);
        addAssetsToDateMap(dateMap, newAssets);
        if (mounted) setState(() {});
      }
      newAssets = await loadAssets(recent.pathEntity, currPage++, size: 80);
      if (newAssets.isEmpty) return;
      newAssets.removeWhere((asset) => asset.type != AssetType.video);
    }

    final int prevLoc = newAssets.indexWhere((asset) => asset.id == lastLoaded.id);
    if (prevLoc > 0) {
      newAssets = newAssets.sublist(0, prevLoc);
      assets.insertAll(0, newAssets);
      addAssetsToDateMap(dateMap, newAssets);
      if (mounted) setState(() {});
    }
  }

  Future<void> checkRemovedVideos() async {
    int cursor = 0;
    final Set<String> currentAssetIds = {};
    List<AssetEntity> batch = [];

    do {
      batch = await loadAssetsRange(recent.pathEntity, cursor, 500);
      cursor += batch.length;
      for (final asset in batch) {
        if (asset.type == AssetType.video) {
          currentAssetIds.add(asset.id);
        }
      }
    } while (batch.isNotEmpty);

    final List<String> removedIds = assets
        .where((asset) => !currentAssetIds.contains(asset.id))
        .map((asset) => asset.id)
        .toList();

    if (removedIds.isEmpty) return;
    removeIdsFromDateMap(dateMap, removedIds);

    if (mounted) {
      setState(() {
        assets.removeWhere((video) => removedIds.contains(video.id));
      });
    }
  }

  Future<void> updateVideos() async {
    final albumInfoList = Provider.of<AlbumInfoList>(context, listen: false);
    await albumInfoList.refreshRecent();
    if (albumInfoList.recent == null) {
      return;
    }
    recent = albumInfoList.recent!;

    await checkRemovedVideos();
    await checkNewVideos();
  }

  Future<void> getVideos() async {
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

        final List<AssetEntity> videos = newAssets
            .where((asset) => asset.type == AssetType.video)
            .toList();

        if (videos.isNotEmpty) {
          assets.addAll(videos);
          addAssetsToDateMap(dateMap, videos);
          if (mounted) setState(() {});
        }
      }
    } finally {
      _isLoading = false;
    }
  }

  Widget videosPageWrapper(ImageSelection imageSelection, Widget child) {
    return GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
            body: WillPopScope(
                onWillPop: () async {
                  if (imageSelection.selectionMode) {
                    imageSelection.endSelection();
                    return false;
                  }
                  return true;
                },
                child: SafeArea(child: child))));
  }

  @override
  Widget build(BuildContext context) {
    final List<DateSection> sections = buildDateSections(dateMap);

    return Consumer<ImageSelection>(builder: (context, imageSelection, child) {
      return videosPageWrapper(
          imageSelection,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(10, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                        onTap: () {
                          if (Navigator.canPop(context)) Navigator.pop(context);
                        },
                        child: const Icon(Icons.arrow_back)),
                    const SizedBox(width: 10),
                    Text(
                      'VIDEOS',
                      style: mainTextStyle(TextStyleType.pageTitle),
                    ),
                    const Spacer(),
                    imageSelection.selectionMode
                        ? SelectionMenu(
                            assets: assets,
                            showMore: false,
                            currentAlbum: null,
                          )
                        : Container()
                  ],
                )),
            Expanded(
              child: DateGroupedMediaGrid(
                controller: _scrollController,
                sections: sections,
                crossAxisCount: 4,
                onRefresh: updateVideos,
              ),
            ),
          ]));
    });
  }

  @override
  void onDetached() {}

  @override
  void onHidden() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {}

  @override
  void onResumed() async {
    updateVideos();
  }
}
