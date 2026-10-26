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
import '../../../shared/widgets/ui.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../auth/provider/auth_provider.dart';
import '../../maintenance/data/maintenance_service.dart';
import '../../disposal/data/disposal_service.dart';
import '../../../shared/utils/idempotency.dart';
import '../../../core/offline/asset_snapshot.dart';
import '../../../core/offline/outbox.dart';
import '../../outbox/sync_engine.dart';
import '../../../shared/widgets/ios_pickers.dart';

// image_picker has no live-camera implementation on Windows/Linux (only a
// file/gallery picker) - mirrors the same gate qr_scanner_screen.dart already
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
  int? _articleId;
  int? _officeId;
  int? _personnelId;   // accountable person
  int? _currentUserId; // who actually has the asset - may differ from accountable person
  String _condition = 'NEW';
  String _lifecycleStatus = 'REGISTERED';
  DateTime? _acquisitionDate;

  // Null when creating a new asset - used to detect a genuine condition
  // transition (matches the backend's own transition check in AssetService).
  late final String? _originalCondition;

  Timer? _categoryDebounce;
  CategoryModel? _suggestedCategory;

  bool _scanning = false;
  bool _wasScanned = false;

  bool get _isEdit => widget.asset != null;

  // A staff account can edit an asset of its own office, but can't move it to another
  // office - mirrors the web app's AddAssetModal staffMode. Only an administrator can
  // relocate an asset.
  bool get _staffMode => !(ref.read(authProvider).valueOrNull?.isAdmin ?? false);

  // 'maintenance' / 'disposal' when staff picked a status - or marked the asset
  // REPAIRABLE / UNSERVICEABLE - which has to be approved by an admin first.
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
    _articleId = a?.article?.id;
    _officeId = a?.office.id;
    _personnelId = a?.accountablePerson?.id;
    _currentUserId = a?.currentUser?.id;
    _condition = a?.condition ?? 'NEW';
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

  Future<void> _scanLabel(ImageSource source) async {
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
      if (mounted) setState(() => _wasScanned = true);
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
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
        // Best-effort convenience feature - stay silent on failure.
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
      _showError('Only assets marked REPAIRABLE or UNSERVICEABLE can be disposed. Set the condition first.');
      return;
    }
    setState(() => _loading = true);
    try {
      final offices = ref.read(officesProvider).valueOrNull ?? [];
      final officeName = offices.where((o) => o.id == _officeId).firstOrNull?.officeName ?? '';
      final data = {
        'propertyNumber': _propertyNumber.text.trim().isEmpty ? null : _propertyNumber.text.trim(),
        'parNumber': '${_parPrefix()}:${_parSerial.text.trim()}',
        'serialNumber': _serialNumber.text.trim().isEmpty ? null : _serialNumber.text.trim(),
        'description': _description.text.trim(),
        'categoryId': _categoryId,
        // 0 = none; the server keeps the current article only when the field is missing
        'articleId': _articleId ?? 0,
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
      final asset = widget.asset;
      final saved = await sendOrQueue<AssetModel>(
        ref,
        // an asset added offline only exists on this phone - its edits join that upload
        forceQueue: asset != null && asset.id < 0,
        send: () => asset != null
            ? service.update(asset.id, data)
            : service.create(data, idempotencyKey: _idempotencyKey),
        queue: () async => Outbox.instance.add(
          kind: asset != null ? 'asset.update' : 'asset.create',
          method: asset != null ? 'PUT' : 'POST',
          path: asset != null ? '/assets/${asset.id}' : '/assets',
          body: data,
          baseUpdatedAt: asset?.updatedAt,
          label: asset != null
              ? 'Edit asset ${asset.propertyNumber}'
              : 'New asset ${data['propertyNumber'] ?? data['description']}',
          preview: await _offlinePreview(data),
          idempotencyKey: asset == null ? _idempotencyKey : null,
        ),
      );
      ref.invalidate(assetsPagedProvider(ref.read(assetSearchProvider)));
      if (asset != null) ref.invalidate(assetDetailProvider(asset.id));
      if (saved == null) {
        if (mounted) {
          showSavedOffline(context);
          Navigator.pop(context, true);
        }
        return;
      }

      // The backend auto-creates a placeholder maintenance/disposal record the
      // moment an asset's condition transitions into REPAIRABLE/UNSERVICEABLE
      // (see AssetService.handleConditionLedger). Rather than sending the user
      // to a blank "Add" form - which would create a second, duplicate record -
      // fetch that auto-created record and open it directly for completion.
      final becameRepairable = _condition == 'REPAIRABLE' && _originalCondition != 'REPAIRABLE';
      final becameUnserviceable = _condition == 'UNSERVICEABLE' && _originalCondition != 'UNSERVICEABLE';

      // Staff's maintenance/disposal goes in as a request an admin approves (no editable
      // record yet), so only an admin is taken straight to the auto-created record.
      if (saved.pendingRequest != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${saved.pendingRequest == 'MAINTENANCE' ? 'Maintenance' : 'Disposal'} request sent: '
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

      // Completes the scan → review → QR flow - manual entry keeps today's behavior.
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

  // How the asset will look once uploaded, so the offline lists and detail show the change.
  Future<Map<String, dynamic>> _offlinePreview(Map<String, dynamic> data) async {
    final asset = widget.asset;
    final base = asset != null && asset.id > 0 ? await AssetSnapshot.instance.rawById(asset.id) : null;
    final category = (ref.read(categoriesProvider).valueOrNull ?? []).where((c) => c.id == _categoryId).firstOrNull;
    final article = (ref.read(articlesProvider).valueOrNull ?? []).where((a) => a.id == _articleId).firstOrNull;
    final office = (ref.read(officesProvider).valueOrNull ?? []).where((o) => o.id == _officeId).firstOrNull;
    final people = ref.read(personnelProvider).valueOrNull ?? [];
    Map<String, dynamic>? person(int? id) {
      final p = people.where((p) => p.id == id).firstOrNull;
      return p == null ? null : {'id': p.id, 'fullName': p.fullName, 'position': p.position};
    }

    // A staff status change is only a request until an admin approves it - the asset keeps its status.
    final request = _staffRequest != null;
    return {
      ...?base,
      ...data,
      'id': asset?.id ?? 0,
      'propertyNumber': data['propertyNumber'] ?? asset?.propertyNumber ?? 'New asset',
      'category': {'id': _categoryId ?? 0, 'categoryName': category?.categoryName ?? asset?.category.categoryName ?? 'N/A'},
      'article': article?.toJson() ?? (_articleId != null && _articleId == asset?.article?.id ? asset!.article!.toJson() : null),
      'office': {'id': _officeId ?? 0, 'officeName': office?.officeName ?? asset?.office.officeName ?? 'N/A'},
      'accountablePerson': person(_personnelId),
      'currentUser': person(_currentUserId),
      if (request) 'condition': asset!.condition,
      if (request) 'lifecycleStatus': asset!.lifecycleStatus,
      'createdAt': base?['createdAt'] ?? asset?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      'updatedAt': base?['updatedAt'] ?? asset?.updatedAt ?? '',
    };
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
    // optional for the form: without the list (e.g. offline before it was ever loaded) the
    // asset keeps its current article
    final articles = ref.watch(articlesProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Asset' : 'New Asset')),
      // main button stays in reach at the bottom, however long the form
      bottomNavigationBar: FormActionBar(child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save Changes' : 'Create Asset'),
            ),
          )),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (categories) => officesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (offices) => personnelAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (personnel) {
              // Accountable Person lists only the chosen location's people (the person is
              // custodially tied to that office), and nobody until a location is picked.
              // Current User is who actually has the device right now, which can be anyone
              // active - including someone from another office, or the admin - so it's
              // never office-filtered.
              final personnelForOffice = _officeId == null
                  ? <PersonnelModel>[]
                  : personnel.where((p) => p.inOffice(_officeId)).toList();

              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  children: [
                    if (!_isEdit) ...[
                      _autofillPanel(context),
                      const SizedBox(height: 20),
                    ],
                    const SectionLabel('Identification'),
                    _field(_serialNumber, 'Serial Number (optional)'),
                    _field(_description, 'Description', required: true),
                    _dropdown<CategoryModel>(
                      label: 'Category',
                      value: categories.where((c) => c.id == _categoryId).firstOrNull,
                      items: categories,
                      itemLabel: (c) => c.categoryName,
                      onChanged: (c) => setState(() {
                        // an article belongs to one category
                        if (c?.id != _categoryId) _articleId = null;
                        _categoryId = c?.id;
                        _suggestedCategory = null;
                      }),
                    ),
                    if (_categoryId != null && articles != null) _articlePicker(articles),
                    AnimatedSize(
                      duration: AppTheme.motionFast,
                      curve: AppTheme.motionCurve,
                      alignment: Alignment.topCenter,
                      child: _suggestedCategory != null ? _categorySuggestionChip() : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 10),
                    const SectionLabel('Quantity and value'),
                    _fixedField('Qty (Property Card)', '1', helperText: 'Always 1. Each asset is its own Property Number.'),
                    _fixedField('Qty (Physical Count)', '1', helperText: 'Always 1.'),
                    _datePicker(),
                    _field(_unitValue, 'Unit Value (₱)', keyboardType: TextInputType.number, required: true),
                    _field(_shortageOverageQty, 'Shortage/Overage Qty (optional)', keyboardType: TextInputType.number),
                    _field(_shortageOverageValue, 'Shortage/Overage Value (₱, optional)', keyboardType: TextInputType.number),
                    const SizedBox(height: 10),
                    const SectionLabel('Property records'),
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
                    const SizedBox(height: 10),
                    const SectionLabel('Location and people'),
                    if (_staffMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Location',
                              helperText: 'Automatically set to your assigned office. Only an administrator can move an asset.',
                              helperMaxLines: 2),
                          child: Text(
                            offices.where((o) => o.id == _officeId).firstOrNull?.officeName ?? 'N/A',
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
                        onChanged: (o) => setState(() {
                          _officeId = o?.id;
                          // the accountable person is tied to their office - drop one from another
                          if (!personnel.any((p) => p.id == _personnelId && p.inOffice(_officeId))) _personnelId = null;
                        }),
                      ),
                    if (_staffMode)
                      // the accountable person decides who can see the asset, so staff can't change it
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Accountable Person', helperText: "You are this asset's accountable person."),
                          child: Text(
                            widget.asset?.accountablePerson?.fullName ?? 'N/A',
                            style: TextStyle(color: context.colors.textPrimary),
                          ),
                        ),
                      )
                    else
                      _dropdown<PersonnelModel>(
                        // rebuilt per office so a person dropped by an office change clears here too
                        key: ValueKey('accountable-$_officeId'),
                        label: 'Accountable Person',
                        value: personnelForOffice.where((p) => p.id == _personnelId).firstOrNull,
                        items: personnelForOffice,
                        itemLabel: (p) => p.position != null ? '${p.fullName}: ${p.position}' : p.fullName,
                        onChanged: (p) => setState(() => _personnelId = p?.id),
                        enabled: _officeId != null,
                        hint: _officeId == null ? 'Select a location first' : null,
                      ),
                    if (!_staffMode && _officeId != null && personnelForOffice.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          'No personnel are assigned to this office yet. Assign one from the web app\'s Personnel page.',
                          style: TextStyle(fontSize: 14, color: context.colors.textTertiary),
                        ),
                      ),
                    _dropdown<PersonnelModel>(
                      label: 'Current User (optional, can be anyone, from any office)',
                      value: personnel.where((p) => p.id == _currentUserId).firstOrNull,
                      items: personnel,
                      itemLabel: (p) => p.position != null ? '${p.fullName}: ${p.position}' : p.fullName,
                      onChanged: (p) => setState(() => _currentUserId = p?.id),
                      required: false,
                    ),
                    const SizedBox(height: 10),
                    const SectionLabel('Status'),
                    _enumDropdown('Condition', _condition,
                      ['NEW', 'SERVICEABLE', 'REPAIRABLE', 'UNSERVICEABLE'],
                      (v) => setState(() => _condition = v!)),
                    if (_staffRequest != null && _lifecycleStatus == widget.asset?.lifecycleStatus)
                      _requestNotice(),
                    // Editing only - a new asset starts as Registered. Staff can't transfer
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
                    const SizedBox(height: 10),
                    const SectionLabel('Notes'),
                    _field(_specifications, 'Technical Specifications', maxLines: 6),
                    _field(_remarks, 'Remarks', maxLines: 3),
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

  // Same as the web Add Asset form (commit deb07aa): a labelled green panel so staff notice
  // they can fill the form from a photo instead of typing - explanation first, then solid
  // buttons, then a confirmation once fields have been filled in.
  Widget _autofillPanel(BuildContext context) {
    final c = context.colors;
    final light = context.isLight;
    final accent = context.brandAccent;
    final busy = _scanning;
    Widget spinner(Color color) =>
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: light ? AppTheme.brandTint : AppTheme.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.6), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: AppTheme.brandButton, shape: BoxShape.circle),
                child: const Icon(Icons.document_scanner_rounded, size: 21, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-fill from a photo. No typing needed',
                        style: TextStyle(color: c.textPrimary, fontSize: 16, height: 1.3, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Take a photo of the device label/sticker or the PAR document. The system reads the '
                      'description, serial number, and specifications and fills them in for you to review.',
                      style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_cameraCaptureSupported) ...[
            ElevatedButton.icon(
              onPressed: busy ? null : () => _scanLabel(ImageSource.camera),
              icon: busy ? spinner(Colors.white) : const Icon(Icons.photo_camera_rounded),
              label: Text(busy ? 'Reading photo…' : 'Take Photo'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: busy ? null : () => _scanLabel(ImageSource.gallery),
            icon: busy && !_cameraCaptureSupported ? spinner(accent) : const Icon(Icons.upload_rounded),
            label: Text(busy && !_cameraCaptureSupported ? 'Reading photo…' : 'Upload Image'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: accent,
              backgroundColor: c.surface,
              side: const BorderSide(color: AppTheme.brandButton, width: 2),
            ),
          ),
          const SizedBox(height: 12),
          if (_wasScanned && !busy)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_rounded, size: 20, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Fields filled in from your photo. Please check them below before saving.',
                      style: TextStyle(color: accent, fontSize: 14, height: 1.4, fontWeight: FontWeight.w600)),
                ),
              ],
            )
          else
            Text('Or skip this and type the details below.', style: TextStyle(color: c.textTertiary, fontSize: 14)),
        ],
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
              Icon(Icons.auto_awesome_rounded, size: 14, color: context.brandAccent),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Suggested: ${suggestion.categoryName} · tap to apply',
                    style: TextStyle(color: context.brandAccent, fontSize: 14, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Article: the kind of item within the chosen category, as on the physical count report.
  // Required once the category has articles.
  Widget _articlePicker(List<ArticleModel> all) {
    final options = all.where((a) => a.categoryId == _categoryId).toList()
      ..sort((a, b) => a.articleName.toLowerCase().compareTo(b.articleName.toLowerCase()));
    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          'This category has no articles yet. An administrator can add them (e.g. Laptop, Printer) on the web Categories page.',
          style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
        ),
      );
    }
    return _dropdown<ArticleModel>(
      // rebuilt per category so the choice clears when the category changes
      key: ValueKey('article-$_categoryId'),
      label: 'Article',
      value: options.where((a) => a.id == _articleId).firstOrNull,
      items: options,
      itemLabel: (a) => a.articleName,
      onChanged: (a) => setState(() => _articleId = a?.id),
    );
  }

  Widget _dropdown<T>({
    Key? key,
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
    bool required = true,
    bool enabled = true,
    String? hint,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 14),
      child: IosSelectFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        // drawn by the picker itself - a decoration hintText would be painted a second time
        hint: hint == null ? null : Text(hint, style: TextStyle(fontSize: 16, color: context.colors.textTertiary)),
        dropdownColor: context.colors.surface,
        items: items.map((e) => DropdownMenuItem(
          value: e,
          child: Text(itemLabel(e), overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: enabled ? onChanged : null,
        validator: required ? (v) => v == null ? 'Required' : null : null,
      ),
    );
  }

  Widget _requestNotice() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          'Saving sends a $_staffRequest request to an administrator. The asset keeps its '
          "current condition and status until it's approved.",
          style: const TextStyle(color: AppTheme.statusMaintenance, fontSize: 14),
        ),
      );

  Widget _enumDropdown(String label, String value, List<String> options, void Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: IosSelectFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        dropdownColor: context.colors.surface,
        items: options.map((e) => DropdownMenuItem(value: e, child: Text(titleCaseCode(e)))).toList(),
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
