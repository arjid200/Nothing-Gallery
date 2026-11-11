import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nothing_gallery/classes/classes.dart';
import 'package:nothing_gallery/constants/constants.dart';
import 'package:nothing_gallery/main.dart';
import 'package:nothing_gallery/style.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashedItem> trashedItems = [];
  Set<String> selectedIds = {};
  bool isSelectionMode = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadTrash();
  }

  Future<void> loadTrash() async {
    setState(() => isLoading = true);
    final items = await TrashManager.getTrashedItems();
    if (mounted) {
      setState(() {
        trashedItems = items;
        selectedIds.clear();
        isSelectionMode = false;
        isLoading = false;
      });
    }
  }

  void toggleSelection(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
        if (selectedIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedIds.add(id);
        isSelectionMode = true;
      }
    });
  }

  Future<void> restoreSelected() async {
    final targets =
        trashedItems.where((i) => selectedIds.contains(i.id)).toList();
    if (targets.isEmpty) return;

    final success = await TrashManager.restoreMultipleItems(targets);
    if (success) {
      Fluttertoast.showToast(
        msg: "Restored ${targets.length} item(s)",
        toastLength: Toast.LENGTH_SHORT,
      );
      eventController.sink.add(Event(EventType.assetMoved, []));
    }
    await loadTrash();
  }

  Future<void> deleteSelectedPermanently() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color.fromRGBO(24, 28, 30, 1),
        title: Text(
          "DELETE PERMANENTLY",
          style: mainTextStyle(TextStyleType.alertTitle),
        ),
        content: Text(
          "Permanently delete ${selectedIds.length} item(s)? This action cannot be undone.",
          style: mainTextStyle(TextStyleType.settingsPageDescription),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("CANCEL", style: mainTextStyle(TextStyleType.buttonText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              "DELETE",
              style: TextStyle(
                color: Colors.redAccent,
                fontFamily: mainTextStyle(TextStyleType.buttonText).fontFamily,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final targets =
          trashedItems.where((i) => selectedIds.contains(i.id)).toList();
      final success = await TrashManager.permanentlyDeleteMultiple(targets);
      if (success) {
        Fluttertoast.showToast(
          msg: "Deleted permanently",
          toastLength: Toast.LENGTH_SHORT,
        );
      }
      await loadTrash();
    }
  }

  Future<void> confirmEmptyTrash() async {
    if (trashedItems.isEmpty) {
      Fluttertoast.showToast(msg: "Trash is already empty");
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color.fromRGBO(24, 28, 30, 1),
        title: Text(
          "EMPTY TRASH",
          style: mainTextStyle(TextStyleType.alertTitle),
        ),
        content: Text(
          "Empty all items from Trash? This cannot be undone.",
          style: mainTextStyle(TextStyleType.settingsPageDescription),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("CANCEL", style: mainTextStyle(TextStyleType.buttonText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              "EMPTY ALL",
              style: TextStyle(
                color: Colors.redAccent,
                fontFamily: mainTextStyle(TextStyleType.buttonText).fontFamily,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await TrashManager.emptyTrash();
      Fluttertoast.showToast(msg: "Trash emptied");
      await loadTrash();
    }
  }

  void openPreview(TrashedItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(
              item.filename,
              style: mainTextStyle(TextStyleType.picturesDateTaken),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(item.localPath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 60,
                ),
              ),
            ),
          ),
          bottomNavigationBar: Container(
            color: const Color.fromRGBO(24, 28, 30, 1),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final success =
                        await TrashManager.restoreMultipleItems([item]);
                    if (success) {
                      Fluttertoast.showToast(msg: "Restored");
                      eventController.sink
                          .add(Event(EventType.assetMoved, []));
                      loadTrash();
                    }
                  },
                  icon: const Icon(Icons.restore, color: Colors.white),
                  label: Text("RESTORE",
                      style: mainTextStyle(TextStyleType.buttonText)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final success =
                        await TrashManager.permanentlyDeleteMultiple([item]);
                    if (success) {
                      Fluttertoast.showToast(msg: "Deleted permanently");
                    }
                    loadTrash();
                  },
                  icon: const Icon(Icons.delete_forever,
                      color: Colors.redAccent),
                  label: const Text(
                    "DELETE",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSelectionMode
                  ? "${selectedIds.length} SELECTED"
                  : "TRASH",
              style: mainTextStyle(TextStyleType.pageTitle),
            ),
            if (!isSelectionMode)
              Text(
                "Kept for 30 days before permanent deletion",
                style: mainTextStyle(TextStyleType.albumTitle3)
                    .copyWith(color: Colors.white54),
              ),
          ],
        ),
        actions: [
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: () {
                setState(() {
                  if (selectedIds.length == trashedItems.length) {
                    selectedIds.clear();
                    isSelectionMode = false;
                  } else {
                    selectedIds = trashedItems.map((e) => e.id).toSet();
                  }
                });
              },
            )
          else
            PopupMenuButton<String>(
              color: const Color.fromRGBO(30, 30, 30, 1),
              onSelected: (val) {
                if (val == 'empty') confirmEmptyTrash();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'empty',
                  child: Text(
                    "Empty Trash",
                    style: mainTextStyle(TextStyleType.popUpMenu),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : trashedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_outline,
                          size: 70, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        "TRASH IS EMPTY",
                        style: mainTextStyle(TextStyleType.gridPageTitle)
                            .copyWith(color: Colors.white38),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: trashedItems.length,
                  itemBuilder: (ctx, index) {
                    final item = trashedItems[index];
                    final isSelected = selectedIds.contains(item.id);

                    return GestureDetector(
                      onLongPress: () => toggleSelection(item.id),
                      onTap: () {
                        if (isSelectionMode) {
                          toggleSelection(item.id);
                        } else {
                          openPreview(item);
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              File(item.localPath),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[900],
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.white38,
                                ),
                              ),
                            ),
                          ),
                          if (item.isVideo)
                            const Positioned(
                              bottom: 4,
                              right: 4,
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          if (isSelected)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                border: Border.all(
                                    color: Colors.white, width: 2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: Icon(Icons.check_circle,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: isSelectionMode
          ? Container(
              color: const Color.fromRGBO(24, 28, 30, 1),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: restoreSelected,
                      icon: const Icon(Icons.restore, color: Colors.white),
                      label: Text(
                        "RESTORE (${selectedIds.length})",
                        style: mainTextStyle(TextStyleType.buttonText),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: deleteSelectedPermanently,
                      icon: const Icon(Icons.delete_forever,
                          color: Colors.redAccent),
                      label: Text(
                        "DELETE FOREVER",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontFamily:
                              mainTextStyle(TextStyleType.buttonText).fontFamily,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
