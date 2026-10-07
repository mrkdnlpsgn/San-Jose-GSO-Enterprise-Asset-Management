import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../model/maintenance_model.dart';
import '../data/maintenance_service.dart';
import '../provider/maintenance_provider.dart';
import '../../../features/assets/model/asset_model.dart';
import '../../../shared/widgets/asset_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/utils/idempotency.dart';

class MaintenanceFormScreen extends ConsumerStatefulWidget {
  final MaintenanceModel? maintenance;
  final AssetModel? preselectedAsset;
  const MaintenanceFormScreen({super.key, this.maintenance, this.preselectedAsset});

  @override
  ConsumerState<MaintenanceFormScreen> createState() => _MaintenanceFormScreenState();
}

class _MaintenanceFormScreenState extends ConsumerState<MaintenanceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final String _idempotencyKey = newIdempotencyKey();

  late final TextEditingController _findings;
  late final TextEditingController _actionsTaken;
  late final TextEditingController _assignedTo;
  late final TextEditingController _cost;

  AssetModel? _selectedAsset;
  String _maintenanceType = 'PREVENTIVE';
  String _status = 'SCHEDULED';
  DateTime? _maintenanceDate;

  bool get _isEdit => widget.maintenance != null;

  @override
  void initState() {
    super.initState();
    final m = widget.maintenance;
    _findings = TextEditingController(text: m?.findings ?? '');
    _actionsTaken = TextEditingController(text: m?.actionsTaken ?? '');
    _assignedTo = TextEditingController(text: m?.assignedTo ?? '');
    _cost = TextEditingController(text: m?.cost?.toStringAsFixed(2) ?? '');
    _maintenanceType = m?.maintenanceType ?? 'PREVENTIVE';
    _status = m?.status ?? 'SCHEDULED';
    _selectedAsset = m?.asset ?? widget.preselectedAsset;
    if (m?.maintenanceDate != null) _maintenanceDate = DateTime.tryParse(m!.maintenanceDate)?.toLocal();
  }

  @override
  void dispose() {
    for (final c in [_findings, _actionsTaken, _assignedTo, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAsset == null) { _showError('Please select an asset.'); return; }
    if (_maintenanceDate == null) { _showError('Please select a maintenance date.'); return; }
    setState(() => _loading = true);
    try {
      final data = {
        'assetId': _selectedAsset!.id,
        'maintenanceType': _maintenanceType,
        'findings': _findings.text.trim(),
        'actionsTaken': _actionsTaken.text.trim(),
        'assignedTo': _assignedTo.text.trim().isEmpty ? null : _assignedTo.text.trim(),
        'maintenanceDate': _maintenanceDate!.toIso8601String().substring(0, 10),
        'cost': _cost.text.trim().isEmpty ? null : double.parse(_cost.text.trim()),
        'status': _status,
      };
      final service = MaintenanceService();
      if (_isEdit) {
        await service.update(widget.maintenance!.id, data);
      } else {
        await service.create(data, idempotencyKey: _idempotencyKey);
      }
      ref.invalidate(maintenancePagedProvider(ref.read(maintenanceSearchProvider)));
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Maintenance' : 'New Maintenance')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Asset selector
            _assetSelector(),
            const SizedBox(height: 14),
            _enumDropdown('Type', _maintenanceType,
              ['PREVENTIVE', 'CORRECTIVE', 'REPAIR'], (v) => setState(() => _maintenanceType = v!)),
            _enumDropdown('Status', _status,
              ['SCHEDULED', 'ONGOING', 'COMPLETED'], (v) => setState(() => _status = v!)),
            _datePicker(),
            _field(_findings, 'Findings', required: true, maxLines: 3),
            _field(_actionsTaken, 'Actions Taken', required: true, maxLines: 3),
            _field(_assignedTo, 'Assigned To'),
            _field(_cost, 'Cost (₱)', keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEdit ? 'Save Changes' : 'Create Record'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _assetSelector() {
    return InkWell(
      onTap: _isEdit
          ? null
          : () async {
              final picked = await showAssetPicker(context, ref);
              if (picked != null) setState(() => _selectedAsset = picked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Asset',
          helperText: _isEdit ? 'Asset cannot be changed after creation' : null,
          suffixIcon: _isEdit
              ? Icon(Icons.lock_outline_rounded, size: 18, color: context.colors.textTertiary)
              : null,
        ),
        child: _selectedAsset != null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_selectedAsset!.description, style: TextStyle(color: context.colors.textPrimary, fontSize: 14)),
                Text(_selectedAsset!.propertyNumber, style: const TextStyle(color: AppTheme.brand, fontSize: 12)),
              ])
            : Text('Tap to select asset', style: TextStyle(color: context.colors.textSecondary)),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType, bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      ),
    );
  }

  Widget _enumDropdown(String label, String value, List<String> options, void Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        dropdownColor: context.colors.surface,
        items: options.map((e) => DropdownMenuItem(value: e, child: Text(e.replaceAll('_', ' ')))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _datePicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _maintenanceDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.brand),
              ),
              child: child!,
            ),
          );
          if (picked != null) setState(() => _maintenanceDate = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Maintenance Date'),
          child: Text(
            _maintenanceDate != null ? _maintenanceDate!.toIso8601String().substring(0, 10) : 'Tap to select',
            style: TextStyle(color: _maintenanceDate != null ? context.colors.textPrimary : context.colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
