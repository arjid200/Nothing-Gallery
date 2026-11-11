import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nothing_gallery/classes/classes.dart';
import 'package:nothing_gallery/style.dart';

class LockedPage extends StatefulWidget {
  const LockedPage({super.key});

  @override
  State<LockedPage> createState() => _LockedPageState();
}

class _LockedPageState extends State<LockedPage> {
  bool isUnlocked = false;
  bool hasExistingPin = false;
  bool isSettingPin = false;
  String enteredPin = '';
  String setupPinFirst = '';

  List<LockedItem> lockedItems = [];
  Set<String> selectedIds = {};
  bool isSelectionMode = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    checkPinStatus();
  }

  Future<void> checkPinStatus() async {
    final hasPin = await LockedManager.hasPin();
    setState(() {
      hasExistingPin = hasPin;
      isSettingPin = !hasPin;
      isLoading = false;
    });
  }

  Future<void> loadLockedItems() async {
    setState(() => isLoading = true);
    final items = await LockedManager.getLockedItems();
    if (mounted) {
      setState(() {
        lockedItems = items;
        selectedIds.clear();
        isSelectionMode = false;
        isLoading = false;
      });
    }
  }

  void onNumberPress(String digit) async {
    if (enteredPin.length >= 4) return;
    setState(() {
      enteredPin += digit;
    });

    if (enteredPin.length == 4) {
      if (isSettingPin) {
        if (setupPinFirst.isEmpty) {
          // First entry done, ask to confirm
          setState(() {
            setupPinFirst = enteredPin;
            enteredPin = '';
          });
        } else {
          // Confirm PIN
          if (enteredPin == setupPinFirst) {
            await LockedManager.setPin(enteredPin);
            Fluttertoast.showToast(msg: "PIN set successfully");
            setState(() {
              isUnlocked = true;
              isSettingPin = false;
            });
            await loadLockedItems();
          } else {
            Fluttertoast.showToast(msg: "PINs did not match, try again");
            setState(() {
              setupPinFirst = '';
              enteredPin = '';
            });
          }
        }
      } else {
        // Verifying existing PIN
        final valid = await LockedManager.verifyPin(enteredPin);
        if (valid) {
          setState(() {
            isUnlocked = true;
          });
          await loadLockedItems();
        } else {
          Fluttertoast.showToast(msg: "Incorrect PIN");
          setState(() {
            enteredPin = '';
          });
        }
      }
    }
  }

  void onBackspace() {
    if (enteredPin.isNotEmpty) {
      setState(() {
        enteredPin = enteredPin.substring(0, enteredPin.length - 1);
      });
    }
  }

  void toggleSelection(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
        if (selectedIds.isEmpty) isSelectionMode = false;
      } else {
        selectedIds.add(id);
        isSelectionMode = true;
      }
    });
  }

  Future<void> unlockSelected() async {
    final targets =
        lockedItems.where((i) => selectedIds.contains(i.id)).toList();
    if (targets.isEmpty) return;

    int unlocked = 0;
    for (final item in targets) {
      final ok = await LockedManager.unlockItem(item);
      if (ok) unlocked++;
    }

    Fluttertoast.showToast(
      msg: "Restored $unlocked item(s) to Gallery",
      toastLength: Toast.LENGTH_SHORT,
    );
    await loadLockedItems();
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
          "Delete ${selectedIds.length} locked item(s) permanently?",
          style: mainTextStyle(TextStyleType.settingsPageDescription),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("CANCEL", style: mainTextStyle(TextStyleType.buttonText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("DELETE",
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final targets =
          lockedItems.where((i) => selectedIds.contains(i.id)).toList();
      for (final item in targets) {
        await LockedManager.deleteLockedItem(item);
      }
      Fluttertoast.showToast(msg: "Deleted permanently");
      await loadLockedItems();
    }
  }

  void openPreview(LockedItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(item.filename,
                style: mainTextStyle(TextStyleType.picturesDateTaken),
                overflow: TextOverflow.ellipsis),
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
                    final success = await LockedManager.unlockItem(item);
                    if (success) {
                      Fluttertoast.showToast(msg: "Unlocked to Gallery");
                      loadLockedItems();
                    }
                  },
                  icon: const Icon(Icons.lock_open, color: Colors.white),
                  label: Text("UNLOCK",
                      style: mainTextStyle(TextStyleType.buttonText)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await LockedManager.deleteLockedItem(item);
                    Fluttertoast.showToast(msg: "Deleted permanently");
                    loadLockedItems();
                  },
                  icon: const Icon(Icons.delete_forever,
                      color: Colors.redAccent),
                  label: const Text("DELETE",
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinScreen() {
    String titleText = "ENTER PIN";
    if (isSettingPin) {
      titleText = setupPinFirst.isEmpty ? "SET 4-DIGIT PIN" : "CONFIRM PIN";
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 50, color: Colors.white),
            const SizedBox(height: 20),
            Text(
              titleText,
              style: mainTextStyle(TextStyleType.pageTitle),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Colors.redAccent : Colors.transparent,
                    border: Border.all(
                      color: filled ? Colors.redAccent : Colors.white38,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 40),
            // Keypad
            Column(
              children: [
                for (var row in [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', 'back'],
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: row.map((key) {
                        if (key.isEmpty) {
                          return const SizedBox(width: 70, height: 70);
                        }
                        if (key == 'back') {
                          return SizedBox(
                            width: 70,
                            height: 70,
                            child: IconButton(
                              icon: const Icon(Icons.backspace_outlined,
                                  color: Colors.white),
                              onPressed: onBackspace,
                            ),
                          );
                        }
                        return SizedBox(
                          width: 70,
                          height: 70,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white12),
                              shape: const CircleBorder(),
                              backgroundColor:
                                  const Color.fromRGBO(24, 28, 30, 0.8),
                            ),
                            onPressed: () => onNumberPress(key),
                            child: Text(
                              key,
                              style: const TextStyle(
                                fontSize: 24,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isUnlocked) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
        body: _buildPinScreen(),
      );
    }

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
                  : "LOCKED FOLDER",
              style: mainTextStyle(TextStyleType.pageTitle),
            ),
            if (!isSelectionMode)
              Text(
                "Hidden from gallery and external apps",
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
                  if (selectedIds.length == lockedItems.length) {
                    selectedIds.clear();
                    isSelectionMode = false;
                  } else {
                    selectedIds = lockedItems.map((e) => e.id).toSet();
                  }
                });
              },
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : lockedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_open,
                          size: 70, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        "NO LOCKED ITEMS",
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
                  itemCount: lockedItems.length,
                  itemBuilder: (ctx, index) {
                    final item = lockedItems[index];
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
                      onPressed: unlockSelected,
                      icon: const Icon(Icons.lock_open, color: Colors.white),
                      label: Text(
                        "UNLOCK (${selectedIds.length})",
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
