import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../model/asset_model.dart';
import '../screens/asset_detail_screen.dart' show AssetHistoryTimeline;

/// The history of one asset in a sheet over the current screen, opened from a scanned QR so
/// the person stays on the scan result instead of landing on the History tab (every asset).
/// Opens at about 60% of the screen; drag it up for the full timeline.
Future<void> showAssetHistorySheet(BuildContext context, AssetModel asset) {
  return showModalBottomSheet<void>(
    useRootNavigator: true, // above the bottom bar, not behind it
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              children: [
                Text('Asset History',
                    style: TextStyle(color: context.colors.heading, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${asset.propertyNumber} · ${asset.description}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.textTertiary, fontSize: 14),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.border),
          Expanded(child: AssetHistoryTimeline(assetId: asset.id, controller: controller)),
        ],
      ),
    ),
  );
}
