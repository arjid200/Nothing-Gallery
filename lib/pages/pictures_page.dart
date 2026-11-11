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
  int currentPage = 0;
  int timelineColCount = 4;
  String activeFilter = 'ALL';

  int startingIndex = 0;

  StreamSubscription? eventSubscription;

  List<String> monthAbrev = [
    "",
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
    "Jan"
  ];

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
            List<AssetEntity> deletedAssets = assets
                .where((image) =>
                    (event.details as List<String>).contains(image.id))
                .toList();

            for (AssetEntity asset in deletedAssets) {
              removeAssetFromDateMap(asset);
            }

            setState(() {
              assets.removeWhere((image) =>
                  (event.details as List<String>).contains(image.id));
              images.removeWhere((image) =>
                  (event.details as List<String>).contains(image.id));
            });

            totalCount -= 1;
            break;
          case EventType.videoOpen:
            if (appStatus.activeTab == InitialScreen.timeline.tabIndex) {
              openVideoPlayerPage(context, event.details);
            }
            break;
          case EventType.pictureOpen:
            if (appStatus.activeTab == InitialScreen.timeline.tabIndex) {
              openImagePage(context, images.indexOf(event.details),
                  images.length, images);
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
    super.dispose();
  }

  void removeAssetFromDateMap(AssetEntity asset) {
    DateTime dateTaken = asset.createDateTime;
    DateTime date = DateTime(dateTaken.year, dateTaken.month, dateTaken.day);
    dateMap[date]?.removeWhere((element) => element.id == asset.id);
    if (dateMap[date]!.isEmpty) {
      dateMap.remove(date);
    }
  }

  Future<void> checkNewAssets() async {
    AssetEntity lastLoaded = assets[0];
    List<AssetEntity> newAssets = [];
    int currPage = 0;

    while (newAssets.where((asset) => asset.id == lastLoaded.id).isEmpty) {
      if (newAssets.isNotEmpty) {
        assets = List.from(newAssets)..addAll(assets);
        images =
            List.from(newAssets.where((asset) => asset.type == AssetType.image))
              ..addAll(images);

        await insertAssetToDateMap(newAssets);
        setState(() {});
      }
      newAssets = await loadAssets(recent.pathEntity, currPage++, size: 80);
    }

    int prevLoc = newAssets.indexWhere((asset) => asset.id == lastLoaded.id);
    newAssets = newAssets.sublist(0, prevLoc);

    print("found $prevLoc images added");

    if (newAssets.isEmpty) return;

    assets = List.from(newAssets)..addAll(assets);
    images =
        List.from(newAssets.where((asset) => asset.type == AssetType.image))
          ..addAll(images);

    await insertAssetToDateMap(newAssets);
    setState(() {});
    images.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
  }

  Future<void> checkRemovedAssets() async {
    int currPage = 0;
    List<String> currentAssetIds = [];
    List<AssetEntity> newAssets = [];

    do {
      newAssets = await loadAssets(recent.pathEntity, currPage++, size: 80);
      currentAssetIds = List.from(currentAssetIds)
        ..addAll(newAssets.map((asset) => asset.id).toList());
    } while (newAssets.isNotEmpty);

    List<String> removedIds = assets
        .where((asset) {
          bool remove = !currentAssetIds.contains(asset.id);
          if (remove) removeAssetFromDateMap(asset);
          return remove;
        })
        .map((asset) => asset.id)
        .toList();

    print("found ${removedIds.length} images removed");
    setState(() {
      assets.removeWhere((image) => removedIds.contains(image.id));
      images.removeWhere((image) => removedIds.contains(image.id));
    });
  }

  Future<void> getImages() async {
    List<AssetEntity> newAssets = [];

    while (assets.length < recent.assetCount) {
      newAssets = await loadAssets(recent.pathEntity, currentPage++, size: 80);
      if (newAssets.isEmpty) break;

      assets = List.from(assets)..addAll(newAssets);
      images = List.from(images)
        ..addAll(newAssets.where((asset) => asset.type == AssetType.image));
      await insertAssetToDateMap(newAssets);
      setState(() {});
    }
    images.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
  }

  Future<void> insertAssetToDateMap(List<AssetEntity> newAssets) async {
    for (AssetEntity asset in newAssets) {
      DateTime dateTaken = asset.createDateTime;
      DateTime date = DateTime(dateTaken.year, dateTaken.month, dateTaken.day);

      dateMap.putIfAbsent(date, () => []);
      dateMap[date]!.add(asset);
      if (dateMap[date]!.isNotEmpty) {
        dateMap[date]!
            .sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      }
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
    final filters = ['ALL', 'PHOTOS', 'VIDEOS', 'SCREENSHOTS', 'FAVORITES'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: filters.map((filter) {
          final isSelected = activeFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => activeFilter = filter),
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

  Widget _buildDateChunk(BuildContext context,
      MapEntry<DateTime, List<AssetEntity>> entry, List<AssetEntity> filteredAssets) {
    if (filteredAssets.isEmpty) return const SizedBox.shrink();

    String dateText = entry.key.year == DateTime.now().year
        ? "${monthAbrev[entry.key.month]} ${entry.key.day}"
        : "${entry.key.year} ${monthAbrev[entry.key.month]} ${entry.key.day}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Text(
            dateText,
            style: mainTextStyle(TextStyleType.picturesDateTaken),
          ),
        ),
        GridView.count(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
            primary: false,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            shrinkWrap: true,
            crossAxisCount: timelineColCount,
            children: filteredAssets.map((asset) {
              return GridItemWidget(
                context: context,
                asset: asset,
                favoritePage: false,
                thumbnailSelection: false,
              );
            }).toList())
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer2<ImageSelection, AppStatus>(
        builder: (context, imageSelection, appStatus, child) {
      // Filter assets per date according to active filter
      var dateList = dateMap.entries.map((entry) {
        List<AssetEntity> filteredList = entry.value;
        if (activeFilter == 'PHOTOS') {
          filteredList = entry.value
              .where((a) => a.type == AssetType.image)
              .toList();
        } else if (activeFilter == 'VIDEOS') {
          filteredList = entry.value
              .where((a) => a.type == AssetType.video)
              .toList();
        } else if (activeFilter == 'SCREENSHOTS') {
          filteredList = entry.value
              .where((a) =>
                  (a.title ?? '').toLowerCase().contains('screenshot'))
              .toList();
        } else if (activeFilter == 'FAVORITES') {
          filteredList = entry.value
              .where((a) => appStatus.isFavorite(a.id))
              .toList();
        }
        return MapEntry(entry.key, filteredList);
      }).where((entry) => entry.value.isNotEmpty).toList();

      dateList.sort((a, b) => b.key.compareTo(a.key));

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
            // Timeline Grid
            Expanded(
                child: RefreshIndicator(
              color: Colors.red,
              onRefresh: () async {
                await updateTimeline();
                return;
              },
              child: CustomScrollView(primary: false, slivers: <Widget>[
                SliverList(
                    delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildDateChunk(
                      context, dateList[index], dateList[index].value),
                  childCount: dateList.length,
                ))
              ]),
            ))
          ]));
    });
  }

  @override
  // TODO: implement wantKeepAlive
  bool get wantKeepAlive => true;

  @override
  void onDetached() {
    // TODO: implement onDetached
  }

  @override
  void onHidden() {
    // TODO: implement onHidden
  }

  @override
  void onInactive() {
    // TODO: implement onInactive
  }

  @override
  void onPaused() {
    // TODO: implement onPaused
  }

  @override
  void onResumed() async {
    updateTimeline();
  }
}
