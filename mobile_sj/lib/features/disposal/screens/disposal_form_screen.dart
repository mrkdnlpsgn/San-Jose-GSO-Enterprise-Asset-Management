import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../model/disposal_model.dart';
import '../data/disposal_service.dart';
import '../provider/disposal_provider.dart';
import '../../../features/assets/model/asset_model.dart';
import '../../../shared/widgets/asset_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/utils/idempotency.dart';

class DisposalFormScreen extends ConsumerStatefulWidget {
  final DisposalModel? disposal;
  final AssetModel? preselectedAsset;
  const DisposalFormScreen({super.key, this.disposal, this.preselectedAsset});

  @override
  ConsumerState<DisposalFormScreen> createState() => _DisposalFormScreenState();
}

class _DisposalFormScreenState extends ConsumerState<DisposalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final String _idempotencyKey = newIdempotencyKey();

  late final TextEditingController _reason;
  late final TextEditingController _inspectionFindings;
  late final TextEditingController _approvedBy;
  late final TextEditingController _appraisedValue;
  late final TextEditingController _orNumber;
  late final TextEditingController _amount;

  AssetModel? _selectedAsset;
  String _recommendedMethod = 'SALE';
  String _disposalStatus = 'PENDING';
  DateTime? _inspectionDate;

  bool get _isEdit => widget.disposal != null;

  @override
  void initState() {
    super.initState();
    final d = widget.disposal;
    _reason = TextEditingController(text: d?.reason ?? '');
    _inspectionFindings = TextEditingController(text: d?.inspectionFindings ?? '');
    _approvedBy = TextEditingController(text: d?.approvedBy ?? '');
    _appraisedValue = TextEditingController(text: d?.appraisedValue?.toStringAsFixed(2) ?? '');
    _orNumber = TextEditingController(text: d?.orNumber ?? '');
    _amount = TextEditingController(text: d?.amount?.toStringAsFixed(2) ?? '');
    _recommendedMethod = d?.recommendedMethod ?? 'SALE';
    _disposalStatus = d?.disposalStatus ?? 'PENDING';
    _selectedAsset = d?.asset ?? widget.preselectedAsset;
    if (d?.inspectionDate != null) _inspectionDate = DateTime.tryParse(d!.inspectionDate);
  }

  @override
  void dispose() {
    for (final c in [_reason, _inspectionFindings, _approvedBy, _appraisedValue, _orNumber, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAsset == null) { _showError('Please select an asset.'); return; }
    if (_inspectionDate == null) { _showError('Please select an inspection date.'); return; }
    setState(() => _loading = true);
    try {
      final data = {
        'assetId': _selectedAsset!.id,
        'reason': _reason.text.trim(),
        'inspectionFindings': _inspectionFindings.text.trim(),
        'recommendedMethod': _recommendedMethod,
        'disposalStatus': _disposalStatus,
        'inspectionDate': _inspectionDate!.toIso8601String().substring(0, 10),
        'approvedBy': _approvedBy.text.trim().isEmpty ? null : _approvedBy.text.trim(),
        'appraisedValue': _appraisedValue.text.trim().isEmpty ? null : double.parse(_appraisedValue.text.trim()),
        'orNumber': _orNumber.text.trim().isEmpty ? null : _orNumber.text.trim(),
        'amount': _amount.text.trim().isEmpty ? null : double.parse(_amount.text.trim()),
      };
      final service = DisposalService();
      if (_isEdit) {
        await service.update(widget.disposal!.id, data);
      } else {
        await service.create(data, idempotencyKey: _idempotencyKey);
      }
      ref.invalidate(disposalPagedProvider(ref.read(disposalSearchProvider)));
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
      appBar: AppBar(title: Text(_isEdit ? 'Edit Disposal' : 'New Disposal')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _assetSelector(),
            if (_selectedAsset != null) _assetDepreciationPreview(),
            const SizedBox(height: 14),
            _enumDropdown('Recommended Method', _recommendedMethod,
              ['SALE', 'TRANSFER', 'DESTRUCTION', 'OTHERS'], (v) => setState(() => _recommendedMethod = v!)),
            _enumDropdown('Status', _disposalStatus,
              ['PENDING', 'APPROVED', 'COMPLETED'], (v) => setState(() => _disposalStatus = v!)),
            _datePicker(),
            _field(_reason, 'Reason for Disposal', required: true, maxLines: 3),
            _field(_inspectionFindings, 'Inspection Findings', required: true, maxLines: 3),
            _field(_approvedBy, 'Approved By'),
            _field(_appraisedValue, 'Appraised Value (₱)', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _field(_orNumber, 'OR No.'),
            _field(_amount, 'Amount (₱)', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text('OR No. and Amount are typically filled in once the item has actually been sold.',
                  style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
            ),
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

  Widget _assetDepreciationPreview() {
    final asset = _selectedAsset!;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.textTertiary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _depRow('Unit Cost', '₱${asset.unitValue.toStringAsFixed(2)}'),
            _depRow('Accumulated Depreciation',
                asset.accumulatedDepreciation != null ? '₱${asset.accumulatedDepreciation!.toStringAsFixed(2)}' : '—'),
            _depRow('Carrying Amount',
                asset.carryingAmount != null ? '₱${asset.carryingAmount!.toStringAsFixed(2)}' : '—'),
          ],
        ),
      ),
    );
  }

  Widget _depRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: context.colors.textTertiary, fontSize: 12)),
            Text(value, style: TextStyle(color: context.colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  Widget _field(TextEditingController ctrl, String label,
      {bool required = false, int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
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
        items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
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
            initialDate: _inspectionDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.brand),
              ),
              child: child!,
            ),
          );
          if (picked != null) setState(() => _inspectionDate = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Inspection Date'),
          child: Text(
            _inspectionDate != null ? _inspectionDate!.toIso8601String().substring(0, 10) : 'Tap to select',
            style: TextStyle(color: _inspectionDate != null ? context.colors.textPrimary : context.colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
