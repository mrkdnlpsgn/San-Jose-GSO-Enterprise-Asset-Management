import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dense;

  const StatusBadge({super.key, required this.label, required this.color, this.dense = false});

  static StatusBadge condition(String value) {
    final color = switch (value) {
      'SERVICEABLE' => AppTheme.brand,
      'REPAIRABLE' => AppTheme.statusMaintenance,
      'UNSERVICEABLE' => AppTheme.statusDisposed,
      _ => Colors.grey,
    };
    final display = switch (value) {
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
      'ARCHIVED' => Colors.grey.shade600,
      _ => Colors.grey,
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
      'COMPLETED' => AppTheme.brand,
      'ONGOING' => AppTheme.statusMaintenance,
      _ => AppTheme.statusAssigned,
    };
    return StatusBadge(label: value.replaceAll('_', ' '), color: color, dense: dense);
  }

  static StatusBadge maintenanceType(String value, {bool dense = false}) {
    final color = switch (value) {
      'PREVENTIVE' => AppTheme.statusAssigned,
      'CORRECTIVE' => AppTheme.statusMaintenance,
      _ => Colors.purple,
    };
    return StatusBadge(label: value.replaceAll('_', ' '), color: color, dense: dense);
  }

  static StatusBadge disposalStatus(String value, {bool dense = false}) {
    final color = switch (value) {
      'COMPLETED' => AppTheme.brand,
      'APPROVED' => AppTheme.statusAssigned,
      _ => AppTheme.statusMaintenance,
    };
    return StatusBadge(label: value.replaceAll('_', ' '), color: color, dense: dense);
  }

  static StatusBadge disposalMethod(String value, {bool dense = false}) {
    final color = switch (value) {
      'SALE' => AppTheme.statusMaintenance,
      'DESTRUCTION' => AppTheme.statusDisposed,
      'OTHERS' => AppTheme.brand,
      _ => AppTheme.statusAssigned,
    };
    return StatusBadge(label: value.replaceAll('_', ' '), color: color, dense: dense);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(dense ? 5 : 6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
