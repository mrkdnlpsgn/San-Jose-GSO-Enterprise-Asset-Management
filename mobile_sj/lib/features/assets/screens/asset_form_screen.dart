import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../model/asset_model.dart';
import '../data/asset_service.dart';
import '../provider/asset_provider.dart';
import '../widgets/asset_qr_sheet.dart';
import '../../../shared/data/reference_service.dart';
import '../../../shared/provider/reference_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/main_shell.dart';
import '../../maintenance/data/maintenance_service.dart';
import '../../disposal/data/disposal_service.dart';
import '../../../shared/utils/idempotency.dart';

// image_picker has no live-camera implementation on Windows/Linux (only a
// file/gallery picker) — mirrors the same gate qr_scanner_screen.dart already
// uses for mobile_scanner's camera path.
bool get _cameraCaptureSupported =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class AssetFormScreen extends ConsumerStatefulWidget {
  final AssetModel? asset; // null = create, non-null = edit
  const AssetFormScreen({super.key, this.asset});

  @override
  ConsumerState<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends ConsumerState<AssetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final String _idempotencyKey = newIdempotencyKey();

  // One entry per unit (= Qty). Resized whenever the quantity changes.
  final List<_UnitFields> _units = [];
  late final TextEditingController _serialNumber;
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _unitValue;
  late final TextEditingController _physicalCount;
  late final TextEditingController _remarks;
  late final TextEditingController _specifications;

  int? _categoryId;
  int? _officeId;
  int? _personnelId;   // accountable person
  int? _currentUserId; // who actually has the asset — may differ from accountable person
  String _condition = 'SERVICEABLE';
  String _lifecycleStatus = 'REGISTERED';
  DateTime? _acquisitionDate;

  // Null when creating a new asset — used to detect a genuine condition
  // transition (matches the backend's own transition check in AssetService).
  late final String? _originalCondition;

  Timer? _categoryDebounce;
  CategoryModel? _suggestedCategory;

  bool _scanning = false;
  bool _wasScanned = false;

  bool get _isEdit => widget.asset != null;

  // A device inside a group is always exactly one unit: Qty (Property Card) and Qty (Physical
  // Count) are fixed at 1 and can't be changed.
  bool get _lockedQty => widget.asset?.groupId != null;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    // Each device has its own Property Number and PAR Number. Only the serial half of
    // "YYYY-MM:SERIAL" is typed; the year-month prefix comes from the acquisition date.
    if (a != null) {
      final par = a.parNumber;
      _units.add(_UnitFields(
        propertyNumber: a.propertyNumber,
        parSerial: par != null && par.contains(':') ? par.substring(par.indexOf(':') + 1) : '',
      ));
    }
    _serialNumber = TextEditingController(text: a?.serialNumber ?? '');
    _description = TextEditingController(text: a?.description ?? '');
    _quantity = TextEditingController(text: a?.quantity.toString() ?? '1');
    _unitValue = TextEditingController(text: a?.unitValue.toStringAsFixed(2) ?? '');
    _physicalCount = TextEditingController(text: a?.physicalCount?.toString() ?? '1');
    _remarks = TextEditingController(text: a?.remarks ?? '');
    _specifications = TextEditingController(text: a?.specifications ?? '');
    _categoryId = a?.category.id;
    _officeId = a?.office.id;
    _personnelId = a?.accountablePerson?.id;
    _currentUserId = a?.currentUser?.id;
    _condition = a?.condition ?? 'SERVICEABLE';
    _originalCondition = a?.condition;
    _lifecycleStatus = a?.lifecycleStatus ?? 'REGISTERED';
    if (a?.acquisitionDate != null) {
      _acquisitionDate = DateTime.tryParse(a!.acquisitionDate);
    }
    if (a?.groupId != null) {
      _quantity.text = '1';
      _physicalCount.text = '1';
    }
    _resizeUnits(a?.quantity ?? 1); // pads legacy assets that have fewer unit entries than their quantity
    if (_units.length > 1) _seedUnitsFromShared(setCondition: true);
    _description.addListener(_onDescriptionChanged);
  }

  @override
  void dispose() {
    _categoryDebounce?.cancel();
    for (final u in _units) {
      u.dispose();
    }
    for (final c in [_serialNumber, _description, _quantity, _unitValue,
        _physicalCount, _remarks, _specifications]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanLabel() async {
    final source = _cameraCaptureSupported ? await _pickImageSource() : ImageSource.gallery;
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() => _scanning = true);
    try {
      final result = await AssetService().scanLabel(picked.path);
      if (result.description != null && result.description!.isNotEmpty) {
        _description.text = result.description!;
      }
      if (result.serialNumber != null && result.serialNumber!.isNotEmpty) {
        _serialNumber.text = result.serialNumber!;
      }
      if (result.specifications != null && result.specifications!.isNotEmpty) {
        _specifications.text = result.specifications!;
      }
      _wasScanned = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scanned — review the details below.'), behavior: SnackBarBehavior.floating),
        );
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<ImageSource?> _pickImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _onDescriptionChanged() {
    _categoryDebounce?.cancel();
    final text = _description.text.trim();
    if (text.length < 3) {
      if (_suggestedCategory != null) setState(() => _suggestedCategory = null);
      return;
    }
    _categoryDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final suggestion = await ReferenceService().suggestCategory(text);
        if (mounted && suggestion.id != _categoryId) {
          setState(() => _suggestedCategory = suggestion);
        }
      } catch (_) {
        // Best-effort convenience feature — stay silent on failure.
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final multi = _units.length > 1;
    if (!multi && _acquisitionDate == null) {
      _showError('Please select an acquisition date.');
      return;
    }
    if (multi && _acquisitionDate == null && _units.any((u) => u.acquisitionDate == null)) {
      _showError('Set an acquisition date for every device — or one shared date above for all of them.');
      return;
    }
    setState(() => _loading = true);
    try {
      final offices = ref.read(officesProvider).value ?? [];
      // With several devices the shared Location / people fields are hidden (each device has its
      // own); the request still carries shared values, so they mirror device 1.
      final sharedOfficeId = multi ? _units.first.officeId : _officeId;
      final sharedPersonnelId = multi ? _units.first.personnelId : _personnelId;
      final sharedCurrentUserId = multi ? _units.first.currentUserId : _currentUserId;
      final officeName = offices.where((o) => o.id == sharedOfficeId).firstOrNull?.officeName ?? '';
      final data = {
        // One entry per device — each becomes its own asset. Anything left blank is
        // inherited from the shared details on this form.
        // One entry per device — each becomes its own asset. With several devices each carries
        // its own value/condition/specs (and date, when no shared date is set); a single asset
        // uses the shared fields, so its entry only has the numbers.
        'units': [
          for (final u in _units)
            {
              'propertyNumber': u.propertyNumber.text.trim().isEmpty ? null : u.propertyNumber.text.trim(),
              'parNumber': '${_parPrefix(u.acquisitionDate)}:${u.parSerial.text.trim()}',
              'serialNumber': !multi || u.serialNumber.text.trim().isEmpty ? null : u.serialNumber.text.trim(),
              'unitValue': multi ? double.tryParse(u.unitValue.text.trim()) : null,
              'acquisitionDate': multi && _acquisitionDate == null
                  ? u.acquisitionDate?.toIso8601String().substring(0, 10)
                  : null,
              'officeId': multi ? u.officeId : null,
              'personnelId': multi ? u.personnelId : null,
              'currentUserId': multi ? u.currentUserId : null,
              'condition': multi ? u.condition : null,
              'specifications': !multi || u.specifications.text.trim().isEmpty ? null : u.specifications.text.trim(),
              'remarks': !multi || u.remarks.text.trim().isEmpty ? null : u.remarks.text.trim(),
            },
        ],
        'serialNumber': _serialNumber.text.trim().isEmpty ? null : _serialNumber.text.trim(),
        'description': _description.text.trim(),
        'categoryId': _categoryId,
        'quantity': int.parse(_quantity.text.trim()),
        'acquisitionDate': _acquisitionDate?.toIso8601String().substring(0, 10),
        // With several devices the shared value is just the sum of the devices' own.
        'unitValue': multi
            ? _units.fold<double>(0, (n, u) => n + (double.tryParse(u.unitValue.text.trim()) ?? 0))
            : double.parse(_unitValue.text.trim()),
        'officeId': sharedOfficeId,
        'personnelId': sharedPersonnelId,
        'currentUserId': sharedCurrentUserId,
        'physicalCount': _physicalCount.text.trim().isEmpty ? null : int.parse(_physicalCount.text.trim()),
        'location': officeName,
        'condition': multi ? 'SERVICEABLE' : _condition,
        'lifecycleStatus': _lifecycleStatus,
        'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
        'specifications': multi || _specifications.text.trim().isEmpty ? null : _specifications.text.trim(),
      };
      final service = AssetService();
      final AssetModel saved;
      if (_isEdit) {
        saved = await service.update(widget.asset!.id, data);
      } else {
        saved = await service.create(data, idempotencyKey: _idempotencyKey);
      }
      ref.invalidate(assetsPagedProvider(ref.read(assetSearchProvider)));

      // The backend auto-creates a placeholder maintenance/disposal record the
      // moment an asset's condition transitions into REPAIRABLE/UNSERVICEABLE
      // (see AssetService.handleConditionLedger). Rather than sending the user
      // to a blank "Add" form — which would create a second, duplicate record —
      // fetch that auto-created record and open it directly for completion.
      final becameRepairable = _condition == 'REPAIRABLE' && _originalCondition != 'REPAIRABLE';
      final becameUnserviceable = _condition == 'UNSERVICEABLE' && _originalCondition != 'UNSERVICEABLE';

      if (becameRepairable && mounted) {
        final records = await MaintenanceService().getByAsset(saved.id);
        if (records.isNotEmpty && mounted) {
          await context.push('/maintenance/${records.first.id}/edit', extra: records.first);
        }
      } else if (becameUnserviceable && mounted) {
        final records = await DisposalService().getByAsset(saved.id);
        if (records.isNotEmpty && mounted) {
          await context.push('/disposal/${records.first.id}/edit', extra: records.first);
        }
      }

      // Completes the scan → review → QR flow — manual entry keeps today's behavior.
      if (!_isEdit && _wasScanned && mounted) {
        await showAssetQrSheet(context, saved);
      }

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
    final categoriesAsync = ref.watch(categoriesProvider);
    final officesAsync = ref.watch(officesProvider);
    final personnelAsync = ref.watch(personnelProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Asset' : 'New Asset')),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.brand)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (categories) => officesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.brand)),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (offices) => personnelAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.brand)),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (personnel) {
              // Once an office is selected, narrow both the Accountable Person and
              // Current User dropdowns to personnel assigned to that office — before
              // that, show everyone so picking an office isn't forced first.
              final personnelForOffice = _officeId == null
                  ? personnel
                  : personnel.where((p) => p.officeId == _officeId).toList();

              return Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + context.mainShellBottomInset),
                  children: [
                    if (!_isEdit) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: OutlinedButton.icon(
                          onPressed: _scanning ? null : _scanLabel,
                          icon: _scanning
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.document_scanner_outlined),
                          label: Text(_scanning ? 'Scanning…' : 'Scan Label/Document — auto-fill from a photo'),
                        ),
                      ),
                    ],
                    _field(_serialNumber,
                        _units.length > 1 ? 'Serial Number (optional — default for every unit)' : 'Serial Number (optional)'),
                    _field(_description, 'Description', required: true),
                    _dropdown<CategoryModel>(
                      label: 'Category',
                      value: categories.where((c) => c.id == _categoryId).firstOrNull,
                      items: categories,
                      itemLabel: (c) => c.categoryName,
                      onChanged: (c) => setState(() {
                        _categoryId = c?.id;
                        _suggestedCategory = null;
                      }),
                    ),
                    AnimatedSize(
                      duration: AppTheme.motionFast,
                      curve: AppTheme.motionCurve,
                      alignment: Alignment.topCenter,
                      child: _suggestedCategory != null ? _categorySuggestionChip() : const SizedBox.shrink(),
                    ),
                    _field(_quantity, 'Qty (Property Card)',
                        keyboardType: TextInputType.number,
                        required: true,
                        enabled: !_lockedQty,
                        helperText: _lockedQty ? 'Fixed at 1 for devices in a group' : null,
                        onChanged: _onQuantityChanged,
                        extraValidator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          return (n == null || n < 1 || n > _maxUnits) ? 'Enter a whole number from 1 to $_maxUnits' : null;
                        }),
                    _datePicker(),
                    _unitsSection(offices, personnel),
                    if (_units.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Total Unit Value (₱)', helperText: "Sum of every device's unit value below."),
                          child: Text(
                              _units.fold<double>(0, (n, u) => n + (double.tryParse(u.unitValue.text.trim()) ?? 0))
                                  .toStringAsFixed(2),
                              style: TextStyle(color: context.colors.textPrimary)),
                        ),
                      )
                    else
                      _field(_unitValue, 'Unit Value (₱)', keyboardType: TextInputType.number, required: true),
                    // With several devices, location and people are set per device (above).
                    if (_units.length == 1) ...[
                    _dropdown<OfficeModel>(
                      label: 'Location',
                      value: offices.where((o) => o.id == _officeId).firstOrNull,
                      items: offices,
                      itemLabel: (o) => o.officeName,
                      onChanged: (o) => setState(() => _officeId = o?.id),
                    ),
                    _dropdown<PersonnelModel>(
                      label: 'Accountable Person',
                      value: personnelForOffice.where((p) => p.id == _personnelId).firstOrNull,
                      items: personnelForOffice,
                      itemLabel: (p) => p.position != null ? '${p.fullName} — ${p.position}' : p.fullName,
                      onChanged: (p) => setState(() => _personnelId = p?.id),
                    ),
                    if (_officeId != null && personnelForOffice.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          'No personnel are assigned to this office yet — assign one from the web app\'s Personnel page.',
                          style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
                        ),
                      ),
                    _dropdown<PersonnelModel>(
                      label: 'Current User (optional)',
                      value: personnelForOffice.where((p) => p.id == _currentUserId).firstOrNull,
                      items: personnelForOffice,
                      itemLabel: (p) => p.position != null ? '${p.fullName} — ${p.position}' : p.fullName,
                      onChanged: (p) => setState(() => _currentUserId = p?.id),
                      required: false,
                    ),
                    ],
                    _field(_physicalCount, 'Qty (Physical Count)',
                        keyboardType: TextInputType.number,
                        required: true,
                        enabled: !_lockedQty,
                        helperText: _lockedQty ? 'Fixed at 1 for devices in a group' : null,
                        extraValidator: (v) =>
                            v?.trim() != _quantity.text.trim() ? 'Must equal Qty (Property Card)' : null),
                    // With several devices, condition and specs are set per device (above).
                    if (_units.length == 1) ...[
                      _enumDropdown('Condition', _condition,
                        ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE'],
                        (v) => setState(() => _condition = v!)),
                      _field(_specifications, 'Technical Specifications', maxLines: 6),
                    ],
                    _field(_remarks, 'Remarks', maxLines: 3),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_isEdit ? 'Save Changes' : 'Create Asset'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboardType,
      bool required = false,
      int maxLines = 1,
      ValueChanged<String>? onChanged,
      String? Function(String?)? extraValidator,
      bool enabled = true,
      String? helperText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        enabled: enabled,
        decoration: InputDecoration(labelText: label, helperText: helperText),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Required';
          return extraValidator?.call(v);
        },
      ),
    );
  }

  Widget _categorySuggestionChip() {
    final suggestion = _suggestedCategory!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          _categoryId = suggestion.id;
          _suggestedCategory = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.brand.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.brand),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Suggested: ${suggestion.categoryName} · tap to apply',
                    style: const TextStyle(color: AppTheme.brand, fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        dropdownColor: context.colors.surface,
        items: items.map((e) => DropdownMenuItem(
          value: e,
          child: Text(itemLabel(e), overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: onChanged,
        validator: required ? (v) => v == null ? 'Required' : null : null,
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

  String _parPrefix([DateTime? override]) {
    final d = _acquisitionDate ?? override;
    if (d == null) return 'YYYY-MM';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  static const _maxUnits = 500;

  // Physical Count must equal Qty (Property Card) — it follows the quantity as
  // it's typed (still editable, still validated) and the unit list resizes to match.
  void _onQuantityChanged(String v) {
    final n = int.tryParse(v.trim());
    if (n == null || n < 1 || n > _maxUnits) return;
    setState(() {
      final wasMulti = _units.length > 1;
      _physicalCount.text = v.trim();
      _resizeUnits(n);
      if (n > 1) {
        // The shared Condition / Specifications / Unit Value fields are replaced by per-device
        // ones — carry over whatever was already entered so nothing is lost.
        _seedUnitsFromShared(setCondition: !wasMulti);
      } else {
        // Back to a single asset: the shared fields come back, seeded from device 1.
        final u0 = _units.first;
        if (u0.unitValue.text.trim().isNotEmpty) _unitValue.text = u0.unitValue.text.trim();
        if (u0.specifications.text.trim().isNotEmpty) _specifications.text = u0.specifications.text;
        _condition = u0.condition;
        _acquisitionDate ??= u0.acquisitionDate;
        _officeId = u0.officeId ?? _officeId;
        _personnelId = u0.personnelId ?? _personnelId;
        _currentUserId = u0.currentUserId ?? _currentUserId;
      }
    });
  }

  // The shared Condition / Specs / Unit Value / Location / people fields are replaced by per-device
  // ones once there are several devices — carry whatever was already entered over to them.
  void _seedUnitsFromShared({required bool setCondition}) {
    for (final u in _units) {
      if (u.unitValue.text.trim().isEmpty) u.unitValue.text = _unitValue.text.trim();
      if (u.specifications.text.trim().isEmpty) u.specifications.text = _specifications.text;
      u.officeId ??= _officeId;
      u.personnelId ??= _personnelId;
      u.currentUserId ??= _currentUserId;
      if (setCondition) u.condition = _condition;
    }
  }

  void _resizeUnits(int n) {
    while (_units.length < n) {
      _units.add(_UnitFields());
    }
    while (_units.length > n) {
      _units.removeLast().dispose();
    }
  }

  String? _validateParSerial(int index, String? v) {
    final s = v?.trim() ?? '';
    if ((_units[index].acquisitionDate ?? _acquisitionDate) == null) return 'Pick the Acquisition Date first';
    if (s.isEmpty) return 'Required';
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(s)) return 'Letters, numbers, and hyphens only';
    for (var i = 0; i < _units.length; i++) {
      if (i != index && _units[i].parSerial.text.trim().toUpperCase() == s.toUpperCase()) {
        return 'Already used by unit ${i + 1}';
      }
    }
    return null;
  }

  // Dropdown for a per-device field. `placeholder` shows while nothing is picked; `clearLabel`
  // (when set) adds an entry that resets the choice to nothing.
  Widget _optionalDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
    String? placeholder,
    String? clearLabel,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        hint: placeholder == null ? null : Text(placeholder),
        dropdownColor: context.colors.surface,
        items: [
          if (clearLabel != null) DropdownMenuItem<T?>(value: null, child: Text(clearLabel)),
          ...items.map((e) => DropdownMenuItem<T?>(
                value: e,
                child: Text(itemLabel(e), overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: onChanged,
        validator: required ? (v) => v == null ? 'Required' : null : null,
      ),
    );
  }

  Widget _unitDatePicker(_UnitFields u) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: u.acquisitionDate ?? DateTime.now(),
            firstDate: DateTime(1990),
            lastDate: DateTime.now(),
          );
          if (picked != null) setState(() => u.acquisitionDate = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Acquisition Date'),
          child: Text(
            u.acquisitionDate != null ? u.acquisitionDate!.toIso8601String().substring(0, 10) : 'Tap to select',
            style: TextStyle(
                color: u.acquisitionDate != null ? context.colors.textPrimary : context.colors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _unitFieldsCard(int i, List<OfficeModel> offices, List<PersonnelModel> personnel) {
    final u = _units[i];
    final multi = _units.length > 1;
    final people = u.officeId == null ? personnel : personnel.where((p) => p.officeId == u.officeId).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: multi ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: multi
          ? BoxDecoration(
              border: Border.all(color: context.colors.textTertiary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (multi)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                  'Device ${i + 1} of ${_units.length}${_isEdit ? (i == 0 ? ' — this asset' : ' — new') : ''}',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: u.propertyNumber,
              decoration: const InputDecoration(
                  labelText: 'Property Number (optional)', hintText: 'Leave blank to auto-generate'),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: multi ? 12 : 0),
            child: TextFormField(
              controller: u.parSerial,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'PAR Number',
                prefixText: '${_parPrefix(u.acquisitionDate)}:',
                hintText: 'e.g. H78JD80',
              ),
              validator: (v) => _validateParSerial(i, v),
            ),
          ),
          if (multi) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: u.unitValue,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}), // keeps the shared total up to date
                decoration: const InputDecoration(labelText: 'Unit Value (₱)'),
                validator: (v) => (double.tryParse(v?.trim() ?? '') == null) ? 'Required' : null,
              ),
            ),
            _optionalDropdown<String>(
              label: 'Condition',
              value: u.condition,
              items: const ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE'],
              itemLabel: (c) => c,
              onChanged: (c) => setState(() => u.condition = c ?? 'SERVICEABLE'),
            ),
            _optionalDropdown<OfficeModel>(
              label: 'Location',
              placeholder: 'Select location',
              required: true,
              value: offices.where((o) => o.id == u.officeId).firstOrNull,
              items: offices,
              itemLabel: (o) => o.officeName,
              onChanged: (o) => setState(() {
                u.officeId = o?.id;
                // the person lists follow the device's location
                if (u.personnelId != null && !personnel.any((p) => p.id == u.personnelId && p.officeId == o?.id)) {
                  u.personnelId = null;
                }
                if (u.currentUserId != null && !personnel.any((p) => p.id == u.currentUserId && p.officeId == o?.id)) {
                  u.currentUserId = null;
                }
              }),
            ),
            _optionalDropdown<PersonnelModel>(
              label: 'Accountable Person',
              placeholder: 'Select accountable person',
              required: true,
              value: people.where((p) => p.id == u.personnelId).firstOrNull,
              items: people,
              itemLabel: (p) => p.position != null ? '${p.fullName} — ${p.position}' : p.fullName,
              onChanged: (p) => setState(() => u.personnelId = p?.id),
            ),
            _optionalDropdown<PersonnelModel>(
              label: 'Current User (optional)',
              placeholder: 'Select current user',
              clearLabel: 'None',
              value: people.where((p) => p.id == u.currentUserId).firstOrNull,
              items: people,
              itemLabel: (p) => p.position != null ? '${p.fullName} — ${p.position}' : p.fullName,
              onChanged: (p) => setState(() => u.currentUserId = p?.id),
            ),
            if (_acquisitionDate == null) _unitDatePicker(u),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextFormField(
                controller: u.specifications,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Technical Specifications (optional)'),
              ),
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4),
                title: const Text('More details',
                    style: TextStyle(color: AppTheme.brand, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('Serial number, remarks — blank = same as the form',
                    style: TextStyle(color: context.colors.textTertiary, fontSize: 11.5)),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: u.serialNumber,
                      decoration: InputDecoration(
                          labelText: 'Serial Number',
                          hintText: _serialNumber.text.trim().isEmpty ? null : 'Same as above'),
                    ),
                  ),
                  TextFormField(
                    controller: u.remarks,
                    decoration: const InputDecoration(labelText: 'Remarks', hintText: 'Same as below'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unitsSection(List<OfficeModel> offices, List<PersonnelModel> personnel) {
    final multi = _units.length > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(multi ? 'Devices (${_units.length})' : 'Property & PAR Number',
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            multi
                ? 'Each device is saved as its own asset and shown grouped in the list. Give every device its own '
                    'Property Number and PAR Number, location, accountable person, value, condition and specs; anything under '
                    '"More details" left blank is copied from this form.'
                    '${_isEdit ? ' Device 1 is the asset you are editing; the others are added as new assets in the same group.' : ''}'
                : 'Unique per asset. The PAR year-month follows the Acquisition Date; type the serial after it.',
            style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _units.length; i++) _unitFieldsCard(i, offices, personnel),
        ],
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
            initialDate: _acquisitionDate ?? DateTime.now(),
            firstDate: DateTime(1990),
            lastDate: DateTime.now(),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.brand),
              ),
              child: child!,
            ),
          );
          if (picked != null) setState(() => _acquisitionDate = picked);
        },
        onLongPress: _units.length > 1 ? () => setState(() => _acquisitionDate = null) : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Acquisition Date',
            helperText: _units.length > 1
                ? 'Applies to every device. Leave empty to give each device its own date.'
                : null,
            helperMaxLines: 2,
          ),
          child: Text(
            _acquisitionDate != null
                ? _acquisitionDate!.toIso8601String().substring(0, 10)
                : (_units.length > 1 ? 'Not set — each device has its own' : 'Tap to select'),
            style: TextStyle(color: _acquisitionDate != null ? context.colors.textPrimary : context.colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

// Inputs for one device — created/disposed as the quantity changes. Blank/null
// means "same as the shared details on the form".
class _UnitFields {
  final TextEditingController propertyNumber;
  final TextEditingController parSerial;
  final TextEditingController serialNumber = TextEditingController();
  final TextEditingController unitValue = TextEditingController();
  final TextEditingController specifications = TextEditingController();
  final TextEditingController remarks = TextEditingController();
  DateTime? acquisitionDate;
  int? officeId;
  int? personnelId;
  int? currentUserId;
  String condition = 'SERVICEABLE';

  _UnitFields({String propertyNumber = '', String parSerial = ''})
      : propertyNumber = TextEditingController(text: propertyNumber),
        parSerial = TextEditingController(text: parSerial);

  void dispose() {
    propertyNumber.dispose();
    parSerial.dispose();
    serialNumber.dispose();
    unitValue.dispose();
    specifications.dispose();
    remarks.dispose();
  }
}
