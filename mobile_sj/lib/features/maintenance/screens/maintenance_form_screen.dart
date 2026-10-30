import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../model/maintenance_model.dart';
import '../data/maintenance_service.dart';
import '../provider/maintenance_provider.dart';
import '../../../features/assets/model/asset_model.dart';
import '../../../shared/widgets/asset_picker.dart';
import '../../../shared/widgets/ui.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/utils/idempotency.dart';
import '../../../shared/widgets/ios_pickers.dart';
import '../../../core/offline/outbox.dart';
import '../../outbox/sync_engine.dart';
import '../../evidence/evidence_service.dart';
import '../../evidence/evidence_sheet.dart';
import '../../reports/utils/formatters.dart';

// One parts line being edited. A part's photos are tied to its saved id, so a new part gets
// photos once the record is saved. An additional part (found needed during the repair) has
// only a post-maintenance photo.
class _PartRow {
  int? id;
  bool additional;
  final TextEditingController particular, unit, quantity, unitCost;

  _PartRow({this.id, this.additional = false, String particular = '', String unit = '', String quantity = '1', String unitCost = ''})
      : particular = TextEditingController(text: particular),
        unit = TextEditingController(text: unit),
        quantity = TextEditingController(text: quantity),
        unitCost = TextEditingController(text: unitCost);

  double get total => ((_num(quantity.text) * _num(unitCost.text)) * 100).round() / 100;

  void dispose() {
    for (final c in [particular, unit, quantity, unitCost]) {
      c.dispose();
    }
  }
}

class _LaborRow {
  int? id;
  final TextEditingController particular, cost;

  _LaborRow({this.id, String particular = '', String cost = ''})
      : particular = TextEditingController(text: particular),
        cost = TextEditingController(text: cost);

  void dispose() {
    particular.dispose();
    cost.dispose();
  }
}

double _num(String v) => double.tryParse(v.trim()) ?? 0;
String _str(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());
String _dateKey(DateTime d) => d.toIso8601String().substring(0, 10);
DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

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
  DateTime? _completedDate;
  final List<_PartRow> _parts = [];
  final List<_LaborRow> _labor = [];

  // the record as last saved: the form stays open after saving new parts so their photos can be added
  MaintenanceModel? _record;
  List<EvidencePhoto> _photos = [];

  bool get _isEdit => _record != null;
  bool get _hasLines => _parts.isNotEmpty || _labor.isNotEmpty;
  bool get _completing => _status == 'COMPLETED' && _record?.status != 'COMPLETED';
  String get _photoPath => '/maintenance/${_record!.id}/photos';
  double get _linesTotal =>
      _parts.fold<double>(0, (t, p) => t + p.total) + _labor.fold<double>(0, (t, l) => t + _num(l.cost.text));

  @override
  void initState() {
    super.initState();
    final m = widget.maintenance;
    _record = m;
    _findings = TextEditingController(text: m?.findings ?? '');
    _actionsTaken = TextEditingController(text: m?.actionsTaken ?? '');
    _assignedTo = TextEditingController(text: m?.assignedTo ?? '');
    _cost = TextEditingController(text: m?.cost?.toStringAsFixed(2) ?? '');
    _maintenanceType = m?.maintenanceType ?? 'PREVENTIVE';
    _status = m?.status ?? 'SCHEDULED';
    _selectedAsset = m?.asset ?? widget.preselectedAsset;
    if (m?.maintenanceDate != null) _maintenanceDate = DateTime.tryParse(m!.maintenanceDate)?.toLocal();
    if (m?.completedDate != null) _completedDate = DateTime.tryParse(m!.completedDate!);
    _setLines(m?.items ?? const []);
    _loadPhotos();
  }

  void _setLines(List<MaintenanceItemModel> items) {
    for (final r in _parts) {
      r.dispose();
    }
    for (final r in _labor) {
      r.dispose();
    }
    _parts
      ..clear()
      ..addAll(items.where((i) => i.isPart).map((i) => _PartRow(
            id: i.id,
            additional: i.additional,
            particular: i.particular,
            unit: i.unit ?? '',
            quantity: _str(i.quantity),
            unitCost: _str(i.unitCost),
          )));
    _labor
      ..clear()
      ..addAll(items.where((i) => !i.isPart).map((i) => _LaborRow(id: i.id, particular: i.particular, cost: _str(i.totalCost))));
  }

  // The record's photos, to show how many each part has; offline the counts stay at what's known.
  Future<void> _loadPhotos() async {
    if (_record == null || _record!.id < 0) return;
    try {
      final photos = await EvidenceService(_photoPath).list();
      if (mounted) setState(() => _photos = photos);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_findings, _actionsTaken, _assignedTo, _cost]) {
      c.dispose();
    }
    for (final r in _parts) {
      r.dispose();
    }
    for (final r in _labor) {
      r.dispose();
    }
    super.dispose();
  }

  // Photos of one part at one stage: uploaded, plus any waiting on the phone to upload.
  int _photoCount(_PartRow p, String stage) {
    if (p.id == null || _record == null) return 0;
    final saved = _photos.where((ph) => ph.itemId == p.id && ph.stage == stage).length;
    final waiting = ref.read(outboxProvider).photosFor(EvidenceService(_photoPath, itemId: p.id).uploadPath(stage)).length;
    return saved + waiting;
  }

  List<String> _missingPhotos() {
    final missing = <String>[];
    for (var i = 0; i < _parts.length; i++) {
      final p = _parts[i];
      final before = p.additional || _photoCount(p, 'BEFORE') > 0;
      final after = _photoCount(p, 'AFTER') > 0;
      if (before && after) continue;
      final name = p.particular.text.trim().isEmpty ? 'Part ${i + 1}' : p.particular.text.trim();
      missing.add('$name (${!before && !after ? 'pre- and post-maintenance' : !before ? 'pre-maintenance' : 'post-maintenance'})');
    }
    return missing;
  }

  Map<String, dynamic> _payload(String status) => {
        'assetId': _selectedAsset!.id,
        'maintenanceType': _maintenanceType,
        'findings': _findings.text.trim(),
        'actionsTaken': _actionsTaken.text.trim(),
        'assignedTo': _assignedTo.text.trim().isEmpty ? null : _assignedTo.text.trim(),
        'maintenanceDate': _dateKey(_maintenanceDate!),
        'completedDate': status == 'COMPLETED' && _completedDate != null ? _dateKey(_completedDate!) : null,
        'cost': _hasLines ? _linesTotal : (_cost.text.trim().isEmpty ? null : double.parse(_cost.text.trim())),
        'status': status,
        'items': [
          for (final p in _parts)
            {
              'id': p.id,
              'kind': 'PART',
              'particular': p.particular.text.trim(),
              'unit': p.unit.text.trim().isEmpty ? null : p.unit.text.trim(),
              'quantity': _num(p.quantity.text),
              'unitCost': _num(p.unitCost.text),
              'additional': p.additional,
            },
          for (final l in _labor) {'id': l.id, 'kind': 'LABOR', 'particular': l.particular.text.trim(), 'totalCost': _num(l.cost.text)},
        ],
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAsset == null) { _showError('Please select an asset.'); return; }
    if (_maintenanceDate == null) { _showError('Please select a maintenance date.'); return; }
    if (_status == 'COMPLETED') {
      if (_completedDate == null) { _showError('Enter the date the maintenance was completed.'); return; }
      if (_completedDate!.isBefore(DateTime(_maintenanceDate!.year, _maintenanceDate!.month, _maintenanceDate!.day))) {
        _showError("The completion date can't be before the maintenance date.");
        return;
      }
    }
    final badPart = _parts.indexWhere((p) => p.particular.text.trim().isEmpty || _num(p.quantity.text) <= 0 || p.unitCost.text.trim().isEmpty);
    if (badPart >= 0) { _showError('Part ${badPart + 1}: enter the particular, a quantity and the unit cost.'); return; }
    final badLabor = _labor.indexWhere((l) => l.particular.text.trim().isEmpty || l.cost.text.trim().isEmpty);
    if (badLabor >= 0) { _showError('Labor ${badLabor + 1}: enter the particular and the cost.'); return; }

    // New parts need saving before their photos can be added, so a repair being completed with
    // new parts is first saved as it was; the form stays open for the photos.
    final newParts = _parts.any((p) => p.id == null);
    final completeLater = _completing && newParts;
    if (_completing && !newParts) {
      final missing = _missingPhotos();
      if (missing.isNotEmpty) {
        _showError('Add the photos missing for these parts before marking the repair Completed: ${missing.join(', ')}.');
        return;
      }
    }
    final status = completeLater ? _record!.status : _status;

    setState(() => _loading = true);
    try {
      final data = _payload(status);
      final service = MaintenanceService();
      final record = _record;
      final asset = _selectedAsset!;
      final sent = await sendOrQueue<MaintenanceModel>(
        ref,
        send: () async => record != null
            ? await service.update(record.id, data)
            : await service.create(data, idempotencyKey: _idempotencyKey),
        queue: () => Outbox.instance.add(
          kind: record != null ? 'maintenance.update' : 'maintenance.create',
          method: record != null ? 'PUT' : 'POST',
          path: record != null ? '/maintenance/${record.id}' : '/maintenance',
          body: data,
          baseUpdatedAt: record?.updatedAt,
          label: '${record != null ? 'Edit' : 'New'} maintenance record · ${asset.propertyNumber}',
          idempotencyKey: record == null ? _idempotencyKey : null,
        ),
      );
      if (sent == null) {
        if (mounted) {
          showSavedOffline(context);
          Navigator.pop(context, true);
        }
        return;
      }
      ref.invalidate(maintenancePagedProvider(ref.read(maintenanceSearchProvider)));
      ref.invalidate(maintenanceDetailProvider(sent.id));
      if (record != null && newParts && sent.items.any((i) => i.isPart)) {
        // stay so the new parts' photos can be added
        setState(() {
          _record = sent;
          _status = completeLater ? _status : sent.status;
          _setLines(sent.items);
        });
        _loadPhotos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(completeLater
                ? 'Saved. Add the new parts\' photos, then save again to mark it Completed.'
                : 'Saved. You can now add the photos of the new parts.'),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
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

  Future<void> _openPhotos(_PartRow p, int index, String stage) async {
    await showEvidenceSheet(
      context,
      path: _photoPath,
      itemId: p.id,
      title: p.particular.text.trim().isEmpty ? 'Part ${index + 1}' : p.particular.text.trim(),
      subtitle: p.additional ? 'Additional part' : 'Damaged part',
      stages: [
        if (!p.additional) const ('BEFORE', 'Pre-maintenance'),
        const ('AFTER', 'Post-maintenance'),
      ],
      initialStage: stage,
    );
    await _loadPhotos();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(outboxProvider); // photo counts include photos waiting to upload
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Maintenance' : 'New Maintenance')),
      // main button stays in reach at the bottom, however long the form
      bottomNavigationBar: FormActionBar(child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save Changes' : 'Create Record'),
            ),
          )),
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
            // a new record can't start as Completed: its photos are added after it is saved
            _enumDropdown('Status', _status,
              ['SCHEDULED', 'ONGOING', if (_isEdit) 'COMPLETED'], (v) => setState(() {
                _status = v!;
                if (_status == 'COMPLETED') _completedDate ??= _today();
              })),
            if (_completing)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Callout(
                    _parts.isNotEmpty
                        ? 'Each part needs its pre- and post-maintenance photos (additional parts only post-maintenance). '
                            'A repairable asset goes back to New, Good, or Serviceable by its age.'
                        : 'Marking it Completed needs at least one pre-maintenance and one post-maintenance photo (Photos). '
                            'A repairable asset goes back to New, Good, or Serviceable by its age.',
                    tone: CalloutTone.info),
              ),
            _datePicker('Maintenance Date', _maintenanceDate, DateTime(2000),
                DateTime.now().add(const Duration(days: 365)), (d) => setState(() => _maintenanceDate = d)),
            if (_status == 'COMPLETED')
              _datePicker('Date Completed', _completedDate,
                  _maintenanceDate != null && _maintenanceDate!.isBefore(_today()) ? _maintenanceDate! : _today(), _today(),
                  (d) => setState(() => _completedDate = d)),
            _field(_findings, 'Findings', required: true, maxLines: 3),
            _field(_actionsTaken, 'Particular (work done)', required: true, maxLines: 3),
            _field(_assignedTo, 'Assigned To'),
            const SizedBox(height: 4),
            _partsAndLabor(),
            const SizedBox(height: 14),
            if (_hasLines)
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Cost of Repair (₱)', helperText: 'The total of the parts and labor.'),
                child: Text(fmtMoney(_linesTotal),
                    style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
              )
            else
              _field(_cost, 'Cost of Repair (₱)', keyboardType: TextInputType.number),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _partsAndLabor() {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Parts and labor'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'List each damaged part with a pre-maintenance photo. When the repair is done, add a post-maintenance '
            'photo of each replacement part, and any additional part needed with its photo.',
            style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
          ),
        ),
        for (var i = 0; i < _parts.length; i++) _partCard(i),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Damaged part'),
            onPressed: () => setState(() => _parts.add(_PartRow())),
          ),
          if (_isEdit)
            OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Additional part'),
              onPressed: () => setState(() => _parts.add(_PartRow(additional: true))),
            ),
        ]),
        const SizedBox(height: 16),
        for (var i = 0; i < _labor.length; i++) _laborRow(i),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Labor'),
          onPressed: () => setState(() => _labor.add(_LaborRow())),
        ),
      ],
    );
  }

  Widget _partCard(int i) {
    final p = _parts[i];
    final c = context.colors;
    final canAddPhotos = p.id != null && _record != null && _record!.id > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Part ${i + 1}', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              if (p.additional) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Additional part', style: TextStyle(color: AppTheme.brand, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Remove part ${i + 1}',
                icon: Icon(Icons.close_rounded, size: 20, color: c.textTertiary),
                onPressed: () => setState(() => _parts.removeAt(i).dispose()),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(children: [
                TextFormField(controller: p.particular, decoration: const InputDecoration(labelText: 'Particular', hintText: 'e.g. Oil Filter'), maxLength: 255, buildCounter: _noCounter),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextFormField(controller: p.unit, decoration: const InputDecoration(labelText: 'Unit', hintText: 'pc'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: p.quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Qty'), onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: TextFormField(controller: p.unitCost, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Unit cost'), onChanged: (_) => setState(() {}))),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Total ${fmtMoney(p.total)}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: p.additional
                        ? Text('No pre-maintenance photo needed', style: TextStyle(color: c.textTertiary, fontSize: 13))
                        : _photoButton(p, i, 'BEFORE', 'Pre-maintenance', canAddPhotos),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _photoButton(p, i, 'AFTER', 'Post-maintenance', canAddPhotos)),
                ]),
                if (!canAddPhotos)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Save the record to add this part\'s photos.', style: TextStyle(color: c.textTertiary, fontSize: 13)),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  static Widget? _noCounter(BuildContext _, {required int currentLength, required bool isFocused, required int? maxLength}) => null;

  Widget _photoButton(_PartRow p, int i, String stage, String label, bool enabled) {
    final n = _photoCount(p, stage);
    return OutlinedButton.icon(
      icon: Icon(n > 0 ? Icons.check_circle_rounded : Icons.photo_camera_outlined, size: 18,
          color: n > 0 && enabled ? AppTheme.brand : null),
      label: Text(n > 0 ? '$label · $n' : label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
      onPressed: enabled ? () => _openPhotos(p, i, stage) : null,
    );
  }

  Widget _laborRow(int i) {
    final l = _labor[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(flex: 3, child: TextFormField(controller: l.particular,
            decoration: InputDecoration(labelText: 'Labor ${i + 1}', hintText: 'e.g. Change Oil Labor'))),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: TextFormField(controller: l.cost, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cost'), onChanged: (_) => setState(() {}))),
        IconButton(
          tooltip: 'Remove labor ${i + 1}',
          icon: Icon(Icons.close_rounded, size: 20, color: context.colors.textTertiary),
          onPressed: () => setState(() => _labor.removeAt(i).dispose()),
        ),
      ]),
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
                CodeText(_selectedAsset!.propertyNumber, size: 14),
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
      child: IosSelectFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        dropdownColor: context.colors.surface,
        items: options.map((e) => DropdownMenuItem(value: e, child: Text(titleCaseCode(e)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _datePicker(String label, DateTime? value, DateTime first, DateTime last, void Function(DateTime) onPicked) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () async {
          var initial = value ?? DateTime.now();
          if (initial.isBefore(first)) initial = first;
          if (initial.isAfter(last)) initial = last;
          final picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
          if (picked != null) onPicked(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(
            value != null ? _dateKey(value) : 'Tap to select',
            style: TextStyle(color: value != null ? context.colors.textPrimary : context.colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

