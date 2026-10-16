import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/provider/reference_provider.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ui.dart';
import '../../assets/model/asset_model.dart';
import '../../assets/provider/asset_provider.dart';
import '../../auth/provider/auth_provider.dart';
import '../data/transfer_service.dart';
import '../provider/transfer_provider.dart';
import '../../../shared/widgets/ios_pickers.dart';

/// "Transfer this asset" — the web Transfer Asset page's form: move to office and new
/// location (required), new accountable person and reason (optional). An admin's transfer
/// is applied at once; a staff member's becomes a request an admin approves.
class TransferFormScreen extends ConsumerStatefulWidget {
  final AssetModel asset;
  const TransferFormScreen({super.key, required this.asset});

  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _location = TextEditingController();
  final _reason = TextEditingController();
  int? _toOfficeId;
  int? _toPersonnelId;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _location.dispose();
    _reason.dispose();
    super.dispose();
  }

  // Staff: their own office (for an asset they can see, also the asset's office). Moving the asset
  // within it keeps the current accountable person by default; moving it anywhere else needs the
  // person who takes it over there (the transfer sets exactly this, so none = nobody). Same as web.
  bool _isOwnOffice(int? officeId) {
    if (officeId == null) return false;
    final me = ref.read(authProvider).valueOrNull;
    return officeId == me?.officeId || officeId == widget.asset.office.id;
  }

  bool _personRequired(bool isAdmin) => !isAdmin && _toOfficeId != null && !_isOwnOffice(_toOfficeId);

  int? _defaultPersonFor(int? officeId, bool isAdmin, List<PersonnelModel> people) {
    final current = widget.asset.accountablePerson?.id;
    if (isAdmin || current == null || !_isOwnOffice(officeId)) return null;
    return people.any((p) => p.id == current && p.officeId == officeId) ? current : null;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final status = await TransferService().submit(
        assetId: widget.asset.id,
        toOfficeId: _toOfficeId!,
        toPersonnelId: _toPersonnelId,
        toLocation: _location.text.trim(),
        reason: _reason.text,
      );
      ref.invalidate(transfersProvider);
      ref.invalidate(assetDetailProvider(widget.asset.id));
      ref.invalidate(assetsPagedProvider(ref.read(assetSearchProvider)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'APPLIED'
            ? 'Transferred — ${widget.asset.propertyNumber} has been moved.'
            : 'Request sent. An administrator will review the transfer.'),
      ));
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final isAdmin = ref.watch(authProvider).valueOrNull?.isAdmin ?? false;
    final officesAsync = ref.watch(officesProvider);
    final personnelAsync = ref.watch(personnelProvider);
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer Asset')),
      bottomNavigationBar: FormActionBar(
        child: ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.swap_horiz_rounded),
          label: Text(isAdmin ? 'Transfer Asset' : 'Send Transfer Request'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // the asset being moved, and where it is now
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CodeText(asset.propertyNumber, size: 14),
                    const SizedBox(height: 4),
                    Text(asset.description,
                        style: TextStyle(color: c.heading, fontSize: 19, height: 1.25, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      StatusBadge.condition(asset.condition),
                      StatusBadge.lifecycle(asset.lifecycleStatus),
                    ]),
                    const SizedBox(height: 12),
                    Text('NOW', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.textTertiary)),
                    const SizedBox(height: 4),
                    MetaLine(Icons.apartment_rounded, asset.office.officeName),
                    if (asset.location.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      MetaLine(Icons.place_rounded, asset.location),
                    ],
                    if (asset.accountablePerson != null) ...[
                      const SizedBox(height: 4),
                      MetaLine(Icons.person_rounded, asset.accountablePerson!.fullName),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Callout(
              isAdmin
                  ? 'As an administrator, the transfer is applied as soon as you submit it.'
                  : 'Your transfer is sent to an administrator for approval. The asset stays where it is until then.',
              tone: CalloutTone.info,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Callout(_error!, tone: CalloutTone.error),
            ],
            const SizedBox(height: 20),
            const SectionLabel('Move to'),
            officesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Callout('Could not load offices: $e', tone: CalloutTone.error),
              data: (offices) => IosSelectFormField<int>(
                initialValue: _toOfficeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Office (required)'),
                items: [
                  for (final o in offices)
                    DropdownMenuItem(value: o.id, child: Text(o.officeName, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _toOfficeId = v;
                  // the accountable person must belong to the new office; in their own office, staff
                  // keep the current one unless they pick someone else
                  _toPersonnelId = _defaultPersonFor(v, isAdmin, personnelAsync.valueOrNull ?? const []);
                }),
                validator: (v) => v == null ? 'Choose the office to transfer to.' : null,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _location,
              maxLength: 150,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'New location (required)',
                hintText: 'e.g. Room 204, 2nd Floor',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the new location.' : null,
            ),
            const SizedBox(height: 8),
            personnelAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (people) {
                final inOffice = _toOfficeId == null ? <PersonnelModel>[] : people.where((p) => p.officeId == _toOfficeId).toList();
                final required = _personRequired(isAdmin);
                return IosSelectFormField<int?>(
                  key: ValueKey(_toOfficeId), // reset when the office changes
                  initialValue: _toPersonnelId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: required ? 'New accountable person (required)' : 'New accountable person (optional)',
                    helperText: _toOfficeId == null
                        ? 'Choose an office first.'
                        : inOffice.isEmpty
                            ? 'No personnel are assigned to this office yet.'
                            : null,
                  ),
                  items: [
                    // the backend sets exactly this — null clears the accountable person (web: "— None —")
                    DropdownMenuItem<int?>(value: null, child: Text(required ? 'Select person' : 'None')),
                    for (final p in inOffice)
                      DropdownMenuItem<int?>(
                        value: p.id,
                        child: Text(
                            '${p.position != null ? '${p.fullName} — ${p.position}' : p.fullName}'
                            '${p.id == asset.accountablePerson?.id ? ' (current)' : ''}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  validator: (v) => required && v == null ? 'Choose who will be accountable for it in the new office.' : null,
                  onChanged: _toOfficeId == null ? null : (v) => setState(() => _toPersonnelId = v),
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              maxLength: 500,
              maxLines: 3,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Reassigned to the new Records Officer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
