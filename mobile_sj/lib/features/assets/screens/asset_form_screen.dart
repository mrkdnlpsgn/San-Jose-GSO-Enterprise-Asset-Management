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
import '../../auth/provider/auth_provider.dart';
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

  late final TextEditingController _propertyNumber;
  late final TextEditingController _parSerial;
  late final TextEditingController _serialNumber;
  late final TextEditingController _description;
  late final TextEditingController _unitValue;
  late final TextEditingController _shortageOverageQty;
  late final TextEditingController _shortageOverageValue;
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

  // A staff account can edit an asset of its own office, but can't move it to another
  // office — mirrors the web app's AddAssetModal staffMode. Only an administrator can
  // relocate an asset.
  bool get _staffMode => !(ref.read(authProvider).value?.isAdmin ?? false);

  // 'maintenance' / 'disposal' when staff picked a status — or marked the asset
  // REPAIRABLE / UNSERVICEABLE — which has to be approved by an admin first.
  String? get _staffRequest {
    if (!_isEdit || !_staffMode) return null;
    final asset = widget.asset!;
    final byStatus = _lifecycleStatus == asset.lifecycleStatus ? null : switch (_lifecycleStatus) {
      'UNDER_MAINTENANCE' => 'maintenance',
      'DISPOSED' => 'disposal',
      _ => null,
    };
    if (byStatus != null) return byStatus;
    if (_condition == asset.condition) return null;
    return switch (_condition) {
      'REPAIRABLE' => 'maintenance',
      'UNSERVICEABLE' => 'disposal',
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    // Only the serial half of "YYYY-MM:SERIAL" is typed; the year-month prefix comes
    // from the acquisition date.
    final par = a?.parNumber;
    _propertyNumber = TextEditingController(text: a?.propertyNumber ?? '');
    _parSerial = TextEditingController(
        text: par != null && par.contains(':') ? par.substring(par.indexOf(':') + 1) : '');
    _serialNumber = TextEditingController(text: a?.serialNumber ?? '');
    _description = TextEditingController(text: a?.description ?? '');
    _unitValue = TextEditingController(text: a?.unitValue.toStringAsFixed(2) ?? '');
    _shortageOverageQty = TextEditingController(text: a?.shortageOverageQty.toString() ?? '0');
    _shortageOverageValue = TextEditingController(text: a?.shortageOverageValue.toStringAsFixed(2) ?? '0.00');
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
      _acquisitionDate = DateTime.tryParse(a!.acquisitionDate)?.toLocal();
    }
    _description.addListener(_onDescriptionChanged);
  }

  @override
  void dispose() {
    _categoryDebounce?.cancel();
    for (final c in [
      _propertyNumber, _parSerial, _serialNumber, _description, _unitValue,
      _shortageOverageQty, _shortageOverageValue, _remarks, _specifications,
    ]) {
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
    if (_acquisitionDate == null) {
      _showError('Please select an acquisition date.');
      return;
    }
    if (_staffRequest == 'disposal' && !const ['REPAIRABLE', 'UNSERVICEABLE'].contains(_condition)) {
      _showError('Only assets marked REPAIRABLE or UNSERVICEABLE can be disposed — set the condition first.');
      return;
    }
    setState(() => _loading = true);
    try {
      final offices = ref.read(officesProvider).value ?? [];
      final officeName = offices.where((o) => o.id == _officeId).firstOrNull?.officeName ?? '';
      final data = {
        'propertyNumber': _propertyNumber.text.trim().isEmpty ? null : _propertyNumber.text.trim(),
        'parNumber': '${_parPrefix()}:${_parSerial.text.trim()}',
        'serialNumber': _serialNumber.text.trim().isEmpty ? null : _serialNumber.text.trim(),
        'description': _description.text.trim(),
        'categoryId': _categoryId,
        'quantity': 1,
        'physicalCount': 1,
        'acquisitionDate': _acquisitionDate?.toIso8601String().substring(0, 10),
        'unitValue': double.parse(_unitValue.text.trim()),
        'officeId': _officeId,
        'personnelId': _personnelId,
        'currentUserId': _currentUserId,
        'shortageOverageQty': int.tryParse(_shortageOverageQty.text.trim()) ?? 0,
        'shortageOverageValue': double.tryParse(_shortageOverageValue.text.trim()) ?? 0,
        'location': officeName,
        'condition': _condition,
        'lifecycleStatus': _lifecycleStatus,
        'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
        'specifications': _specifications.text.trim().isEmpty ? null : _specifications.text.trim(),
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

      // Staff's maintenance/disposal goes in as a request an admin approves (no editable
      // record yet), so only an admin is taken straight to the auto-created record.
      if (saved.pendingRequest != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${saved.pendingRequest == 'MAINTENANCE' ? 'Maintenance' : 'Disposal'} request sent — '
              'an administrator needs to approve it.'),
          behavior: SnackBarBehavior.floating,
        ));
      } else if (_staffMode) {
        // nothing to open
      } else if (becameRepairable && mounted) {
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
              // Accountable Person narrows to the asset's office once one is picked (the
              // person is custodially tied to that office). Current User is who actually
              // has the device right now, which can be anyone active — including someone
              // from another office, or the admin — so it's never office-filtered.
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
                    _field(_serialNumber, 'Serial Number (optional)'),
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
                    _fixedField('Qty (Property Card)', '1', helperText: 'Always 1 — each asset is its own Property Number.'),
                    _fixedField('Qty (Physical Count)', '1', helperText: 'Always 1.'),
                    _datePicker(),
                    _field(_unitValue, 'Unit Value (₱)', keyboardType: TextInputType.number, required: true),
                    _field(_shortageOverageQty, 'Shortage/Overage Qty (optional)', keyboardType: TextInputType.number),
                    _field(_shortageOverageValue, 'Shortage/Overage Value (₱, optional)', keyboardType: TextInputType.number),
                    _field(_propertyNumber, 'Property Number (optional)'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: _parSerial,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'PAR Number',
                          prefixText: '${_parPrefix()}:',
                          hintText: 'e.g. H78JD80',
                        ),
                        validator: _validateParSerial,
                      ),
                    ),
                    if (_staffMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Location',
                              helperText: 'Automatically set to your assigned office — only an administrator can move an asset.',
                              helperMaxLines: 2),
                          child: Text(
                            offices.where((o) => o.id == _officeId).firstOrNull?.officeName ?? '—',
                            style: TextStyle(color: context.colors.textPrimary),
                          ),
                        ),
                      ),
                    ] else
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
                      label: 'Current User (optional — can be anyone, from any office)',
                      value: personnel.where((p) => p.id == _currentUserId).firstOrNull,
                      items: personnel,
                      itemLabel: (p) => p.position != null ? '${p.fullName} — ${p.position}' : p.fullName,
                      onChanged: (p) => setState(() => _currentUserId = p?.id),
                      required: false,
                    ),
                    _enumDropdown('Condition', _condition,
                      ['SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE'],
                      (v) => setState(() => _condition = v!)),
                    if (_staffRequest != null && _lifecycleStatus == widget.asset?.lifecycleStatus)
                      _requestNotice(),
                    // Editing only — a new asset starts as Registered. Staff can't transfer
                    // (an admin assigns), and Under Maintenance / Disposed become requests.
                    if (_isEdit) ...[
                      _enumDropdown('Lifecycle Status', _lifecycleStatus,
                        [
                          for (final s in const ['REGISTERED', 'ASSIGNED', 'TRANSFERRED', 'UNDER_MAINTENANCE', 'DISPOSED', 'ARCHIVED'])
                            if (!_staffMode || s != 'TRANSFERRED' || widget.asset!.lifecycleStatus == 'TRANSFERRED') s,
                        ],
                        (v) => setState(() => _lifecycleStatus = v!)),
                      if (_staffRequest != null && _lifecycleStatus != widget.asset!.lifecycleStatus)
                        _requestNotice(),
                    ],
                    _field(_specifications, 'Technical Specifications', maxLines: 6),
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

  Widget _fixedField(String label, String value, {String? helperText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, helperText: helperText),
        child: Text(value, style: TextStyle(color: context.colors.textSecondary)),
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

  Widget _requestNotice() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          'Saving sends a $_staffRequest request to an administrator — the asset keeps its '
          "current condition and status until it's approved.",
          style: const TextStyle(color: AppTheme.statusMaintenance, fontSize: 12.5),
        ),
      );

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

  String _parPrefix() {
    final d = _acquisitionDate;
    if (d == null) return 'YYYY-MM';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  String? _validateParSerial(String? v) {
    final s = v?.trim() ?? '';
    if (_acquisitionDate == null) return 'Pick the Acquisition Date first';
    if (s.isEmpty) return 'Required';
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(s)) return 'Letters, numbers, and hyphens only';
    return null;
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
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Acquisition Date'),
          child: Text(
            _acquisitionDate != null ? _acquisitionDate!.toIso8601String().substring(0, 10) : 'Tap to select',
            style: TextStyle(color: _acquisitionDate != null ? context.colors.textPrimary : context.colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
