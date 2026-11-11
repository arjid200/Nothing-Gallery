import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:nothing_gallery/main.dart';
import 'package:nothing_gallery/style.dart';
import 'package:nothing_gallery/classes/classes.dart';
import 'package:nothing_gallery/components/components.dart';
import 'package:nothing_gallery/constants/constants.dart';
import 'package:nothing_gallery/model/model.dart';
import 'package:nothing_gallery/util/util.dart';

class ImageGridWidget extends StatefulWidget {
  final AlbumInfo album;
  final bool selectImage;

  const ImageGridWidget(
      {super.key, required this.album, required this.selectImage});

  @override
  State createState() => _ImageGridState();
}

class _ImageGridState extends LifecycleListenerState<ImageGridWidget> {
  late AlbumInfo albumInfo;
  List<AssetEntity> images = [];
  List<AssetEntity> assets = [];
  Map<DateTime, List<AssetEntity>> dateMap = {};
  List<DateSection> sections = [];
  StreamSubscription? eventSubscription;
  final ScrollController _scrollController = ScrollController();

  int totalCount = 0;
  int numCol = 4;
  bool useTrashBin = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    albumInfo = widget.album;
    totalCount = albumInfo.assetCount;
    getPreferences();
    refreshGrid();

    final appStatus = Provider.of<AppStatus>(context, listen: false);

    eventSubscription =
        eventController.stream.asBroadcastStream().listen((event) {
      if (appStatus.activeTab == InitialScreen.timeline.tabIndex) return;

      switch (validateEventType(event)) {
        case EventType.assetDeleted:
        case EventType.assetMoved:
          final List<String> changedIds = (event.details is List)
              ? (event.details as List).map((e) => e.toString()).toList()
              : [];

          if (changedIds.isEmpty) {
            updateGrid();
            return;
          }

          removeIdsFromDateMap(dateMap, changedIds);
          final rebuiltSections = buildDateSections(dateMap);

          if (mounted) {
            setState(() {
              assets.removeWhere((image) => changedIds.contains(image.id));
              sections = rebuiltSections;
              images = collectOrderedImages(rebuiltSections);
              totalCount = (totalCount - changedIds.length).clamp(0, 1 << 30);
            });
          }
          break;
        case EventType.videoOpen:
          openVideoPlayerPage(context, event.details);
          break;
        case EventType.pictureOpen:
          final int idx = images
              .indexWhere((img) => img.id == (event.details as AssetEntity).id);
          if (idx != -1) {
            openImagePage(context, idx, images.length, images);
          }
          break;
        default:
      }
    });
  }

  @override
  void dispose() {
    eventSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> updateGrid() async {
    List<AlbumInfo> updatedAlbum =
        await getCurrentAlbumStates([albumInfo.pathEntity.id]);

    if (updatedAlbum.isEmpty) {
      if (mounted) {
        setState(() => totalCount = 0);
      }
      return;
    }
    albumInfo = updatedAlbum[0];
    totalCount = albumInfo.assetCount;
    await refreshGrid();
  }

  Future<void> refreshGrid() async {
    await getImages(clearFirst: assets.isEmpty);
  }

  void getPreferences() {
    numCol = sharedPref.get(SharedPrefKeys.imageGridPageNumCol);
    useTrashBin = sharedPref.get(SharedPrefKeys.useTrashBin);
  }

  Future<void> getImages({bool clearFirst = true}) async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      final List<AssetEntity> nextAssets = [];
      final Map<DateTime, List<AssetEntity>> nextDateMap = {};

      if (clearFirst) {
        assets.clear();
        images.clear();
        dateMap.clear();
        sections = [];
      }

      int cursor = 0;
      bool firstBatch = true;
      final int targetCount = albumInfo.assetCount;

      while (cursor < targetCount) {
        final int batchSize = firstBatch ? 100 : 500;
        firstBatch = false;

        final List<AssetEntity> newAssets =
            await loadAssetsRange(albumInfo.pathEntity, cursor, batchSize);
        if (newAssets.isEmpty) break;
        cursor += newAssets.length;

        nextAssets.addAll(newAssets);
        addAssetsToDateMap(nextDateMap, newAssets);

        if (clearFirst && mounted) {
          final List<DateSection> builtSections =
              buildDateSections(nextDateMap);
          final List<AssetEntity> orderedImages =
              collectOrderedImages(builtSections);
          setState(() {
            assets = List.from(nextAssets);
            dateMap = nextDateMap;
            sections = builtSections;
            images = orderedImages;
          });
        }
      }

      if (mounted && (!clearFirst || nextAssets.isEmpty)) {
        final List<DateSection> builtSections = buildDateSections(nextDateMap);
        final List<AssetEntity> orderedImages =
            collectOrderedImages(builtSections);
        setState(() {
          assets = nextAssets;
          dateMap = nextDateMap;
          sections = builtSections;
          images = orderedImages;
        });
      }
    } finally {
      _isLoading = false;
    }
  }

  Widget gridPageWrapper(Widget child) {
    return GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Scaffold(
            body: WillPopScope(
                onWillPop: () async {
                  final imageSelection =
                      Provider.of<ImageSelection>(context, listen: false);
                  final appStatus =
                      Provider.of<AppStatus>(context, listen: false);

                  if (imageSelection.selectionMode) {
                    imageSelection.endSelection();
                    return false;
                  }

                  return !appStatus.loading;
                },
                child: SafeArea(child: child))));
  }

  @override
  Widget build(BuildContext context) {
    if (totalCount == 0) {
      Future.microtask(() {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
      return Container();
    } else {
      return gridPageWrapper(Stack(
        children: [
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
                      widget.selectImage
                          ? 'CHOOSE THUMBNAIL'
                          : "${albumInfo.pathEntity.name.toUpperCase()} ($totalCount)",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mainTextStyle(TextStyleType.gridPageTitle),
                    )),
              ),
              Consumer<ImageSelection>(
                  builder: (context, imageSelection, child) {
                if (imageSelection.selectionMode) {
                  return SelectionMenu(
                    assets: assets,
                    showMore: true,
                    currentAlbum: albumInfo.pathEntity,
                  );
                }
                if (!widget.selectImage) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: Icon(
                        numCol == 4
                            ? Icons.grid_view_rounded
                            : numCol == 3
                                ? Icons.view_comfy_alt_outlined
                                : Icons.view_column_outlined,
                        size: 20,
                        color: Colors.white70,
                      ),
                      tooltip: "Grid columns: $numCol",
                      onPressed: () {
                        setState(() {
                          if (numCol >= 4) {
                            numCol = 3;
                          } else if (numCol == 3) {
                            numCol = 2;
                          } else {
                            numCol = 4;
                          }
                        });
                      },
                    ),
                  );
                }
                return const SizedBox.shrink();
              })
            ]),

            // Date-Sorted Virtualized Album Grid with Google Photos Fast Scroller
            Expanded(
              child: DateGroupedMediaGrid(
                controller: _scrollController,
                sections: sections,
                crossAxisCount: numCol,
                onRefresh: updateGrid,
                thumbnailSelection: widget.selectImage,
              ),
            ),
          ]),
          Consumer<AppStatus>(builder: (context, appStatus, child) {
            if (appStatus.loading) {
              return Center(
                  child: Container(
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10)),
                      height: 120,
                      width: 120,
                      child: const SpinKitSquareCircle(
                        color: Colors.white,
                        size: 42.0,
                      )));
            }
            return Container();
          }),
        ],
      ));
    }
  }

  @override
  void onDetached() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {}

  @override
  void onResumed() async {
    updateGrid();
  }

  @override
  void onHidden() {}
}
