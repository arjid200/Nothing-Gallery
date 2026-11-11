import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:nothing_gallery/components/components.dart';
import 'package:nothing_gallery/style.dart';

const List<String> _monthAbrev = [
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
];

class DateSection {
  final DateTime date;
  final String headerLabel;
  final String bubbleLabel;
  final List<AssetEntity> assets;

  const DateSection({
    required this.date,
    required this.headerLabel,
    required this.bubbleLabel,
    required this.assets,
  });
}

/// Inserts assets into a day-keyed map (YYYY-MM-DD), preventing duplicate IDs
/// and sorting each touched date bucket descending by creation timestamp.
void addAssetsToDateMap(
  Map<DateTime, List<AssetEntity>> dateMap,
  Iterable<AssetEntity> newAssets,
) {
  final Map<DateTime, Set<String>> seenByDate = {};

  for (final AssetEntity asset in newAssets) {
    final DateTime dt = asset.createDateTime;
    final DateTime dateKey = DateTime(dt.year, dt.month, dt.day);
    final List<AssetEntity> bucket = dateMap.putIfAbsent(dateKey, () => []);
    final Set<String> seen = seenByDate.putIfAbsent(
      dateKey,
      () => bucket.map((e) => e.id).toSet(),
    );
    if (seen.add(asset.id)) {
      bucket.add(asset);
    }
  }

  for (final DateTime dateKey in seenByDate.keys) {
    dateMap[dateKey]!
        .sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
  }
}

/// Removes matching asset IDs from [dateMap] and prunes empty date buckets.
void removeIdsFromDateMap(
  Map<DateTime, List<AssetEntity>> dateMap,
  Iterable<String> ids,
) {
  final Set<String> idSet = ids is Set<String> ? ids : ids.toSet();
  if (idSet.isEmpty) return;

  final List<DateTime> emptyDates = [];
  dateMap.forEach((date, list) {
    list.removeWhere((asset) => idSet.contains(asset.id));
    if (list.isEmpty) {
      emptyDates.add(date);
    }
  });
  for (final date in emptyDates) {
    dateMap.remove(date);
  }
}

/// Converts a day-keyed map into sorted [DateSection] entries (newest first).
List<DateSection> buildDateSections(
  Map<DateTime, List<AssetEntity>> dateMap, {
  bool Function(AssetEntity)? filter,
}) {
  final int currentYear = DateTime.now().year;
  final List<MapEntry<DateTime, List<AssetEntity>>> entries = [];

  for (final entry in dateMap.entries) {
    final List<AssetEntity> items = filter == null
        ? entry.value
        : entry.value.where(filter).toList();
    if (items.isNotEmpty) {
      entries.add(MapEntry(entry.key, items));
    }
  }

  entries.sort((a, b) => b.key.compareTo(a.key));

  return entries.map((entry) {
    final DateTime d = entry.key;
    final String month = _monthAbrev[d.month];
    final String headerLabel =
        d.year == currentYear ? "$month ${d.day}" : "${d.year} $month ${d.day}";
    final String bubbleLabel =
        d.year == currentYear ? "$month ${d.day}" : "$month ${d.day}, ${d.year}";

    return DateSection(
      date: d,
      headerLabel: headerLabel,
      bubbleLabel: bubbleLabel,
      assets: entry.value,
    );
  }).toList();
}

/// Flattens image entities from ordered [DateSection]s so full-screen viewer
/// swipe order matches the visual grid order.
List<AssetEntity> collectOrderedImages(List<DateSection> sections) {
  final List<AssetEntity> ordered = [];
  for (final section in sections) {
    for (final asset in section.assets) {
      if (asset.type == AssetType.image) {
        ordered.add(asset);
      }
    }
  }
  return ordered;
}

class DateSliverOffsetIndex {
  final List<double> sectionEndOffsets;
  final List<String> labels;
  final double totalExtent;

  DateSliverOffsetIndex._(
    this.sectionEndOffsets,
    this.labels,
    this.totalExtent,
  );

  factory DateSliverOffsetIndex.build({
    required List<DateSection> sections,
    required double viewportWidth,
    required int crossAxisCount,
    double crossAxisSpacing = 2.0,
    double mainAxisSpacing = 2.0,
    double headerHeight = 46.0,
    double sectionBottomPadding = 10.0,
  }) {
    if (sections.isEmpty || viewportWidth <= 0 || crossAxisCount <= 0) {
      return DateSliverOffsetIndex._(const [], const [], 0.0);
    }

    final double usableWidth =
        math.max(0.0, viewportWidth - crossAxisSpacing * (crossAxisCount - 1));
    final double tileExtent = usableWidth / crossAxisCount;
    final double stride = tileExtent + mainAxisSpacing;

    final List<double> ends = List<double>.filled(sections.length, 0.0);
    final List<String> labels = List<String>.filled(sections.length, '');
    double running = 0.0;

    for (int i = 0; i < sections.length; i++) {
      final int count = sections[i].assets.length;
      double gridHeight = 0.0;
      if (count > 0) {
        final int rows = ((count - 1) ~/ crossAxisCount) + 1;
        gridHeight = stride * rows - mainAxisSpacing;
      }
      running += headerHeight + gridHeight + sectionBottomPadding;
      ends[i] = running;
      labels[i] = sections[i].bubbleLabel;
    }

    return DateSliverOffsetIndex._(ends, labels, running);
  }

  String labelForOffset(double offset) {
    if (sectionEndOffsets.isEmpty) return '';
    if (offset <= sectionEndOffsets.first) return labels.first;
    if (offset >= sectionEndOffsets.last) return labels.last;

    int low = 0;
    int high = sectionEndOffsets.length - 1;
    while (low < high) {
      final int mid = (low + high) >> 1;
      if (sectionEndOffsets[mid] <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return labels[low];
  }
}

/// Google Photos-style right-edge semi-circle fast scroller with a floating
/// date indicator bubble during scrubbing.
class MediaFastScroller extends StatefulWidget {
  final ScrollController scrollController;
  final String Function(double documentY) labelBuilder;
  final Widget child;

  const MediaFastScroller({
    super.key,
    required this.scrollController,
    required this.labelBuilder,
    required this.child,
  });

  @override
  State<MediaFastScroller> createState() => _MediaFastScrollerState();
}

class _MediaFastScrollerState extends State<MediaFastScroller> {
  static const double _topMargin = 8.0;
  static const double _bottomMargin = 20.0;
  static const double _thumbHeight = 52.0;
  static const double _minScrollableExtent = 140.0;

  bool _isVisible = false;
  bool _isDragging = false;
  bool _isScrollable = false;
  bool _hasShownInitialHint = false;

  double _scrollFraction = 0.0;
  double _lastScrollPixels = 0.0;
  double _dragStartGlobalY = 0.0;
  double _dragStartFraction = 0.0;
  String _currentLabel = '';
  DateTime? _lastHapticAt;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onControllerScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMetrics());
  }

  @override
  void didUpdateWidget(covariant MediaFastScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onControllerScroll);
      widget.scrollController.addListener(_onControllerScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMetrics());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.scrollController.removeListener(_onControllerScroll);
    super.dispose();
  }

  void _syncMetrics() {
    if (!mounted || !widget.scrollController.hasClients) return;
    if (widget.scrollController.positions.length != 1) return;

    final ScrollPosition pos = widget.scrollController.position;
    final double maxExtent = pos.maxScrollExtent;
    final bool canScroll = maxExtent > _minScrollableExtent;
    final double nextFraction =
        canScroll ? (pos.pixels / maxExtent).clamp(0.0, 1.0) : 0.0;

    if (!canScroll) {
      if (_isScrollable || _isVisible) {
        _hideTimer?.cancel();
        setState(() {
          _isScrollable = false;
          _isVisible = false;
          _isDragging = false;
          _scrollFraction = 0.0;
        });
      }
      return;
    }

    final bool shouldShowInitialHint =
        !_hasShownInitialHint && maxExtent > pos.viewportDimension * 0.7;

    if (!_isDragging) {
      if (shouldShowInitialHint) {
        _hasShownInitialHint = true;
        _isScrollable = true;
        _scrollFraction = nextFraction;
        _lastScrollPixels = pos.pixels;
        _revealTemporarily(duration: const Duration(milliseconds: 2600));
      } else if (_isScrollable != canScroll ||
          (_scrollFraction - nextFraction).abs() > 0.002) {
        setState(() {
          _isScrollable = canScroll;
          _scrollFraction = nextFraction;
        });
      }
    }
  }

  void _onControllerScroll() {
    if (!mounted || _isDragging || !widget.scrollController.hasClients) return;
    if (widget.scrollController.positions.length != 1) return;

    final ScrollPosition pos = widget.scrollController.position;
    final double maxExtent = pos.maxScrollExtent;
    final bool canScroll = maxExtent > _minScrollableExtent;

    if (!canScroll) {
      if (_isScrollable || _isVisible) {
        _hideTimer?.cancel();
        setState(() {
          _isScrollable = false;
          _isVisible = false;
        });
      }
      return;
    }

    final double pixels = pos.pixels;
    final bool movedSignificantly = (pixels - _lastScrollPixels).abs() > 0.5;
    _lastScrollPixels = pixels;
    _scrollFraction = (pixels / maxExtent).clamp(0.0, 1.0);
    _isScrollable = true;

    if (movedSignificantly) {
      _revealTemporarily();
    } else if (_isVisible) {
      setState(() {});
    }
  }

  void _revealTemporarily({
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    _hideTimer?.cancel();
    if (!_isVisible) {
      setState(() => _isVisible = true);
    } else {
      setState(() {});
    }
    _hideTimer = Timer(duration, () {
      if (mounted && !_isDragging) {
        setState(() => _isVisible = false);
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.scrollController.hasClients) return;
    if (widget.scrollController.positions.length != 1) return;

    _hideTimer?.cancel();
    _dragStartGlobalY = details.globalPosition.dy;
    _dragStartFraction = _scrollFraction;

    final ScrollPosition pos = widget.scrollController.position;
    final double docY = pos.pixels + (_scrollFraction * pos.viewportDimension);

    HapticFeedback.lightImpact();
    setState(() {
      _isDragging = true;
      _isVisible = true;
      _currentLabel = widget.labelBuilder(docY);
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double trackExtent) {
    if (!widget.scrollController.hasClients || trackExtent <= 0) return;
    if (widget.scrollController.positions.length != 1) return;

    final double deltaY = details.globalPosition.dy - _dragStartGlobalY;
    final double nextFraction =
        (_dragStartFraction + (deltaY / trackExtent)).clamp(0.0, 1.0);

    final ScrollPosition pos = widget.scrollController.position;
    final double maxExtent = pos.maxScrollExtent;
    final double targetOffset = (nextFraction * maxExtent).clamp(0.0, maxExtent);

    widget.scrollController.jumpTo(targetOffset);

    // Document Y aligned horizontally with the user's thumb on screen
    final double docY =
        targetOffset + (nextFraction * pos.viewportDimension);
    final String nextLabel = widget.labelBuilder(docY);

    if (nextLabel != _currentLabel && nextLabel.isNotEmpty) {
      final DateTime now = DateTime.now();
      if (_lastHapticAt == null ||
          now.difference(_lastHapticAt!).inMilliseconds >= 65) {
        _lastHapticAt = now;
        HapticFeedback.selectionClick();
      }
    }

    setState(() {
      _scrollFraction = nextFraction;
      _lastScrollPixels = targetOffset;
      _currentLabel = nextLabel;
    });
  }

  void _onDragEnd() {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _revealTemporarily();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double height = constraints.maxHeight;
        final double trackExtent =
            math.max(1.0, height - _topMargin - _bottomMargin - _thumbHeight);
        final double thumbTop =
            _topMargin + (_scrollFraction.clamp(0.0, 1.0) * trackExtent);
        const double bubbleHeight = 36.0;
        final double bubbleTop = (thumbTop + (_thumbHeight - bubbleHeight) / 2.0)
            .clamp(_topMargin, math.max(_topMargin, height - _bottomMargin - bubbleHeight));

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification &&
                    notification.dragDetails != null) {
                  _onControllerScroll();
                } else if (notification is ScrollEndNotification) {
                  _syncMetrics();
                }
                return false;
              },
              child: widget.child,
            ),
            // Floating Date Bubble while scrubbing
            Positioned(
              right: 54,
              top: bubbleTop,
              child: IgnorePointer(
                ignoring: true,
                child: AnimatedOpacity(
                  opacity:
                      (_isDragging && _currentLabel.isNotEmpty) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    height: bubbleHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(22, 25, 28, 0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white24, width: 1),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          _currentLabel,
                          style: mainTextStyle(TextStyleType.buttonText).copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Semi-circle Fast Scroll Thumb on right edge
            Positioned(
              right: 0,
              top: thumbTop - 4,
              child: IgnorePointer(
                ignoring: !_isVisible || !_isScrollable,
                child: AnimatedOpacity(
                  opacity: (_isVisible && _isScrollable) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: _onDragStart,
                    onVerticalDragUpdate: (d) => _onDragUpdate(d, trackExtent),
                    onVerticalDragEnd: (_) => _onDragEnd(),
                    onVerticalDragCancel: _onDragEnd,
                    child: Container(
                      width: 48,
                      height: _thumbHeight + 8,
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: _isDragging ? 42 : 36,
                        height: _thumbHeight,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? Colors.white
                              : const Color.fromRGBO(32, 36, 40, 0.94),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(28),
                          ),
                          border: Border.all(
                            color: _isDragging ? Colors.white : Colors.white24,
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(-1, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.unfold_more_rounded,
                            size: 22,
                            color: _isDragging ? Colors.black87 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shared date-grouped virtualized sliver grid with Google Photos-style fast
/// scrolling and pull-to-refresh.
class DateGroupedMediaGrid extends StatelessWidget {
  static const double headerHeight = 46.0;
  static const double gridSpacing = 2.0;
  static const double sectionBottomPadding = 10.0;

  final ScrollController controller;
  final List<DateSection> sections;
  final int crossAxisCount;
  final Future<void> Function() onRefresh;
  final bool favoritePage;
  final bool thumbnailSelection;
  final Widget? emptyState;

  const DateGroupedMediaGrid({
    super.key,
    required this.controller,
    required this.sections,
    required this.crossAxisCount,
    required this.onRefresh,
    this.favoritePage = false,
    this.thumbnailSelection = false,
    this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final DateSliverOffsetIndex offsetIndex = DateSliverOffsetIndex.build(
          sections: sections,
          viewportWidth: constraints.maxWidth,
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: gridSpacing,
          headerHeight: headerHeight,
          sectionBottomPadding: sectionBottomPadding,
        );

        return MediaFastScroller(
          scrollController: controller,
          labelBuilder: (docY) => offsetIndex.labelForOffset(docY),
          child: RefreshIndicator(
            color: Colors.red,
            onRefresh: onRefresh,
            child: sections.isEmpty && emptyState != null
                ? CustomScrollView(
                    controller: controller,
                    primary: false,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: emptyState!,
                      ),
                    ],
                  )
                : CustomScrollView(
                    controller: controller,
                    primary: false,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      for (final section in sections) ...[
                        SliverFixedExtentList(
                          itemExtent: headerHeight,
                          delegate: SliverChildBuilderDelegate(
                            (ctx, _) => Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  section.headerLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mainTextStyle(
                                      TextStyleType.picturesDateTaken),
                                ),
                              ),
                            ),
                            childCount: 1,
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.only(
                              bottom: sectionBottomPadding),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: gridSpacing,
                              mainAxisSpacing: gridSpacing,
                              childAspectRatio: 1.0,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (ctx, index) => GridItemWidget(
                                context: context,
                                asset: section.assets[index],
                                favoritePage: favoritePage,
                                thumbnailSelection: thumbnailSelection,
                              ),
                              childCount: section.assets.length,
                            ),
                          ),
                        ),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
