import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nothing_gallery/style.dart';

void showExifDetailsSheet(BuildContext context, AssetEntity asset) async {
  File? file = await asset.file;
  int fileSize = 0;
  if (file != null && await file.exists()) {
    fileSize = await file.length();
  }

  String formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(1)} KB";
    }
    return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
  }

  String megapixels =
      ((asset.width * asset.height) / 1000000).toStringAsFixed(1);
  String formattedDate =
      DateFormat('EEEE, MMM d, yyyy • h:mm a').format(asset.createDateTime);

  final double lat = asset.latitude;
  final double lng = asset.longitude;
  final bool hasGps = lat != 0.0 || lng != 0.0;

  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color.fromRGBO(20, 22, 24, 0.96),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  "DETAILS",
                  style: mainTextStyle(TextStyleType.pageTitle),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    asset.type == AssetType.video ? "VIDEO" : "PHOTO",
                    style: mainTextStyle(TextStyleType.buttonText)
                        .copyWith(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildDetailRow(
              icon: Icons.calendar_today_rounded,
              title: "DATE & TIME",
              value: formattedDate,
            ),
            _buildDetailRow(
              icon: Icons.image_outlined,
              title: "RESOLUTION & SIZE",
              value:
                  "${asset.width} × ${asset.height} ($megapixels MP) • ${formatSize(fileSize)}",
            ),
            if (asset.type == AssetType.video && asset.duration > 0)
              _buildDetailRow(
                icon: Icons.timer_outlined,
                title: "DURATION",
                value:
                    "${(asset.duration ~/ 60).toString().padLeft(2, '0')}:${(asset.duration % 60).toString().padLeft(2, '0')}",
              ),
            _buildDetailRow(
              icon: Icons.insert_drive_file_outlined,
              title: "FILE NAME",
              value: asset.title ?? file?.path.split(Platform.pathSeparator).last ?? "Unknown",
            ),
            if (file != null)
              _buildDetailRow(
                icon: Icons.folder_open_rounded,
                title: "PATH",
                value: file.path,
              ),
            if (hasGps) ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                icon: Icons.location_on_outlined,
                title: "LOCATION",
                value:
                    "${lat.toStringAsFixed(4)}°, ${lng.toStringAsFixed(4)}°",
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(
                        "geo:$lat,$lng?q=$lat,$lng");
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  icon: const Icon(Icons.map_outlined, color: Colors.white),
                  label: Text(
                    "OPEN IN MAPS",
                    style: mainTextStyle(TextStyleType.buttonText),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _buildDetailRow(
    {required IconData icon,
    required String title,
    required String value}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.white54),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: mainTextStyle(TextStyleType.albumTitle3)
                    .copyWith(color: Colors.white38, letterSpacing: 1.2),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: mainTextStyle(TextStyleType.buttonText)
                    .copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
