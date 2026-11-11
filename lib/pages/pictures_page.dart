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

class PicturesWidget extends StatefulWidget {
  const PicturesWidget({super.key});

  @override
  State createState() => _PicturesState();
}

class _PicturesState extends LifecycleListenerState<PicturesWidget>
    with AutomaticKeepAliveClientMixin {
  late AlbumInfo recent;
  List<AssetEntity> assets = [];
  List<AssetEntity> images = [];

  Map<DateTime, List<AssetEntity>> dateMap = {};
  int totalCount = 0;
  int timelineColCount = 4;
  String activeFilter = 'ALL';
  bool _isLoadingImages = false;

  int startingIndex = 0;

  final ScrollController _scrollController = ScrollController();
  StreamSubscription? eventSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final albumInfoList = Provider.of<AlbumInfoList>(context, listen: false);
      final appStatus = Provider.of<AppStatus>(context, listen: false);

      recent = albumInfoList.recent!;
      totalCount = recent.assetCount;

      getImages();

      eventSubscription =
          eventController.stream.asBroadcastStream().listen((event) {
        switch (validateEventType(event)) {
          case EventType.assetDeleted:
            final List<String> deletedIds = List<String>.from(event.details);
            final List<AssetEntity> deletedAssets = assets
                .where((image) => deletedIds.contains(image.id))
                .toList();

            removeIdsFromDateMap(dateMap, deletedIds);

            if (mounted) {
              setState(() {
                assets.removeWhere((image) => deletedIds.contains(image.id));
                images.removeWhere((image) => deletedIds.contains(image.id));
                totalCount = (totalCount - deletedAssets.length)
                    .clamp(0, 1 << 30);
              });
            }
            break;
          case EventType.assetMoved:
            updateTimeline();
            break;
          case EventType.videoOpen:
            if (appStatus.activeTab == InitialScreen.timeline.tabIndex) {
              openVideoPlayerPage(context, event.details);
            }
            break;
          case EventType.pictureOpen:
            if (appStatus.activeTab == InitialScreen.timeline.tabIndex) {
              final sections = _computeSections(appStatus);
              final orderedImages = collectOrderedImages(sections);
              final int idx = orderedImages.indexWhere(
                  (img) => img.id == (event.details as AssetEntity).id);
              if (idx != -1) {
                openImagePage(
                    context, idx, orderedImages.length, orderedImages);
              } else {
                openImagePage(context, images.indexOf(event.details),
                    images.length, images);
              }
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

  Future<void> checkNewAssets() async {
    if (assets.isEmpty) {
      await getImages();
      return;
    }

    final AssetEntity lastLoaded = assets[0];
    List<AssetEntity> newAssets = [];
    int currPage = 0;

    while (newAssets.where((asset) => asset.id == lastLoaded.id).isEmpty) {
      if (newAssets.isNotEmpty) {
        assets.insertAll(0, newAssets);
        images.insertAll(
            0, newAssets.where((asset) => asset.type == AssetType.image));
        addAssetsToDateMap(dateMap, newAssets);
        if (mounted) setState(() {});
      }
      newAssets = await loadAssets(recent.pathEntity, currPage++, size: 80);
      if (newAssets.isEmpty) return;
    }

    final int prevLoc = newAssets.indexWhere((asset) => asset.id == lastLoaded.id);
    newAssets = newAssets.sublist(0, prevLoc);

    if (newAssets.isEmpty) return;

    assets.insertAll(0, newAssets);
    images.insertAll(
        0, newAssets.where((asset) => asset.type == AssetType.image));
    addAssetsToDateMap(dateMap, newAssets);
    images.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    if (mounted) setState(() {});
  }

  Future<void> checkRemovedAssets() async {
    int cursor = 0;
    final Set<String> currentAssetIds = {};
    List<AssetEntity> batch = [];

    do {
      batch = await loadAssetsRange(recent.pathEntity, cursor, 500);
      cursor += batch.length;
      for (final asset in batch) {
        currentAssetIds.add(asset.id);
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
        assets.removeWhere((image) => removedIds.contains(image.id));
        images.removeWhere((image) => removedIds.contains(image.id));
      });
    }
  }

  Future<void> getImages() async {
    if (_isLoadingImages) return;
    _isLoadingImages = true;

    try {
      int cursor = 0;
      bool firstBatch = true;

      while (assets.length < recent.assetCount) {
        final int batchSize = firstBatch ? 100 : 500;
        firstBatch = false;

        final List<AssetEntity> newAssets =
            await loadAssetsRange(recent.pathEntity, cursor, batchSize);
        if (newAssets.isEmpty) break;
        cursor += newAssets.length;

        assets.addAll(newAssets);
        images.addAll(
            newAssets.where((asset) => asset.type == AssetType.image));
        addAssetsToDateMap(dateMap, newAssets);

        if (mounted) setState(() {});
      }
      images.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    } finally {
      _isLoadingImages = false;
    }
  }

  Future<void> updateTimeline() async {
    final albumInfoList = Provider.of<AlbumInfoList>(context, listen: false);
    await albumInfoList.refreshRecent();
    if (albumInfoList.recent == null) {
      return;
    }
    recent = albumInfoList.recent!;
    totalCount = recent.assetCount;

    await checkRemovedAssets();
    await checkNewAssets();
  }

  List<DateSection> _computeSections(AppStatus appStatus) {
    bool Function(AssetEntity)? predicate;
    if (activeFilter == 'PHOTOS') {
      predicate = (a) => a.type == AssetType.image;
    } else if (activeFilter == 'VIDEOS') {
      predicate = (a) => a.type == AssetType.video;
    } else if (activeFilter == 'SCREENSHOTS') {
      predicate = (a) => (a.title ?? '').toLowerCase().contains('screenshot');
    } else if (activeFilter == 'FAVORITES') {
      predicate = (a) => appStatus.isFavorite(a.id);
    }
    return buildDateSections(dateMap, filter: predicate);
  }

  Widget picturesPageWrapper(ImageSelection imageSelection, Widget child) {
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

  Widget _buildFilterPills(AppStatus appStatus) {
    const filters = ['ALL', 'PHOTOS', 'VIDEOS', 'SCREENSHOTS', 'FAVORITES'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: filters.map((filter) {
          final isSelected = activeFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                if (activeFilter != filter) {
                  setState(() => activeFilter = filter);
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : const Color.fromRGBO(28, 32, 34, 1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white12,
                    width: 1,
                  ),
                ),
                child: Text(
                  filter,
                  style: mainTextStyle(TextStyleType.buttonText).copyWith(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.black : Colors.white70,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer2<ImageSelection, AppStatus>(
        builder: (context, imageSelection, appStatus, child) {
      final List<DateSection> sections = _computeSections(appStatus);

      return picturesPageWrapper(
          imageSelection,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Row(
                  children: [
                    Text(
                      'TIMELINE',
                      style: mainTextStyle(TextStyleType.pageTitle),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        timelineColCount == 4
                            ? Icons.grid_view_rounded
                            : timelineColCount == 3
                                ? Icons.view_comfy_alt_outlined
                                : Icons.view_column_outlined,
                        size: 20,
                        color: Colors.white70,
                      ),
                      tooltip: "Grid columns: $timelineColCount",
                      onPressed: () {
                        setState(() {
                          if (timelineColCount == 4) {
                            timelineColCount = 3;
                          } else if (timelineColCount == 3) {
                            timelineColCount = 2;
                          } else {
                            timelineColCount = 4;
                          }
                        });
                      },
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
            _buildFilterPills(appStatus),
            Expanded(
              child: DateGroupedMediaGrid(
                controller: _scrollController,
                sections: sections,
                crossAxisCount: timelineColCount,
                onRefresh: updateTimeline,
                emptyState: activeFilter != 'ALL'
                    ? Center(
                        child: Text(
                          'NO $activeFilter FOUND',
                          style: mainTextStyle(TextStyleType.gridPageTitle)
                              .copyWith(color: Colors.white38),
                        ),
                      )
                    : null,
              ),
            ),
          ]));
    });
  }

  @override
  bool get wantKeepAlive => true;

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
    updateTimeline();
  }
}
