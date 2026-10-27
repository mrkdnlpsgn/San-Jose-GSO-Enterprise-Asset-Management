import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dense;

  const StatusBadge({super.key, required this.label, required this.color, this.dense = false});

  // Staff-requested maintenance/disposal awaiting (or refused) admin review - mirrors
  // web's ApprovalBadge. Null for approved records, which show no badge.
  static StatusBadge? approval(String? value) => switch (value) {
        'PENDING_APPROVAL' => const StatusBadge(label: 'Awaiting approval', color: AppTheme.statusMaintenance, dense: true),
        'REJECTED' => const StatusBadge(label: 'Rejected', color: AppTheme.statusDisposed, dense: true),
        _ => null,
      };

  static StatusBadge condition(String value) {
    final color = switch (value) {
      'NEW' => AppTheme.statusRegistered,         // web: sky
      'GOOD' => AppTheme.conditionGood,           // web: teal
      'SERVICEABLE' => AppTheme.statusAssigned,   // web: emerald
      'REPAIRABLE' => AppTheme.statusMaintenance,
      'UNSERVICEABLE' => AppTheme.statusDisposed,
      _ => AppTheme.statusArchived,
    };
    final display = switch (value) {
      'NEW' => 'New',
      'GOOD' => 'Good',
      'SERVICEABLE' => 'Serviceable',
      'REPAIRABLE' => 'Repairable',
      'UNSERVICEABLE' => 'Unserviceable',
      _ => value,
    };
    return StatusBadge(label: display, color: color);
  }

  static StatusBadge lifecycle(String value) {
    final color = switch (value) {
      'REGISTERED' => AppTheme.statusRegistered,
      'ASSIGNED' => AppTheme.statusAssigned,
      'TRANSFERRED' => AppTheme.statusTransferred,
      'UNDER_MAINTENANCE' => AppTheme.statusMaintenance,
      'DISPOSED' => AppTheme.statusDisposed,
      'ARCHIVED' => AppTheme.statusArchived,
      _ => AppTheme.statusArchived,
    };
    final display = switch (value) {
      'REGISTERED' => 'Registered',
      'ASSIGNED' => 'Assigned',
      'TRANSFERRED' => 'Transferred',
      'UNDER_MAINTENANCE' => 'Under Maintenance',
      'DISPOSED' => 'Disposed',
      'ARCHIVED' => 'Archived',
      _ => value,
    };
    return StatusBadge(label: display, color: color);
  }

  static StatusBadge maintenanceStatus(String value, {bool dense = false}) {
    final color = switch (value) {
      'COMPLETED' => AppTheme.statusAssigned,
      'ONGOING' => AppTheme.statusMaintenance,
      _ => AppTheme.info,
    };
    return StatusBadge(label: _titleCase(value), color: color, dense: dense);
  }

  static StatusBadge maintenanceType(String value, {bool dense = false}) {
    final color = switch (value) {
      'PREVENTIVE' => AppTheme.info,
      'CORRECTIVE' => AppTheme.statusTransferred,   // web: orange
      'REPAIR' => AppTheme.statusDisposed,          // web: red
      _ => AppTheme.statusArchived,
    };
    return StatusBadge(label: _titleCase(value), color: color, dense: dense);
  }

  static StatusBadge disposalStatus(String value, {bool dense = false}) {
    final color = switch (value) {
      'COMPLETED' => AppTheme.statusAssigned,
      'APPROVED' => AppTheme.info,
      _ => AppTheme.statusMaintenance,
    };
    return StatusBadge(label: _titleCase(value), color: color, dense: dense);
  }

  static StatusBadge disposalMethod(String value, {bool dense = false}) {
    final color = switch (value) {
      'SALE' => AppTheme.info,
      'TRANSFER' => AppTheme.statusTransferred,
      'DESTRUCTION' => AppTheme.statusDisposed,
      'OTHERS' => AppTheme.statusAssigned,
      _ => AppTheme.statusArchived,
    };
    return StatusBadge(label: _titleCase(value), color: color, dense: dense);
  }

  // Same look as the web app's Badge: a pill with a faint tint, a hairline ring and a
  // leading dot. On white the label uses a darker shade of the hue so it stays readable.
  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final hsl = HSLColor.fromColor(color);
    final textColor = light
        ? hsl.withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0)).toColor()
        : hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
    // iOS tag: a soft tinted capsule - no outline, no dot. The colour (and so the meaning)
    // matches the web's badges; the darkened text keeps it readable on the tint.
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: light ? 0.14 : 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: dense ? 12.5 : 13.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

/// "UNDER_MAINTENANCE" → "Under Maintenance"
String _titleCase(String raw) => raw
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');
